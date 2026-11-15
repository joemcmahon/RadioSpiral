//
//  NowPlayingClock.swift
//  RadioSpiral
//
//  The track's elapsed time as the system will count it. The system counts forward from the
//  elapsed time in the last Now Playing write, so a write that only changes the rate or the
//  artist line has to carry the time as it is now, not the one last set (task-49).
//

import Foundation
import MediaPlayer

struct NowPlayingClock {
    private let elapsedAtSince: Double
    let rate: Double
    private let since: TimeInterval
    private let duration: TimeInterval?
    /// When the display was frozen by a pause, nil while playing.
    private let pausedAt: TimeInterval?

    /// - Parameters:
    ///   - elapsed: The server's elapsed time into the track at `since`.
    ///   - rate: What the system is told: 1 while playing, 0 while paused. It doesn't change
    ///     how the clock counts, which follows the server's timeline (the phone's time bubble
    ///     and the AzuraCast web player count the same way).
    ///   - since: A monotonic time such as `ProcessInfo.systemUptime`, not the wall clock.
    ///   - duration: The track's length, which the time never passes.
    init(elapsed: Double, rate: Double, since: TimeInterval, duration: TimeInterval? = nil,
         pausedAt: TimeInterval? = nil) {
        self.elapsedAtSince = elapsed
        self.rate = rate
        self.since = since
        self.duration = duration
        self.pausedAt = pausedAt
    }

    /// The clock for a new track, counting from the elapsed time the server gave. A live show
    /// has none: its duration and elapsed time are a silent placeholder's and mean nothing.
    static func forTrack(_ metadata: UnifiedMetadata, at now: TimeInterval) -> NowPlayingClock? {
        guard !metadata.isLiveDJ else { return nil }
        return NowPlayingClock(elapsed: metadata.elapsed ?? 0.0, rate: 1, since: now, duration: metadata.duration)
    }

    /// The live position in the track at `now`, as the time bubble counts it.
    func elapsed(at now: TimeInterval) -> Double {
        let elapsed = elapsedAtSince + max(0, now - since)
        guard let duration = duration, duration > 0 else { return elapsed }
        return min(elapsed, duration)
    }

    /// The same timeline, shown as playing (rate 1) or frozen at `now` (rate 0). A resumed clock
    /// shows the live position, not the one the pause stopped at.
    func with(rate: Double, at now: TimeInterval) -> NowPlayingClock {
        NowPlayingClock(elapsed: elapsedAtSince, rate: rate, since: since, duration: duration,
                        pausedAt: rate == 0 ? (pausedAt ?? now) : nil)
    }

    /// `info` with the time to show at `now` and this rate, and everything else as it was. A paused
    /// clock shows the time of the pause, however late it is written.
    func apply(to info: [String: Any], at now: TimeInterval) -> [String: Any] {
        var info = info
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed(at: pausedAt ?? now)
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        return info
    }
}
