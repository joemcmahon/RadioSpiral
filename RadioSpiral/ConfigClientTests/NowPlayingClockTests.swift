//
//  NowPlayingClockTests.swift
//  ConfigClientTests
//
//  The system counts forward from the elapsed time in the last Now Playing write. A write that
//  only changes the rate or the artist line has to carry the time as it is now, or the clock
//  jumps back to the value from before (task-49: pressing Play in CarPlay after a pause).
//  A live show has no clock at all, so it never gets one.
//

import XCTest
import MediaPlayer
@testable import RadioSpiral

final class NowPlayingClockTests: XCTestCase {

    func testAClockCountsForwardFromWhereItWasSet() {
        let clock = NowPlayingClock(elapsed: 75, rate: 1, since: 100)
        XCTAssertEqual(clock.elapsed(at: 110), 85, accuracy: 0.001)
    }

    func testAClockKeepsCountingLivePastAPause() {
        // The server's timeline doesn't stop when the listener pauses; the phone's time bubble
        // and the AzuraCast web player don't either. After a pause, CarPlay shows the same.
        let paused = NowPlayingClock(elapsed: 75, rate: 1, since: 100).with(rate: 0, at: 110)

        XCTAssertEqual(paused.elapsed(at: 200), 175, accuracy: 0.001, "elapsed(at:) is the live timeline; only apply(to:at:) freezes")
    }

    func testResumingShowsTheLivePositionNotTheTimeOfThePause() {
        let resumed = NowPlayingClock(elapsed: 75, rate: 1, since: 100).with(rate: 0, at: 110).with(rate: 1, at: 130)

        XCTAssertEqual(resumed.apply(to: [:], at: 150)[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 125, accuracy: 0.001, "It jumped back to the time before the pause")
    }

    func testTheTimeIsNeverPastTheTracksLength() {
        let clock = NowPlayingClock(elapsed: 75, rate: 1, since: 100, duration: 200)
        XCTAssertEqual(clock.elapsed(at: 400), 200, accuracy: 0.001)
    }

    func testARewriteCarriesTheCurrentTimeAndRateAndKeepsTheRest() {
        let clock = NowPlayingClock(elapsed: 75, rate: 1, since: 100)
        let info: [String: Any] = [MPMediaItemPropertyTitle: "Song",
                                   MPNowPlayingInfoPropertyElapsedPlaybackTime: 75.0,
                                   MPNowPlayingInfoPropertyPlaybackRate: 0.0]

        let rewritten = clock.apply(to: info, at: 110)

        XCTAssertEqual(rewritten[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 85, accuracy: 0.001)
        XCTAssertEqual(rewritten[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1)
        XCTAssertEqual(rewritten[MPMediaItemPropertyTitle] as? String, "Song")
    }

    func testAPausedRewriteFreezesTheDisplayAtTheLiveTimeOfThePause() {
        let paused = NowPlayingClock(elapsed: 75, rate: 1, since: 100).with(rate: 0, at: 110)

        let rewritten = paused.apply(to: [:], at: 110)

        XCTAssertEqual(rewritten[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 85, accuracy: 0.001)
        XCTAssertEqual(rewritten[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)
    }

    func testAPausedDisplayStaysWhereThePauseStoppedItWhateverIsRewrittenLater() {
        // The artist line is rewritten every 10 seconds in CarPlay. A paused display must not
        // creep forward with each of those writes.
        let paused = NowPlayingClock(elapsed: 75, rate: 1, since: 100).with(rate: 0, at: 110)

        let later = paused.apply(to: [:], at: 140)

        XCTAssertEqual(later[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? -1, 85, accuracy: 0.001)
    }

    func testARecordedTrackStartsAClockAtItsElapsedTime() {
        let metadata = UnifiedMetadata(trackName: "Song", artistName: "Artist", duration: 200, elapsed: 75, isLiveDJ: false)

        let clock = NowPlayingClock.forTrack(metadata, at: 100)

        XCTAssertEqual(clock?.elapsed(at: 110) ?? -1, 85, accuracy: 0.001)
        XCTAssertEqual(clock?.elapsed(at: 400) ?? -1, 200, accuracy: 0.001, "Past the track's length")
    }

    func testARecordedTrackWithNoElapsedTimeStartsAtZero() {
        let metadata = UnifiedMetadata(trackName: "Song", artistName: "Artist", isLiveDJ: false)

        let clock = NowPlayingClock.forTrack(metadata, at: 100)

        XCTAssertEqual(clock?.elapsed(at: 100) ?? -1, 0, accuracy: 0.001)
    }

    func testALiveShowGetsNoClock() {
        let metadata = UnifiedMetadata(trackName: "Show", artistName: "DJ", duration: 720, elapsed: 40, isLiveDJ: true)

        XCTAssertNil(NowPlayingClock.forTrack(metadata, at: 100), "A live show's time means nothing; writing it brought back the resetting clock")
    }
}
