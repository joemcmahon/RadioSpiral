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
    private var pendingReceive: ((Result<URLSessionWebSocketTask.Message, Error>) -> Void)?

    func resume() { resumeCount += 1 }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { cancelCount += 1 }

    func send(_ message: URLSessionWebSocketTask.Message,
              completionHandler: @escaping @Sendable (Error?) -> Void) {
        sent.append(message)
        completionHandler(nil)
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

    func runAfter(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        delayed.append((delay, action))
    }

    func startTimer(interval: TimeInterval, _ action: @escaping () -> Void) -> LivenessTimer {
        let timer = FakeTimer(interval: interval, action: action)
        timers.append(timer)
        return timer
    }

    func fireNextDelayed() {
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

    override func setUp() {
        super.setUp()
        sockets = []
        requestedURLs = []
        notified = []
        clock = FakeClock()
        client = ACWebSocketClient(serverName: "radio.example", shortCode: shortCode, defaultDJ: "",
                                   clock: clock) { [unowned self] url in
            self.requestedURLs.append(url)
            let socket = FakeSocket()
            self.sockets.append(socket)
            return socket
        }
        client.addSubscriber { [unowned self] status in self.notified.append(status.connection) }
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

    func testAMessageRestartsTheWaitsAtFiveSeconds() throws {
        client.connect()
        try socket(0).drop()
        clock.fireNextDelayed()
        try socket(1).drop()
        clock.fireNextDelayed()

        try socket(2).deliver(try connectMessage())
        try socket(2).drop()

        XCTAssertEqual(clock.delayed.last?.delay, 5)
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
        let first = try XCTUnwrap(clock.timers.first)

        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()

        XCTAssertTrue(first.isInvalidated)
        XCTAssertEqual(clock.timers.count, 2)
        XCTAssertEqual(clock.liveTimers.count, 1)
    }

    func testTimerRunningOutClosesTheSocketAndOpensANewOne() throws {
        client.connect()
        try socket(0).deliver(try connectMessage(ping: 20))
        drainMainQueue()

        try XCTUnwrap(clock.liveTimers.first).action()

        XCTAssertEqual(try socket(0).cancelCount, 1)
        XCTAssertEqual(sockets.count, 2)
        XCTAssertEqual(try socket(1).resumeCount, 1)
        XCTAssertEqual(client.status.connection, .connecting)
    }
}
