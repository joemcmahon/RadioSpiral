//
//  SocketClientIntegrationTests.swift
//  ConfigClientTests
//
//  Drives ACWebSocketClient's connection states through a fake socket and a fake
//  clock, so nothing here touches the network or waits in real time.
//

import XCTest
@testable import RadioSpiral

/// Stands in for a URLSessionWebSocketTask. The test decides when messages and drops arrive.
final class FakeSocket: WebSocketTasking {
    private(set) var resumeCount = 0
    private(set) var cancelCount = 0
    private(set) var sent: [URLSessionWebSocketTask.Message] = []
    /// What the next `send` reports. Nil means it worked.
    var sendError: Error?
    private var pendingReceive: ((Result<URLSessionWebSocketTask.Message, Error>) -> Void)?

    var holdsSendResults = false
    private var heldSendResult: (@Sendable (Error?) -> Void)?

    func resume() { resumeCount += 1 }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { cancelCount += 1 }

    func send(_ message: URLSessionWebSocketTask.Message,
              completionHandler: @escaping @Sendable (Error?) -> Void) {
        sent.append(message)
        if holdsSendResults {
            heldSendResult = completionHandler
        } else {
            completionHandler(sendError)
        }
    }

    /// Reports the result of a send held back by `holdsSendResults`, as a real socket does some time later.
    func finishHeldSend(with error: Error?) {
        let handler = heldSendResult
        heldSendResult = nil
        handler?(error)
    }

    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        pendingReceive = completionHandler
    }

    var isListening: Bool { pendingReceive != nil }

    func deliver(_ text: String) {
        let handler = pendingReceive
        pendingReceive = nil
        handler?(.success(.string(text)))
    }

    func deliverBinary() {
        let handler = pendingReceive
        pendingReceive = nil
        handler?(.success(.data(Data([1, 2, 3]))))
    }

    /// Also stands in for a cancelled socket's late failure: a real one reports
    /// "cancelled" to its pending receive, some time after `cancel` returns.
    func drop() {
        let handler = pendingReceive
        pendingReceive = nil
        handler?(.failure(URLError(.networkConnectionLost)))
    }
}

/// Records what the client schedules. Nothing runs until the test fires it.
final class FakeClock: SocketClock {
    final class FakeTimer: LivenessTimer {
        let interval: TimeInterval
        let action: () -> Void
        private(set) var isInvalidated = false

        init(interval: TimeInterval, action: @escaping () -> Void) {
            self.interval = interval
            self.action = action
        }

        func invalidate() { isInvalidated = true }
    }

    private(set) var delayed: [(delay: TimeInterval, action: () -> Void)] = []
    private(set) var timers: [FakeTimer] = []
    /// Moves only when a test moves it.
    var now = Date(timeIntervalSinceReferenceDate: 0)
    /// Where each wait lands between its shortest and longest. 1 is the longest.
    var jitterFraction = 1.0

    func randomFraction() -> Double { jitterFraction }

    func runAfter(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        delayed.append((delay, action))
    }

    func startTimer(interval: TimeInterval, _ action: @escaping () -> Void) -> LivenessTimer {
        let timer = FakeTimer(interval: interval, action: action)
        timers.append(timer)
        return timer
    }

    /// Fails the test, rather than crashing the run, if nothing is waiting.
    func fireNextDelayed() {
        guard !delayed.isEmpty else { return XCTFail("nothing was scheduled") }
        delayed.removeFirst().action()
    }

    var liveTimers: [FakeTimer] { timers.filter { !$0.isInvalidated } }
}

final class SocketClientIntegrationTests: XCTestCase {
    private let shortCode = ConnectMessageFixture.shortCode
    private var sockets: [FakeSocket] = []
    private var requestedURLs: [URL] = []
    private var clock: FakeClock!
    private var client: ACWebSocketClient!
    private var notified: [ACConnectionState] = []
    private var notifiedTracks: [String] = []
    private var holdSendResults = false

    override func setUp() {
        super.setUp()
        holdSendResults = false
        sockets = []
        requestedURLs = []
        notified = []
        notifiedTracks = []
        clock = FakeClock()
        client = ACWebSocketClient(serverName: "radio.example", shortCode: shortCode, defaultDJ: "",
                                   clock: clock) { [unowned self] url in
            self.requestedURLs.append(url)
            let socket = FakeSocket()
            socket.holdsSendResults = self.holdSendResults
            self.sockets.append(socket)
            return socket
        }
        client.addSubscriber { [unowned self] status in
            self.notified.append(status.connection)
            self.notifiedTracks.append(status.track)
        }
    }

