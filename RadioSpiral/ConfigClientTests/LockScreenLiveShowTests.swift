//
//  LockScreenLiveShowTests.swift
//  ConfigClientTests
//
//  During a live DJ show AzuraCast reports the silent placeholder track's duration and
//  elapsed time (about 12 minutes), which means nothing about the show. The lock screen and
//  CarPlay clock counted it and kept resetting. A live show is published as a live stream,
//  with no time at all; a recorded track still gets its time.
//

import XCTest
import MediaPlayer
@testable import RadioSpiral

final class LockScreenLiveShowTests: XCTestCase {

    func testALiveShowIsPublishedAsALiveStreamWithNoTime() {
        let metadata = UnifiedMetadata(trackName: "Show", artistName: "DJ", duration: 720, elapsed: 40, isLiveDJ: true)

        let info = StationsManager.trackInfo(from: [:], metadata: metadata, artistLine: "DJ")

        XCTAssertEqual(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, true)
        XCTAssertNil(info[MPMediaItemPropertyPlaybackDuration])
        XCTAssertNil(info[MPNowPlayingInfoPropertyElapsedPlaybackTime])
    }

    func testATimeFromThePreviousRecordedTrackDoesNotSurviveIntoALiveShow() {
        let existing: [String: Any] = [MPMediaItemPropertyPlaybackDuration: 200.0,
                                       MPNowPlayingInfoPropertyElapsedPlaybackTime: 75.0]
        let metadata = UnifiedMetadata(trackName: "Show", artistName: "DJ", isLiveDJ: true)

        let info = StationsManager.trackInfo(from: existing, metadata: metadata, artistLine: "DJ")

        XCTAssertNil(info[MPMediaItemPropertyPlaybackDuration])
        XCTAssertNil(info[MPNowPlayingInfoPropertyElapsedPlaybackTime])
    }

    func testARecordedTrackKeepsItsTimeAndIsNotALiveStream() {
        let existing: [String: Any] = [MPNowPlayingInfoPropertyIsLiveStream: true]
        let metadata = UnifiedMetadata(trackName: "Song", artistName: "Artist", duration: 200, elapsed: 75, isLiveDJ: false)

        let info = StationsManager.trackInfo(from: existing, metadata: metadata, artistLine: "Artist")

        XCTAssertEqual(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, false, "Still marked live after the show ended")
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double, 200)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 75)
    }
}
