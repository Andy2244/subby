#!/usr/bin/env ruby
# frozen_string_literal: true

# process all MKVs in those directory's and all sub-directory's NOTE: use / instead of \ , also dont forget the ',' at the end!
FILES_DIRS = [
  # 'd:/my_anime',

  # can work with direct network paths
  #'//servername_or_ip/smb_sharename/foldername',
]

# Flag's support depends on the player, most support 'forced', some 'default' and maybe 'disabled'
# Set a operation mode or multiple (disable = will disable the track, making it invisible to supported players, enable = reverts this)
# Audio Operation-Mode 'default','forced','disable','enable'
AUDIO_MODE = ['default']
# Subtitle Operation-Mode 'default','forced' NOTE: we dont support enable/disable sub tracks as of right now
SUBTITLE_MODE = ['default','forced']

# Languages settings use only 3 letter ISO codes! https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
# what languages you speak natively, can have multiple ['eng','spa','ger']
NATIVE_LANGUAGES = ['eng']
# what are your languages preferences for audio, rate wanted foreign original higher
AUDIO_LANGUAGES = {
  'jpn' => 122,
  'kor' => 121,
  'chi' => 120,
  'eng' => 100,
}
# audio codec priorities, here we avoid DTS if possible
AUDIO_CODECS = {
  'TrueHD Atmos' => 6,
  'AC-3 Dolby Surround EX' => 5,
  'E-AC-3' => 4,
  'AC-3' => 3,
  'DTS-HD Master Audio' => 2,
  'DTS-HD High Resolution Audio' => 1,
  'DTS' => 0,
}
# audio channel priorities (channel numbers => priority), in this example we favor 6 channel tracks!
AUDIO_CHANNELS = {
  8 => 9,
  7 => 8,
  6 => 10,
  5 => 7,
  4 => 6,
  3 => 5,
}
# your preferred subtitle languages, 'und' means undefined and can help on bad tagged files
SUBTITLE_LANGUAGES = {
  'eng' => 100,
  'und' => 30,
  'ger' => 10,
}
# filter strings for the track names, we usually want full dialog audio/subtitles, we use negative values to avoid those tracks
TRACK_FILTERS = {
  'dialog' => 10,
  'full' => 9,
  'non_honorific' => 2,
  'subtitle' => 1,
  'commentar' => -199,
  'sign' => -200,
  'sing' => -200,
  'song' => -200,
  'shd' => -200,
}
# preferred subtitle codec, here we prefer ASS
SUBTITLE_CODECS = {
  'SubStationAlpha' => 2,
  'SubRip/SRT' => 1,
  'HDMV PGS' => 0,
}
