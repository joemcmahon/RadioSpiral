import Foundation

/// Decides what to do about audio that has stopped moving, from a once-a-second look at the player.
///
/// The player can't be asked directly: on a phone, through real network drops, it reported no error,
/// reconnected by itself, and then sat waiting with minutes of audio buffered and never played it.
/// So moving position is the proof of audio. Asking again resumes it, without a new connection.
/// A rebuild is the last resort, for a player that has failed or is getting no data.
struct StallRecovery {
    struct Sample {
        let position: Double
        let buffered: Double
        /// The player is holding back because it stalled. Slow starts don't report this.
        let isWaitingOnStall: Bool
        let hasFailed: Bool
        let networkUp: Bool
        let now: TimeInterval
    }

    enum Action { case none, resume, rebuild }

    /// Audio that was playing has stopped moving. Starting up doesn't count.
    private(set) var isStalled = false

    // About what the server sends on reconnecting, and what the player normally holds.
    private static let bufferedToResume: Double = 5
    // For a station that sends less. Below this it couldn't play for long anyway.
    private static let bufferedToResumeLate: Double = 2
    private static let lateAfter: TimeInterval = 20
    private static let resumeSpacing: TimeInterval = 5
    private static let frozenBeforeStalled: TimeInterval = 2
    private static let noDataBeforeRebuild: TimeInterval = 30
    private static let longestRebuildWait: TimeInterval = 120
    private static let playingToClearRebuilds: TimeInterval = 60

    private let randomFraction: () -> Double
    private var lastPosition: Double?
    private var lastBuffered: Double = 0
    private var lastMovedAt: TimeInterval = 0
    private var lastProgressAt: TimeInterval = 0
    private var lastResumeAt: TimeInterval?
    private var movingSince: TimeInterval?
    private var hasStarted = false
    private var rebuilds = 0
    private var rebuildWait: TimeInterval = 0

    init(randomFraction: @escaping () -> Double = { Double.random(in: 0...1) }) {
        self.randomFraction = randomFraction
    }

    mutating func next(_ sample: Sample) -> Action {
        let now = sample.now
        guard let previous = lastPosition else {
            lastPosition = sample.position
            lastBuffered = sample.buffered
            lastMovedAt = now
            lastProgressAt = now
            return sample.hasFailed && sample.networkUp && rebuildWait == 0 ? rebuilt() : .none
        }
        let grew = sample.buffered > lastBuffered + 0.01
        lastPosition = sample.position
        lastBuffered = sample.buffered

        if sample.position != previous {
            hasStarted = true
            isStalled = false
            lastMovedAt = now
            lastProgressAt = now
            movingSince = movingSince ?? now
            if let movingSince, now - movingSince >= Self.playingToClearRebuilds {
                rebuilds = 0
                rebuildWait = 0
            }
            return .none
        }

        movingSince = nil
        let frozenFor = now - lastMovedAt
        if hasStarted && frozenFor >= Self.frozenBeforeStalled { isStalled = true }
        // The player reconnects by itself, so offline time and arriving data don't count against it.
        if grew || !sample.networkUp { lastProgressAt = now }
        let quietFor = now - lastProgressAt

        if sample.hasFailed {
            return sample.networkUp && quietFor >= rebuildWait ? rebuilt() : .none
        }

        if sample.isWaitingOnStall {
            let needed = frozenFor >= Self.lateAfter ? Self.bufferedToResumeLate : Self.bufferedToResume
            let spaced = lastResumeAt.map { now - $0 >= Self.resumeSpacing } ?? true
            if sample.buffered >= needed && spaced {
                lastResumeAt = now
                return .resume
            }
        }

        return quietFor >= max(Self.noDataBeforeRebuild, rebuildWait) ? rebuilt() : .none
    }

    /// The next sample is from a new player, so its position says nothing about the old one's.
    mutating func playerWasReplaced() {
        forgetPlayback()
    }

    mutating func playbackStopped() {
        forgetPlayback()
    }

    private mutating func forgetPlayback() {
        lastPosition = nil
        lastResumeAt = nil
        movingSince = nil
        hasStarted = false
        isStalled = false
    }

    private mutating func rebuilt() -> Action {
        let longest = min(Self.noDataBeforeRebuild * pow(2, Double(rebuilds)), Self.longestRebuildWait)
        rebuildWait = longest * (0.5 + 0.5 * randomFraction())
        rebuilds += 1
        return .rebuild
    }
}
