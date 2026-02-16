# RadioSpiral

<p align="center">
    <img alt="RadioSpiral screen" src="https://pemungkah.com/wp-content/uploads/2023/11/Screenshot-Small.png">
</p>

RadioSpiral started out as a port of the [Swift Radio Pro](https://github.com/analogcode/Swift-Radio-Pro) app specifically designed to work with our old AirTime/[LibreTime](https://github.com/libretime/libretime) server, and functioned extremely well for that.

However, LibreTime stalled out on upgrades, and we found the constant need to regenerate the automated playlists onerous (and easy to forget; we had more than one long outage because we didn't remember to rebuild the playlists!). We searched around for an option that would work better for us, and found [Azuracast](https://www.azuracast.com/). Out of the box, Azuracast drastically simplified the work we needed to do to keep the station going, so we switched...and discovered that the Icecast instance that Azuracast runs doesn't supply metadata.

We limped along for a few months with no "now-playing" data or album covers, and I eventually embarked on a major rewrite to fix the problems:

 - No metadata or album covers -- this entailed building out a new class to use Azuracast's web socket interface to receive dynamic metadata updates, which include the album artwork directly; no more repending on the iTunes API, which more than once made some very funny choices when the actual album in question wasn't on iTunes.
 - Poor performance when the device was rotated or split screen was used on the iPad -- the controls would rotate offscreen, making it impossible to use the app without rotating the device back or unsplitting
 - No MacOS support -- we had a not-so-great _Objective-C_ app that could stream audio, but it was a definite lesser option. (We did retain it for older versions of MacOS, though).
 - Sometimes the controls were fussy; a start-stop-start might restart, or it might be necessary to do it a couple times to get the audio to resume.
 - Connectivity issues didn't self-resolve very well; if the signal dropped (say, walking out to the car and going out of WiFi range and into cellular), very often you'd have to manually restart playback. Sometimes it was even necessary to completely relaunch the app.

So I decided to look at the code, and update it significantly to work more smoothly overall, and in particular to work well with Azuracast's APIs to allow us (the station) more flexibility to dynamically add or remove streams, and to take advantage of Azuracast's real-time metadata updating.

## The new codebase

We needed to completely revamp metadata management, as FRadioPlayer (the existing audio engine) had been doing double duty as the audio streaming engine and the metadata manager, responsible not only for playback, but for capturing the Icecast metadata, poking the iTunes API for covers, and managing the lockscreen display. The new metadata management worked like this:

### Added

 - ACWebSocketClient — Custom WebSocket client for real-time Azuracast metadata with connection state machine, liveness timer, exponential backoff reconnection. Using the websocket protocol allowed us to receive async dynamic updates without having to run a process to do it (long-running background processes are a sure ticket to Terminationsville on iOS).
 - StationMetadataManager — Unified metadata with fallback chain (Azuracast → ConfigClient → RadioStation defaults), Combine-based distribution. This moved the metadata management into its own class and out of FRadioPlayer, since it couldn't get good metadata from Icecast anymore.
 - ConfigClient — Dynamic station loading from Azuracast API with smart fallback chain, station exclusion lists. Allows us to use Azuracast's multiple-stream feature and dynamically add and remove "stations" (i.e. streams) from the station list, controlled by the data Azuracast sends via its APIs.
 - RadioPlayer — Thin AVPlayer wrapper (~120 lines) replacing FRadioPlayer (~600 lines). No internal Reachability, no metadata parsing, Combine publishers. Allows us to drastically simplify connection management, and prevents the playback engine from trying to second-guess connection status overall.
 - CarPlaySceneDelegate — Modern CarPlay framework (iOS 14+) using CPTemplateApplicationSceneDelegate, replacing deprecated MPPlayableContentManager. This is an upgrade of the CarPlay feature in Swift Radio Pro: function is the same, but it uses the new (non-deprecated) CarPlay framework.
 - SceneDelegate + MainCoordinator — Modern scene-based lifecycle with coordinator navigation pattern. Moves the app into modern UIKit.
 - Connection recovery system — Multi-layer: liveness timer, scheduleReconnect() with exponential backoff, wasPlaying flag for auto-restart, connection status      
  banner. Makes the app more resilient and shows status better to the user.

### Removed

  - FRadioPlayer — About 600 lines including bundled Reachability, ICY metadata parsing, iTunes API integration). I gradually trimmed it down to only handling streaming, and when I started having trouble with conflicting connection recovery logic (which was eating a _lot_ of battery), it was time to replace it with something lighter.
  - Reachability — A second Reachability instance was embedded in the metadata management, and after I found that it was not being dependable -- fired minutes late on iOS WiFi drop, actively blocked recovery -- I removed it completely.
  - The FRadioPlayerObserver protocol was replaced by Combine publishers, making monitoring status a "let me ask" instead of an "I'm telling you _now_".
  - AppDelegate was stripped way down and moved into ConfigClient: isAutoPlay, enableArtwork, artworkAPI all were removed.

### Architecture Changes

  - Metadata: ICY stream parsing was upgraded to Azuracast WebSocket real-time metadata
  - Reactivity: Delegation/observer protocols switched to Combine (`@Published`, sinks, `AnyCancellable`)
  - Station loading: We now have a three-layer fallback: we try Azuracast's station API, then the old GitHub-hosted static config, and finally internal config.
  - Connection recovery: FRadioPlayer-internal Reachability → External multi-layer state machine with exponential backoff
  - CarPlay: Removed the deprecated MPPlayableContentManager and upgraded to modern CPTemplateApplicationSceneDelegate

## Current status

This branch has been updated to build under Xcode 26 and Swift 5.

We use SPM for dependency management: Spring for enhanced UI, Kingfisher for wasy image management, NVActivityIndicatorView for our "playing" animation.

RadioSpiral is no longer a generic radio app, but one tuned specifically for our purposes and server. I do want to credit the Swift Radio Pro developers for 
providing me with a great platform that I've turned into a mutant of my own design:

- **Co-organizer & current-lead developer of Swift Radio Pro, [Fethi El Hassasna](https://fethica.com), Twitter: [@fethica](https://twitter.com/fethica)** 
- **Created by [Matthew Fecher](http://matthewfecher.com) from [AudioKit Pro](https://audiokitpro.com), Twitter: [@analogMatthew](http://twitter.com/analogMatthew)**  
- *Contributions by others listed in Github [here](https://github.com/swiftcodex/Swift-Radio-Pro/graphs/contributors).*
