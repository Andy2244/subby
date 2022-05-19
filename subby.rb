#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'mtxlib'
require_relative 'settings'

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

FILES_DIRS.each do |in_dir|
  next unless File.directory?(in_dir)

  Dir["#{in_dir}/**/*.mkv"].each do |in_file|
    next unless File.file?(in_file)

    file_count += 1
    print "scanning files: #{file_count}\r"

    json = identify_file in_file
    unless json.is_a?(Hash) && json['tracks'].is_a?(Array)
      puts "SKIPPING (no track data): #{in_file}"
      next
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
        _audio_tracks.push([value_sum, in_track])
      when 'subtitles'
        value_sum += SUBTITLE_LANGUAGES[in_track['properties']['language']]
        value_sum += SUBTITLE_CODECS[in_track['codec']]
        if in_track['properties']['track_name']
          TRACK_FILTERS.each do |key, value|
            value_sum += value if in_track['properties']['track_name'].downcase.include?(key)
          end
        end
        _subtitle_tracks.push([value_sum, in_track])
      else
        # type code here
      end
    end

    # sort value arrays, best is at [0]
    _audio_tracks = _audio_tracks.sort_by { |key, value| key }.reverse!
    _subtitle_tracks = _subtitle_tracks.sort_by { |key, value| key }.reverse!

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

    edit_file_properties [in_file] + arguments
    tags = [changed_audio ? 'audio' : nil, changed_sub ? 'sub' : nil].compact.join('+')
    puts "\u2714 #{in_file} [#{tags}]"
    File.write("_files_changed_#{TIMESTAMP}.log", "#{in_file} [#{tags}]\n", mode: 'a')
    did_change = true
  end
end

puts "scanned #{file_count} files"
if did_change
  puts "Logfile written inside the script dir: <_files_changed_#{TIMESTAMP}.log>"
end
exit(true)
