---
id: task-3
title: Convert old-style CarPlay interface to new technology
status: Done
assignee: []
created_date: '2025-07-08'
updated_date: '2026-06-28'
labels: []
dependencies: []
---

## Description
This needs to be reimplemented top to bottom. I believe I have the right permissions etc. but that needs to be checked.

## Implementation Notes

Marked Done for the framework conversion: app now uses CPTemplateApplicationSceneDelegate with CPListTemplate (modern CarPlay framework). No old-style MPPlayableContentManager / MPContentItem code remains. com.apple.developer.carplay-audio entitlement present.

Current implementation (RadioSpiral/CarPlay/CarPlaySceneDelegate.swift):
- Station list via CPListTemplate with station artwork (CarPlaySceneDelegate.swift:58-78, 100-102)
- Tap-to-play with MPNowPlayingInfoCenter update (CarPlaySceneDelegate.swift:104-145)
- Cold-start race condition fixed (Build 72, commit cd6b9398)
- External play starts mirror into wasPlaying flag for WiFi recovery (commit b5c59697)

Remaining gaps split into follow-up tasks (filed as task-15, task-16, task-17):
- CPNowPlayingTemplate for dedicated CarPlay now-playing UI
- In-CarPlay play/pause/next/previous controls
- Info.plist UISceneConfigurations entry to replace AppDelegate runtime routing
