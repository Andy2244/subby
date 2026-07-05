#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
$log_dir = File.join(Dir.home, '.subby')
FileUtils.mkdir_p($log_dir)

$stdout.sync = true
if Gem.win_platform?
  $stdout.set_encoding('UTF-8')
  $stderr.set_encoding('UTF-8')
  system 'chcp 65001 > NUL 2>&1'
end

$cache = nil
$cache_path = nil
$cache_dirty = false

at_exit do
  cache_save($cache, $cache_path) if $cache && $cache_path && $cache_dirty
  if $! && !$!.is_a?(SystemExit)
    puts "\nERROR: #{$!.class}: #{$!.message}"
    puts $!.backtrace&.first(3)&.join("\n")
  end
end

require_relative 'mtxlib'
require_relative 'mtxcache'
require_relative 'settings'

# defaults for settings.rb files predating these
SDH_FLAG_PENALTY = -200 unless defined?(SDH_FLAG_PENALTY)
SUBTITLE_TRACK_FILTERS = {} unless defined?(SUBTITLE_TRACK_FILTERS)

AUDIO_LANGUAGES.default = 0
AUDIO_CODECS.default = 0
AUDIO_CHANNELS.default = 0
SUBTITLE_LANGUAGES.default = 0
TRACK_FILTERS.default = 0
SUBTITLE_CODECS.default = 0

TIMESTAMP = Time.now.strftime("%Y-%m-%d_%H-%M")
did_change = false
file_count = 0

if FILES_DIRS.nil? || FILES_DIRS.empty?
  abort('ABORTED! FILES_DIRS is empty! (check settings.rb)')
end
%w[mkvmerge mkvpropedit].each do |bin|
  unless system("#{bin} --version", [:out, :err] => File::NULL)
    abort("ABORTED! '#{bin}' not found! Install mkvtoolnix and make sure it's on your PATH.")
  end
end
if AUDIO_MODE.include?('enable') && AUDIO_MODE.include?('disable')
  abort('ABORTED! Cant use AUDIO_MODE with enable + disable, simultaneously !')
end
if SUBTITLE_MODE.include?('enable') || SUBTITLE_MODE.include?('disable')
  abort('ABORTED! SUBTITLE_MODE does not support enable, disable modes!')
end
if SUBTITLE_MODE.include?('forced') && SUBTITLE_MODE.include?('forced_clean')
  abort('ABORTED! SUBTITLE_MODE cant use forced + forced_clean, simultaneously !')
end

puts "%-12s %s" % ["[changes]", "file"]
puts "-" * 40

$cache_path = USE_CACHE ? File.join($log_dir, 'subby_cache.json') : nil
$cache = USE_CACHE ? cache_load($cache_path) : { 'version' => CACHE_VERSION, 'entries' => {} }
if USE_CACHE
  puts "cache: #{$cache_path} (#{$cache['entries'].length} entries loaded)"
else
  puts "cache: disabled (USE_CACHE = false)"
end

# collect full file list once, then identify in parallel via worker pool
mkv_files = []
FILES_DIRS.each do |in_dir|
  next unless File.directory?(in_dir)
  Dir["#{in_dir}/**/*.mkv"].each do |f|
    mkv_files << File.expand_path(f) if File.file?(f)
  end
end
mkv_files.uniq!
total_files = mkv_files.length

