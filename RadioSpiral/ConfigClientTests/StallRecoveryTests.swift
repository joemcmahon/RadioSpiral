//
//  StallRecoveryTests.swift
//  ConfigClientTests
//
//  The decisions that keep audio going after a stall. Timings and levels come from
//  logs of real network drops on a phone (task-52).
//

import XCTest
@testable import RadioSpiral

final class StallRecoveryTests: XCTestCase {
    private var recovery: StallRecovery!
    private var now: TimeInterval = 0
    private var position: Double = 0

    override func setUp() {
        super.setUp()
        now = 0
        position = 0
        recovery = StallRecovery(randomFraction: { 1 })
    }

    /// One second passes and the player reports its state.
    @discardableResult
    private func tick(moving: Bool = false, buffered: Double = 0, waiting: Bool = false,
                      failed: Bool = false, networkUp: Bool = true) -> StallRecovery.Action {
        now += 1
        if moving { position += 1 }
        return recovery.next(.init(position: position, buffered: buffered, isWaitingOnStall: waiting,
                                   hasFailed: failed, networkUp: networkUp, now: now))
    }

    private func play(seconds: Int) {
        for _ in 0..<seconds { XCTAssertEqual(tick(moving: true, buffered: 5.5), .none) }
    }

    /// The player is replaced, and the new one reports for the first time.
    private func replacePlayer() {
        recovery.playerWasReplaced()
        tick()
    }

    /// Runs frozen, with no data, until a rebuild comes. Returns how long that took.
    private func secondsUntilRebuild(limit: Int = 300) -> Int? {
        for second in 1...limit where tick() == .rebuild { return second }
        return nil
    }

    // MARK: Healthy playback

    func testPlayingAudioIsLeftAlone() {
        play(seconds: 120)

        XCTAssertFalse(recovery.isStalled)
    }

    // MARK: Resuming

    /// What the phone did: bytes back, 150 seconds buffered, and it never moved again.
    func testAStalledPlayerWithEnoughBufferedIsResumed() {
        play(seconds: 10)
        tick(buffered: 0.1, waiting: true)

        XCTAssertEqual(tick(buffered: 5.4, waiting: true), .resume)
    }

    func testAStalledPlayerWithLittleBufferedKeepsWaiting() {
        play(seconds: 10)
        tick(buffered: 0.1, waiting: true)

        XCTAssertEqual(tick(buffered: 4.9, waiting: true), .none)
    }

    /// A station that sends a smaller burst on reconnecting would otherwise never reach 5 seconds.
    func testAfterTwentySecondsStalledLessBufferedIsEnough() {
        play(seconds: 10)
        var actions: [StallRecovery.Action] = []
        for _ in 0..<20 { actions.append(tick(buffered: 2, waiting: true)) }

        XCTAssertEqual(actions.prefix(19).filter { $0 == .resume }.count, 0)
        XCTAssertEqual(actions.last, .resume)
    }

    /// A buffered level this low can't play for long, however long it's been.
    func testVeryLittleBufferedNeverResumes() {
        play(seconds: 10)
        for _ in 0..<25 { XCTAssertNotEqual(tick(buffered: 1.9, waiting: true), .resume) }
    }

    /// CarPlay starts slowly: status says playing, data piles up, the position stays still.
    func testAPlayerThatIsNotWaitingIsNotResumed() {
        XCTAssertEqual(tick(buffered: 16, waiting: false), .none)
        XCTAssertEqual(tick(buffered: 17, waiting: false), .none)
    }

    func testAResumeIsNotRepeatedEverySecond() {
        play(seconds: 10)
        var buffered = 5.0
        var actions: [StallRecovery.Action] = []
        for _ in 0..<6 {
            buffered += 1
            actions.append(tick(buffered: buffered, waiting: true))
        }

        XCTAssertEqual(actions, [.resume, .none, .none, .none, .none, .resume])
    }

    // MARK: Rebuilding

    func testNoDataForThirtySecondsWithTheNetworkUpRebuilds() {
        play(seconds: 10)

        XCTAssertEqual(secondsUntilRebuild(), 30)
    }

    /// Slow to start isn't dead: data is still arriving.
    func testDataStillArrivingIsNotRebuilt() {
        var buffered = 0.0
        for _ in 0..<120 {
            buffered += 1
            XCTAssertEqual(tick(buffered: buffered, waiting: false), .none)
        }
    }

