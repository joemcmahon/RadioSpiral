# RadioSpiral iOS app

The RadioSpiral player for iPhone and CarPlay (UIKit, Swift Package Manager).
Station, server and people background: the `radiospiral` page of the knowledge wiki.
Current status: `docs/HANDOFF.md`.

## Build and test

```bash
xcodebuild build -scheme RadioSpiral -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -scheme ConfigClientTests -destination 'platform=iOS Simulator,name=iPhone 17'
```
Without `-destination`, `xcodebuild` does a signed device build, which can bring up a Keychain
prompt: warn Joe before running one.

`ConfigClient` and `CreditsClient` tests use canned responses (`StubURLProtocol`), so they need no
network. The exception is `LiveServerSmokeTests`, two labeled tests that check the live formats of
`spiral.radio/api/stations` and the GitHub `config.json`. They skip on a connection problem or a
server error, and fail only on a format change. Don't rerun them in loops. Other tests may start real
connections from the running app, so check connectivity before treating a failure as a regression.

Real-device testing uses an iPhone 13 Pro; CarPlay is tested in the CarPlay Simulator.
`CARPLAY-UPGRADE.md` documents the CarPlay work.

## Architecture notes

- **Station list loading** uses one source, chosen by flags in `DataManager.getStation`:
  `Config.useConfigClient`, then `useLocalStations` (bundled `stations.json`), then HTTP
  `stations.json`. These are not a runtime fallback: with the current flags only `ConfigClient`
  runs, and its failure goes to the error and retry screen in `LoaderController`.
- **`ConfigClient`** loads the remote `config.json` from the `radiospiral-config` repo. TestFlight
  and Xcode builds can select `config-test.json` on the About screen (`StationServer`). It tries
  the listed sources in order (AzuraCast public API, then admin API; or a static list), then its
  stations cached in memory. AzuraCast sources have an exclude list (e.g. `rstest`).
- **Now-playing metadata** comes from the AzuraCast WebSocket, then falls back to station info
  (`ConfigClient`, then `RadioStation`; the DJ name checks `RadioStation` first). See
  `StationMetadataManager`.
- Key code: `RadioSpiral/ConfigClient/` (ConfigClient, StationConfig), `RadioSpiral/Model/RadioStation.swift`
  (`init(from: StationConfig)`), `StationMetadataManager`, `DataManager`, `NowPlayingViewController`.
- When adding a Swift file, register it in `project.pbxproj` for every target that needs it
  (the app and `ConfigClientTests`).

## Decisions to respect

- The time bubble is phone-only, not on CarPlay. The audio-mode button was removed on 2026-10-11
  and replaced by the interruption setting in the iOS Settings app; don't restore it.
- `backlog/` is local-only (gitignored): never commit or push task files, never `git add -f`.
  Follow `docs/backlog-guidelines.md` when writing a task by hand (the CLI isn't installed).
- `docs/archive/` holds old handoffs and plans and is also kept local.
