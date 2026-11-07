import Foundation

/// Covers a brief glitch at the start of audio by keeping it silent for a moment, then fading in.
///
/// The player makes two tiny bursts of sound as it starts or resumes after a stall. The cause isn't
/// known: the player reports nothing wrong and the same stream starts cleanly in Safari. By ear on a
/// phone, the glitch went unheard once the audio stayed silent until position had moved 1.5 seconds,
/// and came through when the fade began at once (task-54). It counts position, not time, because
/// the wait before audio moves runs from about 1.5 to about 14 seconds depending on the route.
struct StartFade {
    private static let silence: Double = 1.5
    private static let ramp: Double = 0.3

    private var origin: Double?

    var isActive: Bool { origin != nil }

    /// Starts over from silence, counting from `position`.
    mutating func begin(at position: Double) {
        origin = position
    }

    /// The volume for this position. The fade ends itself on reaching full volume.
    mutating func volume(at position: Double) -> Float {
        guard let origin else { return 1 }
        guard position.isFinite else { return 0 }
        let intoRamp = (position - origin - Self.silence) / Self.ramp
        if intoRamp >= 1 {
            self.origin = nil
            return 1
        }
        return Float(max(0, intoRamp))
    }
}