    /// A rebuild while offline would throw away the player that reconnects by itself.
    func testNothingIsRebuiltWhileTheNetworkIsDown() {
        play(seconds: 10)
        for _ in 0..<300 { XCTAssertEqual(tick(networkUp: false), .none) }
    }

    /// The old player reconnects within seconds of the network returning, so it gets the chance.
    func testTheThirtySecondsStartWhenTheNetworkReturns() {
        play(seconds: 10)
        for _ in 0..<120 { tick(networkUp: false) }

        XCTAssertEqual(secondsUntilRebuild(), 30)
    }

    func testAFailedPlayerIsRebuiltAtOnce() {
        play(seconds: 10)

        XCTAssertEqual(tick(failed: true), .rebuild)
    }

    func testAFailedPlayerWaitsForTheNetwork() {
        play(seconds: 10)
        XCTAssertEqual(tick(failed: true, networkUp: false), .none)

        XCTAssertEqual(tick(failed: true, networkUp: true), .rebuild)
    }

    func testAFailedPlayerIsNotRebuiltEverySecond() {
        play(seconds: 10)
        XCTAssertEqual(tick(failed: true), .rebuild)
        recovery.playerWasReplaced()

        for _ in 0..<30 { XCTAssertEqual(tick(failed: true), .none) }
        XCTAssertEqual(tick(failed: true), .rebuild)
    }

    func testRebuildWaitsGrowAndStopAtTwoMinutes() {
        var waits: [Int?] = []
        tick()
        for _ in 0..<5 {
            waits.append(secondsUntilRebuild())
            replacePlayer()
        }

        XCTAssertEqual(waits, [30, 30, 60, 120, 120])
    }

    func testRebuildWaitsNeverDropBelowHalfTheirLength() {
        recovery = StallRecovery(randomFraction: { 0 })
        var waits: [Int?] = []
        tick()
        for _ in 0..<5 {
            waits.append(secondsUntilRebuild())
            replacePlayer()
        }

        // The 30 seconds of no data is a fixed test for trouble; only the waits between rebuilds vary.
        XCTAssertEqual(waits, [30, 30, 30, 60, 60])
    }

    func testAMinuteOfPlayingRestartsTheRebuildWaits() {
        for _ in 0..<3 {
            XCTAssertNotNil(secondsUntilRebuild())
            replacePlayer()
        }

        play(seconds: 61)
        XCTAssertNotNil(secondsUntilRebuild())
        replacePlayer()

        XCTAssertEqual(secondsUntilRebuild(), 30)
    }

    func testPlayingBrieflyDoesNotRestartTheRebuildWaits() {
        for _ in 0..<3 {
            XCTAssertNotNil(secondsUntilRebuild())
            replacePlayer()
        }

        play(seconds: 5)
        XCTAssertNotNil(secondsUntilRebuild())
        replacePlayer()

        XCTAssertEqual(secondsUntilRebuild(), 120)
    }

    // MARK: Telling the listener

    func testAudioFrozenForTwoSecondsCountsAsStalled() {
        play(seconds: 10)
        tick()
        XCTAssertFalse(recovery.isStalled)

        tick()

        XCTAssertTrue(recovery.isStalled)
    }

    func testAudioMovingAgainEndsTheStall() {
        play(seconds: 10)
        tick()
        tick()

        tick(moving: true)

        XCTAssertFalse(recovery.isStalled)
    }

    /// Starting up isn't trouble, and CarPlay takes about 14 seconds to do it.
    func testAudioThatHasNotStartedYetIsNotStalled() {
        for _ in 0..<20 { tick(buffered: 1) }

        XCTAssertFalse(recovery.isStalled)
    }

    func testANewPlayerHasNotStartedYet() {
        play(seconds: 10)
        tick()
        tick()
        XCTAssertTrue(recovery.isStalled)

        recovery.playerWasReplaced()
        position = 0
        tick()
        tick()
        tick()

        XCTAssertFalse(recovery.isStalled)
    }

    /// Stopping forgets the stall, so a later Play doesn't begin by reporting one.
    func testStoppingEndsTheStall() {
        play(seconds: 10)
        tick()
        tick()

        recovery.playbackStopped()

        XCTAssertFalse(recovery.isStalled)
    }
}
