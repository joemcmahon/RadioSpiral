// RadioSpiral/Model/AudioStabilityPreference.swift
import Foundation

/// User preference for audio stability mode when hearing aids are connected.
/// Single source of truth shared by the hearing-aid banner and the ear button.
enum AudioStabilityPreference: String {
    /// "Auto-select": stability with hearing aids, fidelity otherwise. Also the effective
    /// value before the user has chosen (see `hasChoice`).
    case ask = "ask"
    /// "Pitch lock": always use Stability Mode.
    case alwaysStability = "alwaysStability"
    /// "Continuous audio lock": always use Fidelity Mode, even with hearing aids.
    case neverStability = "neverStability"

    /// Posted on the main thread whenever `current` is set.
    static let didChange = Notification.Name("AudioStabilityPreferenceDidChange")

    private static let key = "audioStabilityPreference"

    /// False until the user picks a mode (banner or ear menu). Drives the first-run banner.
    static var hasChoice: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }

    static var current: AudioStabilityPreference {
        get {
            let raw = UserDefaults.standard.string(forKey: key) ?? "ask"
            return AudioStabilityPreference(rawValue: raw) ?? .ask
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
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
