// RadioSpiral/Model/AudioStabilityPreference.swift
import Foundation

/// User preference for audio stability mode when hearing aids are connected.
enum AudioStabilityPreference: String {
    /// Default. Auto-switch to Stability Mode on HA connect; show banner every time.
    case ask = "ask"
    /// Always use Stability Mode when HAs connect. No banner. Shows icon.
    case alwaysStability = "alwaysStability"
    /// Always use Fidelity Mode even with HAs. No banner. Shows icon.
    case neverStability = "neverStability"

    private static let key = "audioStabilityPreference"

    static var current: AudioStabilityPreference {
        get {
            let raw = UserDefaults.standard.string(forKey: key) ?? "ask"
            return AudioStabilityPreference(rawValue: raw) ?? .ask
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// The active audio mode applied to AVAudioSession and AVPlayerItem.
enum AudioStabilityMode {
    case stability   // spokenAudio session, timeDomain pitch, 30s buffer
    case fidelity    // default session, spectral pitch, 2s buffer
}
