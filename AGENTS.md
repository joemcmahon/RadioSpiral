# RadioSpiral iOS app

The RadioSpiral player for iPhone and CarPlay (UIKit, CocoaPods + Swift Package Manager).
Station, server and people background: the `radiospiral` page of the knowledge wiki.
Current status: `docs/HANDOFF.md`.

## Build and test

```bash
xcodebuild build -scheme RadioSpiral -configuration Debug
xcodebuild test  -scheme ConfigClientTests -destination 'platform=iOS Simulator,name=<sim>'
```
Real-device testing uses an iPhone 13 Pro; CarPlay is tested in the CarPlay Simulator.
`CARPLAY-UPGRADE.md` documents the CarPlay work.

## Architecture notes

- **Station list loading** goes through a fallback chain: `ConfigClient` (remote `config.json`
  from the `radiospiral-config` repo, with live AzuraCast lookup) → bundled `stations.json`
  → HTTP `stations.json`. It is toggled by `Config.useConfigClient`. The remote config has an
  exclude list (e.g. `rstest`).
- **Now-playing metadata** falls back AzuraCast → FRadioPlayer → ConfigClient + RadioStation →
  RadioStation.
- Key code: `RadioSpiral/ConfigClient/` (ConfigClient, StationConfig), `RadioSpiral/Model/RadioStation.swift`
  (`init(from: StationConfig)`), `StationMetadataManager`, `DataManager`, `NowPlayingViewController`.
- When adding a Swift file, register it in `project.pbxproj` for every target that needs it
  (the app and `ConfigClientTests`).

## Decisions to respect

- The audio-mode (lock/ear) button and the time bubble are phone-only, not on CarPlay.
- `backlog/` is local-only (gitignored): never commit or push task files, never `git add -f`.
  Follow `docs/backlog-guidelines.md` when writing a task by hand (the CLI isn't installed).
- `docs/archive/` holds old handoffs and plans and is also kept local.
