# subby.rb
Automatic ruby script to flag audio, subtitle track language via mkv flags and mkvpropedit.
The main usecase is to flag Anime, foreign content so the prefered audio/subtitle combo is picked by the player.
Most video players, Media Centers have too basic options to handle complexer cases, thats where "subby" comes in!

### Disclaimer
The script itself has no delete/remux logic and will not change the actual streams in any way, so should be safe to use.
I tested it with ~1000 files and had no issues.
What you may loose is the original 'default', 'forced' flag settings, since thats what the script will change, operates on.
So test it before you point it to your main collection!
- mpc-hc on windows will properly show the current flags in its filters/track options

# Requirements
1. mkvpropedit via https://mkvtoolnix.download/downloads.html
   - put `mkvpropedit` in the script dir or search PATH variable
3. Ruby script interpreter
   - https://rubyinstaller.org
   - https://www.ruby-lang.org/en/downloads/
   - via https://chocolatey.org `choco install ruby`

# Useage via commandline
- `ruby subby.rb`
- `rubyw subby.rb` without cmd prompt on windows
- edit the `settings.rb` file to your liking!
  - You must add at least one directory you want the script to operate on!

## Features
- does not remux or alter any tracks/streams, only the mkv flags are set inplace!
  - therefor can work on huge librarys in seconds, minutes
- automatically flag mkv audio/subtitle tracks based on user defined score/heuristics *(default, forced, disable)*
  - heuristics include:
    - NATIVE_LANGUAGES
    - AUDIO_LANGUAGES
    - AUDIO_CODECS
    - AUDIO_CHANNELS
    - SUBTITLE_CODECS
    - SUBTITLE_LANGUAGES
    - TRACK_FILTERS
- works similar to Sonarr/Radarr and evaluates/scores each track, than picks the track with the highest score
- allows filtering via track name words *(signs, sdh....)* to improve matching
- can setup multiple directory paths to operate on
  - can directly work on network paths
- can operate in multiple audio/subtitle modes ('default', 'forced', 'disable', 'enable')

### Note on mkv Flags and operation modes: *settings.rb (AUDIO_MODE, SUBTITLE_MODE)*
- `'default'` = "many" players will pick 'default' flagged tracks by default, if there are no other user settings in place that overrides this
- `'forced'`  = nearly all players will honor 'forced' subtitles tracks, while some may also favor 'forced' audio tracks
- `'disable'` = disables the track, making it "invisible" to some players *(LAV filters work)* Note: The track is still there, just hidden!
- `'enable'`  = re/enables all tracks, used to revert 'disable' changes

## Recommendations
- `AUDIO_MODE = ['default']` This is a good starting point for audio tracks, see if you player correctly picks the new set default track
  - make sure you favor default tracks in your player or remove any setup languages preferences
- `SUBTITLE_MODE = ['default','forced']` This sets both flags on the picked subtitle track, this should work on all players.
- `AUDIO_MODE = ['default','disable']` This hides all none picked audio tracks, "may" work in cases where the player stubbornly refuses to pick the default/forced track. At least works if LAV filters are used with default settings, other players may choose to ignore the 'enabled' flag!

### Note on the settings.rb
- the heuristic array entries all look like this `['name' => value]` you can move the entries around or change the value similar to Sonarr/Profile preferred entries!
- the name values are just simple strings, so no RegEx is supported as of now!
- you should always value languages much higher aka 100+, while codec, filters can be adapted to your liking