    /// The client hands timer and status work to the main queue. Blocks run in order,
    /// so once this one has run, everything queued before it has too.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }

    /// The nth socket opened. Fails the test, rather than crashing the run, if there's no such socket.
    private func socket(_ index: Int) throws -> FakeSocket {
        guard sockets.indices.contains(index) else {
            XCTFail("expected socket \(index), but only \(sockets.count) opened")
            throw URLError(.cannotFindHost)
        }
        return sockets[index]
    }

    private func station(server: String = "next.example", shortCode: String = ConnectMessageFixture.shortCode) -> RadioStation {
        RadioStation(name: "Next Station",
                     streamURL: "https://\(server)/next.mp3",
                     imageURL: "stationImage",
                     desc: "Next description",
                     serverName: server,
                     shortCode: shortCode,
                     defaultDJ: "")
    }

    private func connectMessage(ping: Int? = nil) throws -> String {
        let data = try ConnectMessageFixture.data()
        guard let ping else { return try XCTUnwrap(String(data: data, encoding: .utf8)) }
        var message = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var connect = try XCTUnwrap(message["connect"] as? [String: Any])
        connect["ping"] = ping
        message["connect"] = connect
        let edited = try JSONSerialization.data(withJSONObject: message)
        return try XCTUnwrap(String(data: edited, encoding: .utf8))
    }

    // MARK: Connecting

    func testConnectOpensASocketToTheStationsNowPlayingAddress() throws {
        client.connect()

        XCTAssertEqual(requestedURLs.map(\.absoluteString),
                       ["wss://radio.example/api/live/nowplaying/websocket"])
        XCTAssertEqual(sockets.first?.resumeCount, 1)
        XCTAssertEqual(client.status.connection, .connecting)
    }

