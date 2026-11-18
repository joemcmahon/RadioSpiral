//
//  DemoLiveShow.swift
//  RadioSpiral
//
//  UI layout tests cannot choose whether a live DJ is on air, and a live show changes Now
//  Playing: the live indicator appears beside the DJ name and moves it. In Debug builds the
//  launch argument `-nowPlayingDemoLive on|off` decides for the test; any other value, and every
//  Release build, leaves the station's own state in charge.
//

import Foundation

enum DemoLiveShow {
    /// "on", "off", or nil (not set, or not recognised, or a Release build).
    static var launchOverride: String? {
        #if DEBUG
        guard let value = UserDefaults.standard.string(forKey: "nowPlayingDemoLive"),
              value == "on" || value == "off" else { return nil }
        return value
        #else
        return nil
        #endif
    }

    /// Whether the live-show indicator is hidden.
    static func indicatorHidden(isLiveDJ: Bool, override: String? = launchOverride) -> Bool {
        switch override {
        case "on": return false
        case "off": return true
        default: return !isLiveDJ
        }
    }
}