# process one identified file: scoring + mkvpropedit + log. runs in main thread only
process_file = lambda do |in_file, json|
  if json.is_a?(Array) && json[0] == :error
    puts "WARNING: mkvmerge failed for: #{in_file}"
    puts "  output: #{json[1]}" if json[1] && !json[1].empty?
    return
  end
  unless json.is_a?(Hash) && json['tracks'].is_a?(Array)
    puts "SKIPPING (no track data): #{in_file}"
    return
  end

  arguments = []

    # internal
    _audio_tracks = Array.new(0) { Array.new(0) }
    _subtitle_tracks = Array.new(0) { Array.new(0) }

    # parse and value tracks
    json['tracks'].each do |in_track|
      value_sum = 0
      case in_track['type']
      when 'audio'
        value_sum += AUDIO_LANGUAGES[in_track['properties']['language']]
        value_sum += AUDIO_CODECS[in_track['codec']]
        value_sum += AUDIO_CHANNELS[in_track['properties']['audio_channels']]
        if in_track['properties']['track_name']
          TRACK_FILTERS.each do |key, value|
            value_sum += value if in_track['properties']['track_name'].downcase.include?(key)
          end
        end
        # existing default flag only breaks ties (fractional) -> repeat runs stay stable
        value_sum += 0.5 if in_track['properties']['default_track']
        _audio_tracks.push([value_sum, in_track])
      when 'subtitles'
        value_sum += SUBTITLE_LANGUAGES[in_track['properties']['language']]
        value_sum += SUBTITLE_CODECS[in_track['codec']]
        if in_track['properties']['track_name']
          TRACK_FILTERS.merge(SUBTITLE_TRACK_FILTERS).each do |key, value|
            value_sum += value if in_track['properties']['track_name'].downcase.include?(key)
          end
        end
        value_sum += SDH_FLAG_PENALTY if in_track['properties']['flag_hearing_impaired']
        value_sum += 0.5 if in_track['properties']['default_track']
        _subtitle_tracks.push([value_sum, in_track])
      else
        # type code here
      end
    end

    # sort value arrays, best is at [0]; index tie-break keeps mux order on equal
    # scores (Ruby sort is not stable -- sort-then-reverse once flagged a commentary track)
    _audio_tracks = _audio_tracks.each_with_index.sort_by { |(key, _track), index| [-key, index] }.map(&:first)
    _subtitle_tracks = _subtitle_tracks.each_with_index.sort_by { |(key, _track), index| [-key, index] }.map(&:first)

    audio_args_before = arguments.length
    # set audio default: flag winner, clear all others
    if AUDIO_MODE.include?('default') && _audio_tracks.length > 1
      winner = _audio_tracks[0][1]
      unless winner['properties']['default_track']
        arguments += ['--edit', "track:=#{winner['properties']['uid']}", '--set', 'flag-default=1']
      end
      _audio_tracks.each do |_, track|
        next if track == winner
        if track['properties']['default_track']
          arguments += ['--edit', "track:=#{track['properties']['uid']}", '--set', 'flag-default=0']
        end
      end
    end

    # set audio forced: flag winner, clear all others
    if AUDIO_MODE.include?('forced') && _audio_tracks.length > 1
      winner = _audio_tracks[0][1]
      unless winner['properties']['forced_track']
        arguments += ['--edit', "track:=#{winner['properties']['uid']}", '--set', 'flag-forced=1']
      end
      _audio_tracks.each do |_, track|
        next if track == winner
        if track['properties']['forced_track']
          arguments += ['--edit', "track:=#{track['properties']['uid']}", '--set', 'flag-forced=0']
        end
      end
    end

    # set disable
    if AUDIO_MODE.include?('disable') && _audio_tracks.length > 1
      _audio_tracks.each do |in_track|
        if !_audio_tracks[0].nil? && in_track[1] != _audio_tracks[0][1] && in_track[1]['properties']['enabled_track'] == true
          arguments += ['--edit', "track:=#{in_track[1]['properties']['uid']}", '--set', 'flag-enabled=0']
        end
      end
      if !_audio_tracks[0].nil? && _audio_tracks[0][1]['properties']['enabled_track'] == false
        arguments += ['--edit', "track:=#{_audio_tracks[0][1]['properties']['uid']}", '--set', 'flag-enabled=1']
      end
    end
    # set enable NOTE: we prioritise this over disabled
    if AUDIO_MODE.include?('enable') && !_audio_tracks.empty?
      _audio_tracks.each do |in_track|
        if in_track[1]['properties']['enabled_track'] == false
          arguments += ['--edit', "track:=#{in_track[1]['properties']['uid']}", '--set', 'flag-enabled=1']
        end
      end
    end

    changed_audio = arguments.length > audio_args_before

    is_native_audio = !_audio_tracks[0].nil? && NATIVE_LANGUAGES.any?(_audio_tracks[0][1]['properties']['language'])
    sub_args_before = arguments.length
    # set subtitle default: flag winner, clear all others (skip if native audio)
    if SUBTITLE_MODE.include?('default') && !_subtitle_tracks[0].nil?
      winner = _subtitle_tracks[0][1]
      if is_native_audio
        # native audio: no subtitle default needed, clear any that are set
        _subtitle_tracks.each do |_, track|
          if track['properties']['default_track']
            arguments += ['--edit', "track:=#{track['properties']['uid']}", '--set', 'flag-default=0']
          end
        end
      else
        unless winner['properties']['default_track']
          arguments += ['--edit', "track:=#{winner['properties']['uid']}", '--set', 'flag-default=1']
        end
        _subtitle_tracks.each do |_, track|
          next if track == winner
          if track['properties']['default_track']
            arguments += ['--edit', "track:=#{track['properties']['uid']}", '--set', 'flag-default=0']
          end
        end
      end
    end

    # set subtitle forced: flag winner, clear all others (skip if native audio, keep org. forced)
    if SUBTITLE_MODE.include?('forced') && !_subtitle_tracks[0].nil?
      winner = _subtitle_tracks[0][1]
      unless is_native_audio
        unless winner['properties']['forced_track']
          arguments += ['--edit', "track:=#{winner['properties']['uid']}", '--set', 'flag-forced=1']
        end
        _subtitle_tracks.each do |_, track|
          next if track == winner
          if track['properties']['forced_track']
            arguments += ['--edit', "track:=#{track['properties']['uid']}", '--set', 'flag-forced=0']
          end
        end
      end
    end

    # forced_clean subtitles: explicitly clear ALL forced flags from all subtitle tracks
    if SUBTITLE_MODE.include?('forced_clean')
      _subtitle_tracks.each do |_, track|
        if track['properties']['forced_track']
          arguments += ['--edit', "track:=#{track['properties']['uid']}", '--set', 'flag-forced=0']
        end
      end
    end

    changed_sub = arguments.length > sub_args_before

    # process arguments and write the actual changes
    next if arguments.empty?

  # invalidate before the edit attempt so a Ctrl-C/exception during mkvpropedit
  # can't leave a stale pre-edit entry that at_exit would persist. mkvpropedit only
  # rewrites header bytes, so mtime/size stay the same and we can't rely on the
  # next run's stat check to catch it.
  cache_invalidate($cache, in_file) if USE_CACHE
  edit_file_properties [in_file] + arguments
  tags = [changed_audio ? 'audio' : nil, changed_sub ? 'sub' : nil].compact.join('+')
  puts "%-12s %s" % ["[#{tags}]", in_file]
  File.write(File.join($log_dir, "subby_#{TIMESTAMP}.log"), "%-12s %s\n" % ["[#{tags}]", in_file], mode: 'a')
  did_change = true