    func testConnectSubscribesToTheStationAndStartsListening() throws {
        client.connect()

        let socket = try XCTUnwrap(sockets.first)
        guard case .string(let text)? = socket.sent.first else {
            return XCTFail("expected one text subscription message, got \(socket.sent)")
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let subs = try XCTUnwrap(json["subs"] as? [String: Any])
        XCTAssertEqual(Array(subs.keys), ["station:\(shortCode)"])
        XCTAssertTrue(socket.isListening)
    }

    func testFirstMessageMovesToConnectedAndNotifies() throws {
        client.connect()

        try socket(0).deliver(try connectMessage())

        XCTAssertEqual(client.status.connection, .connected)
        XCTAssertEqual(notified.first, .connected)
        XCTAssertTrue(try socket(0).isListening, "should keep listening after a message")
    }

    // MARK: Dropping and reconnecting

    func testDropMarksDisconnectedAndNotifies() throws {
        client.connect()
        try socket(0).deliver(try connectMessage())
        notified = []

        try socket(0).drop()

        XCTAssertEqual(client.status.connection, .disconnected)
        XCTAssertEqual(notified, [.disconnected])
        XCTAssertFalse(try socket(0).isListening, "shouldn't keep listening on a dead socket")
    }

    func testWaitsGrowFromFiveSecondsAndStopAtSixty() throws {
        client.connect()

        var waits: [TimeInterval] = []
        for _ in 0..<6 {
            sockets.last?.drop()
            waits.append(try XCTUnwrap(clock.delayed.first?.delay))
            clock.fireNextDelayed()
        }

        XCTAssertEqual(waits, [5, 10, 20, 40, 60, 60])
    }

    func testEachWaitEndsInANewSocket() throws {
        client.connect()

        try socket(0).drop()
        XCTAssertEqual(sockets.count, 1, "nothing should reconnect before the wait is over")

        clock.fireNextDelayed()

        XCTAssertEqual(sockets.count, 2)
        XCTAssertEqual(try socket(1).resumeCount, 1)
        XCTAssertEqual(client.status.connection, .connecting)
    }

    /// Two failed connections, leaving socket 2 opening and the next wait at 20 seconds.
    private func failTwice() throws {
        client.connect()
        try socket(0).drop()
        clock.fireNextDelayed()
        try socket(1).drop()
        clock.fireNextDelayed()
    }

    func testAMessageThenACloseDoesNotRestartTheWaits() throws {
        try failTwice()

        try socket(2).deliver(try connectMessage())
        try socket(2).drop()

        XCTAssertEqual(clock.delayed.last?.delay, 20)
    }

    func testAServerThatAlwaysAcceptsThenClosesStillGrowsTheWaits() throws {
        client.connect()

        var waits: [TimeInterval] = []
        for _ in 0..<6 {
            sockets.last?.deliver(try connectMessage())
            sockets.last?.drop()
            waits.append(try XCTUnwrap(clock.delayed.first?.delay))
            clock.fireNextDelayed()
        }

        XCTAssertEqual(waits, [5, 10, 20, 40, 60, 60])
    }

    func testAConnectionUpForAMinuteRestartsTheWaits() throws {
        try failTwice()

        try socket(2).deliver(try connectMessage())
        clock.now += 60
        try socket(2).drop()

        XCTAssertEqual(clock.delayed.last?.delay, 5)
    }

    func testAConnectionUpForJustUnderAMinuteDoesNotRestartTheWaits() throws {
        try failTwice()

        try socket(2).deliver(try connectMessage())
        clock.now += 59
        try socket(2).drop()

        XCTAssertEqual(clock.delayed.last?.delay, 20)
    }

    func testTimeSpentOpeningDoesNotCountAsStable() throws {
        try failTwice()

        clock.now += 60
        try socket(2).deliver(try connectMessage())
        try socket(2).drop()

        XCTAssertEqual(clock.delayed.last?.delay, 20)
    }

    func testWaitsGrowAgainAfterARestart() throws {
        try failTwice()
        try socket(2).deliver(try connectMessage())
        clock.now += 60
        try socket(2).drop()
        clock.fireNextDelayed()

        try socket(3).drop()

        XCTAssertEqual(clock.delayed.last?.delay, 10)
    }

    /// Stopping a connection that had been fine shouldn't leave its old failures behind.
    func testDisconnectingAStableConnectionRestartsTheWaits() throws {
        try failTwice()
        try socket(2).deliver(try connectMessage())
        clock.now += 60
        client.disconnect()

        client.connect()
        try socket(3).drop()

        XCTAssertEqual(clock.delayed.last?.delay, 5)
    }

    /// One server's trouble says nothing about the next station's.
    func testSwitchingStationRestartsTheWaits() throws {
        try failTwice()

        client.switchToStation(station())
        try XCTUnwrap(sockets.last).drop()

        XCTAssertEqual(clock.delayed.last?.delay, 5)
    }

    // MARK: Jitter

    func testWaitsNeverDropBelowHalfTheirLength() throws {
        clock.jitterFraction = 0
        client.connect()

        var waits: [TimeInterval] = []
        for _ in 0..<6 {
            sockets.last?.drop()
            waits.append(try XCTUnwrap(clock.delayed.first?.delay))
            clock.fireNextDelayed()
        }

        XCTAssertEqual(waits, [2.5, 5, 10, 20, 30, 30])
    }

    func testAWaitLandsBetweenItsShortestAndLongest() throws {
        clock.jitterFraction = 0.5
        client.connect()

        try socket(0).drop()

        XCTAssertEqual(clock.delayed.first?.delay, 3.75)
    }

    func testFinishedWaitDoesNothingIfAlreadyConnecting() throws {
        client.connect()
        try socket(0).drop()
        client.connect()
        XCTAssertEqual(sockets.count, 2)

        clock.fireNextDelayed()

        XCTAssertEqual(sockets.count, 2, "should not open a third socket")
    }

    // MARK: Liveness

    func testAMessageStartsATimerAtOneAndAHalfTimesThePing() throws {
        client.connect()

        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()

        XCTAssertEqual(clock.liveTimers.map(\.interval), [30])
    }

    func testAnotherMessageReplacesTheTimer() throws {
        client.connect()
        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()
        let first = try XCTUnwrap(clock.liveTimers.first)

        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()

        XCTAssertTrue(first.isInvalidated)
        XCTAssertEqual(clock.liveTimers.count, 1)
    }

    func testTimerRunningOutClosesTheSocketAndOpensANewOneAfterAWait() throws {
        client.connect()
        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()
        notified = []

        try XCTUnwrap(clock.liveTimers.first).action()

        XCTAssertEqual(try socket(0).cancelCount, 1)
        XCTAssertEqual(client.status.connection, .disconnected)
        XCTAssertEqual(notified, [.disconnected])
        XCTAssertEqual(sockets.count, 1, "nothing should reconnect before the wait is over")
        XCTAssertEqual(clock.delayed.map(\.delay), [5])

        clock.fireNextDelayed()

        XCTAssertEqual(sockets.count, 2)
        XCTAssertEqual(try socket(1).resumeCount, 1)
        XCTAssertEqual(client.status.connection, .connecting)
    }

    func testRepeatedTimeoutsGrowTheWaits() throws {
        client.connect()

        var waits: [TimeInterval] = []
        for _ in 0..<3 {
            sockets.last?.deliver(try connectMessage(ping: 20))
            drainMainQueue()
            try XCTUnwrap(clock.liveTimers.first).action()
            waits.append(try XCTUnwrap(clock.delayed.first?.delay))
            clock.fireNextDelayed()
        }

        XCTAssertEqual(waits, [5, 10, 20])
    }

    func testTimedOutSocketsLateFailureStartsNoSecondWait() throws {
        client.connect()
        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()
        try XCTUnwrap(clock.liveTimers.first).action()

        try socket(0).drop()

        XCTAssertEqual(clock.delayed.count, 1)
    }

    /// Left running, the timer would go off during the wait and count the same failure twice.
    func testADropStopsTheTimer() throws {
        client.connect()
        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()

        try socket(0).drop()

        XCTAssertTrue(clock.liveTimers.isEmpty)
    }

    func testAMessageJustBeforeADropStartsNoTimer() throws {
        client.connect()
        try socket(0).deliver(try connectMessage(ping: 20))

        try socket(0).drop()
        drainMainQueue()

        XCTAssertTrue(clock.liveTimers.isEmpty)
    }

    // MARK: Server-supplied ping

    func testPingsOutsideTheSaneRangeAreHeldToIt() throws {
        let cases: [(ping: Int, timer: TimeInterval)] = [
            (1, 15), (9, 15), (10, 15), (120, 180), (121, 180), (86_400, 180), (Int.max, 180)
        ]
        for (ping, timer) in cases {
            setUp()
            client.connect()

            try socket(0).deliver(try connectMessage(ping: ping))
            drainMainQueue()

            XCTAssertEqual(clock.liveTimers.map(\.interval), [timer], "ping \(ping)")
        }
    }

    // MARK: A connection that opens and stays silent

    func testConnectStartsAThirtySecondTimer() throws {
        client.connect()

        XCTAssertEqual(clock.liveTimers.map(\.interval), [30])
    }

    func testFirstMessageReplacesTheOpeningTimer() throws {
        client.connect()
        let opening = try XCTUnwrap(clock.liveTimers.first)

        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()

        XCTAssertTrue(opening.isInvalidated)
        XCTAssertEqual(clock.liveTimers.map(\.interval), [30], "1.5 times the 20 second ping")
    }

    func testASilentConnectionTimesOutAndRetriesAfterAWait() throws {
        client.connect()
        notified = []

        try XCTUnwrap(clock.liveTimers.first).action()

        XCTAssertEqual(try socket(0).cancelCount, 1)
        XCTAssertEqual(client.status.connection, .disconnected)
        XCTAssertEqual(notified, [.disconnected])
        XCTAssertEqual(clock.delayed.map(\.delay), [5])

        clock.fireNextDelayed()

        XCTAssertEqual(sockets.count, 2)
        XCTAssertEqual(client.status.connection, .connecting)
    }

    func testRepeatedSilentConnectionsGrowTheWaits() throws {
        client.connect()

        var waits: [TimeInterval] = []
        for _ in 0..<3 {
            try XCTUnwrap(clock.liveTimers.first).action()
            waits.append(try XCTUnwrap(clock.delayed.first?.delay))
            clock.fireNextDelayed()
        }

        XCTAssertEqual(waits, [5, 10, 20])
    }

    func testDisconnectStopsTheOpeningTimer() throws {
        client.connect()

        client.disconnect()

        XCTAssertTrue(clock.liveTimers.isEmpty)
    }

    func testNoAddressStartsNoOpeningTimer() throws {
        let empty = ACWebSocketClient(serverName: nil, shortCode: nil, defaultDJ: "",
                                      clock: clock) { _ in FakeSocket() }

        empty.connect()

        XCTAssertTrue(clock.timers.isEmpty)
    }

    func testConnectingAgainWhileOpeningClosesTheOldSocket() throws {
        client.connect()

        client.connect()

        XCTAssertEqual(try socket(0).cancelCount, 1)
        XCTAssertEqual(sockets.count, 2)
    }

    func testAPingOfZeroKeepsThePreviousInterval() throws {
        client.connect()

        try socket(0).deliver(try connectMessage(ping: 0))
        drainMainQueue()

        XCTAssertEqual(clock.liveTimers.map(\.interval), [37.5], "25 seconds is the starting ping")
    }

    func testConnectingStopsARunningTimer() throws {
        client.connect()
        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()
        let running = try XCTUnwrap(clock.liveTimers.first)

        client.connect()

        XCTAssertTrue(running.isInvalidated)
        XCTAssertEqual(clock.liveTimers.count, 1, "only the new connection's timer")
    }

    // MARK: Other messages

    func testBinaryMessageChangesNothingAndKeepsListening() throws {
        client.connect()

        try socket(0).deliverBinary()

        XCTAssertEqual(client.status.connection, .connecting)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertTrue(try socket(0).isListening)
    }

    /// Unusable messages leave what's on screen alone, and the socket keeps listening.
    private func assertIgnoredAfterASong(_ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        client.connect()
        try socket(0).deliver(try connectMessage())
        drainMainQueue()
        let track = client.status.track
        let notifications = notifiedTracks.count
        XCTAssertFalse(track.isEmpty, file: file, line: line)

        try socket(0).deliver(message)
        drainMainQueue()

        XCTAssertEqual(client.status.track, track, file: file, line: line)
        XCTAssertEqual(notifiedTracks.count, notifications, file: file, line: line)
        XCTAssertTrue(try socket(0).isListening, file: file, line: line)
    }

    func testMalformedChannelMessageKeepsTheCurrentSong() throws {
        try assertIgnoredAfterASong(#"{"channel": "station:rs-one", "pub": 5}"#)
    }

    func testMessageThatIsNotAnObjectKeepsTheCurrentSong() throws {
        try assertIgnoredAfterASong("[1, 2, 3]")
    }

    func testMalformedServerNameOpensNoSocket() throws {
        let client = ACWebSocketClient(serverName: "not a host", shortCode: shortCode, defaultDJ: "",
                                       clock: clock) { [unowned self] url in
            self.requestedURLs.append(url)
            return FakeSocket()
        }

        client.connect()

        XCTAssertTrue(requestedURLs.isEmpty)
        XCTAssertEqual(client.status.connection, .disconnected)
    }

    /// Reconnecting to the old station would show its metadata under the new one.
    func testSwitchingToAMalformedServerNameDoesNotReuseTheOldAddress() throws {
        client.connect()

        client.switchToStation(station(server: "not a host"))

        XCTAssertEqual(requestedURLs.map(\.absoluteString),
                       ["wss://radio.example/api/live/nowplaying/websocket"])
    }

    func testNoAddressMeansNoSocket() throws {
        let empty = ACWebSocketClient(serverName: nil, shortCode: nil, defaultDJ: "",
                                      clock: clock) { [unowned self] url in
            self.requestedURLs.append(url)
            return FakeSocket()
        }

        empty.connect()

        XCTAssertTrue(requestedURLs.isEmpty)
        XCTAssertEqual(empty.status.connection, .disconnected)
    }

    func testFailedSubscriptionSendIsRecordedButNobodyIsTold() throws {
        let failing = FakeSocket()
        failing.sendError = URLError(.networkConnectionLost)
        let client = ACWebSocketClient(serverName: "radio.example", shortCode: shortCode, defaultDJ: "",
                                       clock: clock) { _ in failing }
        client.addSubscriber { [unowned self] status in self.notified.append(status.connection) }

        client.connect()

        XCTAssertEqual(client.status.connection, .failedSubscribe)
        XCTAssertTrue(notified.isEmpty)
    }

    // MARK: Switching station

    func testSwitchingClosesTheOldSocketAndOpensOneToTheNewServer() throws {
        client.connect()
        try socket(0).deliver(try connectMessage())

        client.switchToStation(station())

        XCTAssertEqual(try socket(0).cancelCount, 1)
        XCTAssertEqual(requestedURLs.last?.absoluteString,
                       "wss://next.example/api/live/nowplaying/websocket")
        XCTAssertEqual(try socket(1).resumeCount, 1)
        XCTAssertEqual(client.status.connection, .connecting)
    }

    // A cancelled socket reports its failure some time later. By then it no longer counts.
    func testOldSocketsLateFailureLeavesTheNewConnectionAlone() throws {
        client.connect()
        client.switchToStation(station())
        XCTAssertEqual(client.status.connection, .connecting)
        notified = []

        try socket(0).drop()

        XCTAssertEqual(client.status.connection, .connecting)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertTrue(clock.delayed.isEmpty)
    }

    func testOldSocketsLateSendFailureLeavesTheNewConnectionAlone() throws {
        holdSendResults = true
        client.connect()
        client.switchToStation(station())

        try socket(0).finishHeldSend(with: URLError(.cancelled))

        XCTAssertEqual(client.status.connection, .connecting)
    }

    func testNewSocketsFirstMessageConnectsAfterAnOldSocketsLateFailure() throws {
        client.connect()
        client.switchToStation(station())
        try socket(0).drop()
        notified = []

        try socket(1).deliver(try connectMessage())

        XCTAssertEqual(client.status.connection, .connected)
        XCTAssertTrue(notified.contains(.connected))
    }

    func testOldSocketsMessageIsNotTakenForTheNewStations() throws {
        client.connect()
        client.switchToStation(station())
        notifiedTracks = []
        let timersBefore = clock.timers.count

        try socket(0).deliver(try connectMessage())
        drainMainQueue()

        XCTAssertEqual(client.status.connection, .connecting)
        XCTAssertEqual(client.status.track, "")
        XCTAssertTrue(notifiedTracks.isEmpty)
        XCTAssertEqual(clock.timers.count, timersBefore, "the old socket shouldn't start a timer")
    }

    // MARK: Disconnecting

    func testDisconnectClosesTheSocketAndNotifies() throws {
        client.connect()
        try socket(0).deliver(try connectMessage())
        notified = []

        client.disconnect()

        XCTAssertEqual(try socket(0).cancelCount, 1)
        XCTAssertEqual(client.status.connection, .disconnected)
        XCTAssertEqual(notified, [.disconnected])
    }

    // disconnect() is final: nothing reconnects until connect() is called again.
    func testDisconnectCancelsAWaitAlreadyRunning() throws {
        client.connect()
        try socket(0).drop()
        client.disconnect()

        clock.fireNextDelayed()

        XCTAssertEqual(sockets.count, 1)
        XCTAssertEqual(client.status.connection, .disconnected)
    }

    func testLateFailureAfterDisconnectIsIgnored() throws {
        client.connect()
        client.disconnect()
        notified = []

        try socket(0).drop()

        XCTAssertTrue(clock.delayed.isEmpty)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertEqual(client.status.connection, .disconnected)
    }

    func testLateSendFailureAfterDisconnectIsIgnored() throws {
        holdSendResults = true
        client.connect()
        client.disconnect()

        try socket(0).finishHeldSend(with: URLError(.cancelled))

        XCTAssertEqual(client.status.connection, .disconnected)
    }

    func testCurrentSocketsLateSendFailureIsStillRecorded() throws {
        holdSendResults = true
        client.connect()

        try socket(0).finishHeldSend(with: URLError(.networkConnectionLost))

        XCTAssertEqual(client.status.connection, .failedSubscribe)
    }

    /// Runs on a background thread, as URLSession does, and returns with the main thread having
    /// run nothing in between: a semaphore, because an XCTest wait would drain the main queue.
    private func onURLSessionThread(_ action: @escaping () -> Void) {
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            action()
            finished.signal()
        }
        finished.wait()
    }

    func testFailureRacingADisconnectStartsNoWait() throws {
        client.connect()
        let first = try socket(0)

        onURLSessionThread { first.drop() }
        client.disconnect()
        drainMainQueue()

        XCTAssertTrue(clock.delayed.isEmpty)
        XCTAssertEqual(client.status.connection, .disconnected)
    }

    func testMessageRacingADisconnectDoesNotConnect() throws {
        client.connect()
        let first = try socket(0)
        let message = try connectMessage()

        onURLSessionThread { first.deliver(message) }
        client.disconnect()
        drainMainQueue()

        XCTAssertEqual(client.status.connection, .disconnected)
        XCTAssertFalse(notified.contains(.connected))
    }

    func testFailureFromTheURLSessionThreadStillStartsAWait() throws {
        client.connect()
        let first = try socket(0)

        onURLSessionThread { first.drop() }
        drainMainQueue()

        XCTAssertEqual(clock.delayed.first?.delay, 5)
        XCTAssertEqual(client.status.connection, .disconnected)
    }

    func testDisconnectStopsTheLivenessTimer() throws {
        client.connect()
        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()
        XCTAssertEqual(clock.liveTimers.count, 1)

        client.disconnect()

        XCTAssertTrue(clock.liveTimers.isEmpty)
    }

    /// handleMessage queues its timer on the main thread, so a disconnect can get in first.
    func testMessageJustBeforeDisconnectStartsNoTimerOrMetadata() throws {
        client.connect()
        try socket(0).deliver(try connectMessage(ping: 20))

        client.disconnect()
        drainMainQueue()

        XCTAssertTrue(clock.liveTimers.isEmpty)
        XCTAssertEqual(client.status.track, "")
    }

    func testMessageAfterDisconnectIsIgnored() throws {
        client.connect()
        client.disconnect()
        notified = []

        try socket(0).deliver(try connectMessage())
        drainMainQueue()

        XCTAssertEqual(client.status.connection, .disconnected)
        XCTAssertTrue(notified.isEmpty)
        XCTAssertFalse(try socket(0).isListening)
    }

    func testConnectAfterDisconnectOpensANewSocket() throws {
        client.connect()
        client.disconnect()

        client.connect()

        XCTAssertEqual(sockets.count, 2)
        XCTAssertEqual(client.status.connection, .connecting)
    }

    /// A wait left over from before a connect() would otherwise cut the next wait short.
    func testConnectReplacesAWaitAlreadyRunning() throws {
        client.connect()
        try socket(0).drop()
        client.connect()
        try socket(1).drop()
        XCTAssertEqual(clock.delayed.count, 2)

        clock.fireNextDelayed()
        XCTAssertEqual(sockets.count, 2)

        clock.fireNextDelayed()
        XCTAssertEqual(sockets.count, 3)
    }

    // MARK: What subscribers receive

    // Known-wrong (F1): the comment in handleMessage says a repeat is skipped.
    func testRepeatedMessageNotifiesAgain() throws {
        client.switchToStation(station())
        let message = try connectMessage()
        try socket(0).deliver(message)
        drainMainQueue()
        let afterFirst = notifiedTracks.count
        XCTAssertGreaterThan(afterFirst, 0)

        try socket(0).deliver(message)
        drainMainQueue()

        XCTAssertEqual(notifiedTracks.count, afterFirst + 1)
    }

    func testAMessageReachesSubscribersWithItsTrackAndTheRealConnectionState() throws {
        client.connect()

        try socket(0).deliver(try connectMessage())
        drainMainQueue()

        let expected = try ParseWebSocketData(data: try ConnectMessageFixture.data(), defaultDJ: "")
            .parse(shortCode: shortCode).track
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(notifiedTracks.last, expected)
        XCTAssertEqual(notified.last, .connected)
        XCTAssertEqual(client.status.track, expected)
    }

    // Known-wrong (F3): the parser reports a failed subscription, and this replaces it.
    func testUnknownShortCodeSendsBlankMetadataAndKeepsTheConnectedState() throws {
        client.switchToStation(station(shortCode: "no-such-station"))

        try socket(0).deliver(try connectMessage())
        drainMainQueue()

        XCTAssertEqual(notifiedTracks.last, "")
        XCTAssertEqual(notified.last, .connected)
        XCTAssertFalse(notified.contains(.failedSubscribe))
        XCTAssertEqual(client.status.connection, .connected)
    }

    // Known-wrong (F3): the parser reports the station as offline, and this replaces it.
    func testOfflineStationKeepsTheConnectedState() throws {
        client.connect()
        let data = try ConnectMessageFixture.data { $0["is_online"] = false }

        try socket(0).deliver(try XCTUnwrap(String(data: data, encoding: .utf8)))
        drainMainQueue()

        XCTAssertEqual(notified.last, .connected)
        XCTAssertEqual(client.status.connection, .connected)
    }
}
