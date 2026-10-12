// RadioSpiral/Model/InterruptionPreference.swift
import Foundation

/// What the stream does when something speaks over it (navigation, Siri, VoiceOver, other apps).
/// Set in the iOS Settings app (Settings.bundle, same key). The raw values are the ones the old
/// audio mode menu saved, so earlier choices carry over: Auto-select → automatic,
/// Pitch lock → pause, Continuous audio lock → lowerVolume.
enum InterruptionPreference: String {
    /// Pause with hearing aids connected, lower the volume otherwise. The default.
    case automatic = "ask"
    case pause = "alwaysStability"
    case lowerVolume = "neverStability"

    static let key = "audioStabilityPreference"

    static var current: InterruptionPreference {
        get {
            let raw = UserDefaults.standard.string(forKey: key) ?? automatic.rawValue
            return InterruptionPreference(rawValue: raw) ?? .automatic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func mode(hearingAidsConnected: Bool) -> InterruptionMode {
        switch self {
        case .pause: return .pause
        case .lowerVolume: return .lowerVolume
        case .automatic: return hearingAidsConnected ? .pause : .lowerVolume
        }
    }
}

/// The interruption behavior applied to the audio session.
enum InterruptionMode {
    case pause         // .spokenAudio session: spoken interruptions pause the stream
    case lowerVolume   // .default session: spoken interruptions play over it at lower volume
}
