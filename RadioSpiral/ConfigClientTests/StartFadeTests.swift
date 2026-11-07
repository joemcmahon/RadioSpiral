//
//  StartFadeTests.swift
//  ConfigClientTests
//
//  The volume rule that covers the brief glitch when audio starts (task-54).
//

import XCTest
@testable import RadioSpiral

final class StartFadeTests: XCTestCase {
    func testWithNoFadeTheVolumeIsFull() {
        var fade = StartFade()

        XCTAssertEqual(fade.volume(at: 0), 1)
        XCTAssertFalse(fade.isActive)
    }

    func testVolumeFollowsPositionFromAStart() {
        let cases: [(position: Double, volume: Float)] = [
            (0, 0), (1, 0), (1.5, 0), (1.65, 0.5), (1.8, 1), (10, 1)
        ]
        for (position, volume) in cases {
            var fade = StartFade()
            fade.begin(at: 0)

            XCTAssertEqual(fade.volume(at: position), volume, accuracy: 0.001, "position \(position)")
        }
    }

    /// Recovery resumes a player that's well into the stream, so it counts from there.
    func testAFadeCountsFromWhereItBegan() {
        var fade = StartFade()
        fade.begin(at: 249)

        XCTAssertEqual(fade.volume(at: 249), 0)
        XCTAssertEqual(fade.volume(at: 250.5), 0)
        XCTAssertEqual(fade.volume(at: 250.65), 0.5, accuracy: 0.001)
        XCTAssertEqual(fade.volume(at: 250.8), 1)
    }

    func testAFadeEndsOnceTheVolumeIsFull() {
        var fade = StartFade()
        fade.begin(at: 0)

        XCTAssertTrue(fade.isActive)
        _ = fade.volume(at: 1)
        XCTAssertTrue(fade.isActive)
        _ = fade.volume(at: 1.8)
        XCTAssertFalse(fade.isActive)
    }

    /// Once finished, position going back shouldn't silence audio.
    func testAFinishedFadeStaysFull() {
        var fade = StartFade()
        fade.begin(at: 10)
        _ = fade.volume(at: 12)

        XCTAssertEqual(fade.volume(at: 0), 1)
    }

    func testBeginningAgainStartsOver() {
        var fade = StartFade()
        fade.begin(at: 0)
        _ = fade.volume(at: 1)

        fade.begin(at: 1)

        XCTAssertEqual(fade.volume(at: 2), 0, "only 1 second since the new beginning")
        XCTAssertEqual(fade.volume(at: 2.8), 1)
    }

    /// A position that can't be read says nothing, so it doesn't end the silence.
    func testAnUnreadablePositionKeepsItSilent() {
        var fade = StartFade()
        fade.begin(at: 0)

        XCTAssertEqual(fade.volume(at: .nan), 0)
        XCTAssertEqual(fade.volume(at: .infinity), 0)
        XCTAssertTrue(fade.isActive)
    }

    /// A start that never moves stays silent, but the next player's fade is its own.
    func testAStartThatNeverMovesDoesNotAffectTheNext() {
        var fade = StartFade()
        fade.begin(at: 0)
        XCTAssertEqual(fade.volume(at: 0), 0)

        fade.begin(at: 0)

        XCTAssertEqual(fade.volume(at: 1.8), 1)
    }
}