end

# split into cache hits (instant, no mkvmerge) and misses (route through identify)
cache_hits = []
cache_misses = []
mkv_files.each do |f|
  if USE_CACHE && (json = cache_get($cache, f))
    cache_hits << [f, json]
  else
    cache_misses << f
  end
end

# process cache hits immediately on the main thread
cache_hits.each do |in_file, json|
  file_count += 1
  print "scanning files: #{file_count}/#{total_files}\r"
  process_file.call(in_file, json)
end

worker_count = [[PARALLEL_ANALYSIS.to_i, 1].max, [cache_misses.length, 1].max].min

if cache_misses.empty?
  # all hits, nothing to identify
elsif worker_count <= 1
  # sequential path (original behavior, no thread overhead)
  cache_misses.each do |in_file|
    file_count += 1
    print "scanning files: #{file_count}/#{total_files}\r"
    pre_stat = USE_CACHE ? (File.stat(in_file) rescue nil) : nil
    json = identify_file(in_file)
    cache_put($cache, in_file, json, pre_stat) if USE_CACHE && pre_stat && json.is_a?(Hash) && json['tracks'].is_a?(Array)
    process_file.call(in_file, json)
  end
else
  # parallel: N workers run identify_file concurrently, main thread consumes results serially
  require 'thread'
  in_queue = Queue.new
  out_queue = Queue.new
  cache_misses.each { |f| in_queue << f }
  worker_count.times { in_queue << :stop }

  Array.new(worker_count) do
    Thread.new do
      begin
        loop do
          item = in_queue.pop
          break if item == :stop
          begin
            pre_stat = USE_CACHE ? (File.stat(item) rescue nil) : nil
            json = identify_file(item)
            out_queue << [:result, item, json, pre_stat]
          rescue StandardError => e
            out_queue << [:result, item, [:error, "#{e.class}: #{e.message}"], nil]
          end
        end
      ensure
        out_queue << :worker_done
      end
    end
  end

  workers_alive = worker_count
  while workers_alive > 0
    msg = out_queue.pop
    if msg == :worker_done
      workers_alive -= 1
      next
    end
    _tag, in_file, json, pre_stat = msg
    file_count += 1
    print "scanning files: #{file_count}/#{total_files}\r"
    cache_put($cache, in_file, json, pre_stat) if USE_CACHE && pre_stat && json.is_a?(Hash) && json['tracks'].is_a?(Array)
    process_file.call(in_file, json)
  end
end

print "\r#{' ' * 40}\r"
puts "-" * 40
puts "scanned #{file_count} files"
if did_change
  puts "Logfile: #{File.join($log_dir, "subby_#{TIMESTAMP}.log")}"
end
exit(true)
