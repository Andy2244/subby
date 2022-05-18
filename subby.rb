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

if FILES_DIRS.nil? || FILES_DIRS.empty?
  abort('ABORTED! FILES_DIRS is empty! (check settings.rb)')
end
if AUDIO_MODE.include?('enable') && AUDIO_MODE.include?('disable')
  abort('ABORTED! Cant use AUDIO_MODE with enable + disable, simultaneously !')
end
if SUBTITLE_MODE.include?('enable') || SUBTITLE_MODE.include?('disable')
  abort('ABORTED! SUBTITLE_MODE does not support enable, disable modes!')
end

FILES_DIRS.each do |in_dir|
  next unless File.directory?(in_dir)

  Dir["#{in_dir}/**/*.mkv"].each do |in_file|
    next unless File.file?(in_file)

    json = identify_file in_file
    arguments = []
    default_audio = nil
    default_subtitle = nil
    forced_audio = nil
    forced_subtitle = nil

    # internal
    _audio_tracks = Array.new(0) { Array.new(0) }
    _subtitle_tracks = Array.new(0) { Array.new(0) }

    puts "processing File: #{in_file}"

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
        default_audio = in_track if in_track['properties']['default_track']
        forced_audio = in_track if in_track['properties']['forced_track']
      when 'subtitles'
        value_sum += SUBTITLE_LANGUAGES[in_track['properties']['language']]
        value_sum += SUBTITLE_CODECS[in_track['codec']]
        if in_track['properties']['track_name']
          TRACK_FILTERS.each do |key, value|
            value_sum += value if in_track['properties']['track_name'].downcase.include?(key)
          end
        end
        _subtitle_tracks.push([value_sum, in_track])
        default_subtitle = in_track if in_track['properties']['default_track']
        forced_subtitle = in_track if in_track['properties']['forced_track']
      else
        # type code here
      end
    end

    # sort value arrays, best is at [0]
    _audio_tracks = _audio_tracks.sort_by { |key, value| key }.reverse!
    _subtitle_tracks = _subtitle_tracks.sort_by { |key, value| key }.reverse!

    # set default
    if AUDIO_MODE.include?('default') && _audio_tracks.length > 1
      if !default_audio.nil? && !_audio_tracks[0].nil? && default_audio == _audio_tracks[0][1]
        # puts 'audio default already set!'
      else
        arguments += ['--edit', "track:=#{_audio_tracks[0][1]['properties']['uid']}", '--set', 'flag-default=1']
        unless default_audio.nil?
          arguments += ['--edit', "track:=#{default_audio['properties']['uid']}", '--set', 'flag-default=0']
        end
      end
    end

    # set forced
    if AUDIO_MODE.include?('forced') && _audio_tracks.length > 1
      if !forced_audio.nil? && !_audio_tracks[0].nil? && forced_audio == _audio_tracks[0][1]
        # puts 'audio forced already set!'
      else
        arguments += ['--edit', "track:=#{_audio_tracks[0][1]['properties']['uid']}", '--set', 'flag-forced=1']
        unless forced_audio.nil?
          arguments += ['--edit', "track:=#{forced_audio['properties']['uid']}", '--set', 'flag-forced=0']
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

    is_native_audio = !_audio_tracks[0].nil? && NATIVE_LANGUAGES.any?(_audio_tracks[0][1]['properties']['language'])
    # default subtitles
    if SUBTITLE_MODE.include?('default') && !_subtitle_tracks[0].nil?
      if is_native_audio
        unless default_subtitle.nil?
          arguments += ['--edit', "track:=#{default_subtitle['properties']['uid']}", '--set', 'flag-default=0']
        end
      elsif !default_subtitle.nil? && !_subtitle_tracks[0].nil? && default_subtitle == _subtitle_tracks[0][1]
        # puts 'subtitle already set!'
      else
        arguments += ['--edit', "track:=#{_subtitle_tracks[0][1]['properties']['uid']}", '--set', 'flag-default=1']
        unless default_subtitle.nil?
          arguments += ['--edit', "track:=#{default_subtitle['properties']['uid']}", '--set', 'flag-default=0']
        end
      end
    end

    # forced subtitles
    if SUBTITLE_MODE.include?('forced') && !_subtitle_tracks[0].nil?
      if is_native_audio
        # unless forced_subtitle.nil?
        #   arguments += ['--edit', "track:=#{forced_subtitle['properties']['uid']}", '--set', 'flag-forced=0']
        # end
        # keep org. forced?
      elsif !forced_subtitle.nil? && !_subtitle_tracks[0].nil? && forced_subtitle == _subtitle_tracks[0][1]
        # puts 'subtitle already set!'
      else
        arguments += ['--edit', "track:=#{_subtitle_tracks[0][1]['properties']['uid']}", '--set', 'flag-forced=1']
        unless forced_subtitle.nil?
          arguments += ['--edit', "track:=#{forced_subtitle['properties']['uid']}", '--set', 'flag-forced=0']
        end
      end
    end

    # process arguments and write the actual changes
    next if arguments.empty?

    File.write("_files_changed_#{TIMESTAMP}.log", "#{in_file}\n", mode: 'a')
    # puts "Editing #{in_file}"
    edit_file_properties [in_file] + arguments
    did_change = true
  end
end

if did_change
  puts "Logfile written inside the script dir: <_files_changed_#{TIMESTAMP}.log>"
end
exit(true)
