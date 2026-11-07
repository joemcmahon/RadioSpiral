//
//  ACWebSocketClient.swift
//
//  Created by Joe McMahon on 12/18/24.
//

import Foundation
import Combine

public let ACExtractedData = 1
public let ACRawSubsections = 2
public let ACFullDump = 4
public let ACConnectivityChecks = 8
public let ACActivityTrace = 16


/// Type describing a callback to send the current status to a subscriber.
public typealias MetadataCallback<T> = (T) -> Void

/// The parts of `URLSessionWebSocketTask` the client uses, so tests can supply a fake socket.
/// `URLProtocol` can't stand in for one: it sees the task, but its bytes never become messages.
protocol WebSocketTasking: AnyObject {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping @Sendable (Error?) -> Void)
    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
}

extension URLSessionWebSocketTask: WebSocketTasking {}

/// A running liveness timer.
protocol LivenessTimer {
    func invalidate()
}

extension Timer: LivenessTimer {}

/// The client's delays, the time and its randomness, so tests can control them.
protocol SocketClock {
    var now: Date { get }
    /// A random value from 0 to 1, for spreading out retry waits.
    func randomFraction() -> Double
    /// Runs `action` after `delay`. Can't be cancelled.
    func runAfter(_ delay: TimeInterval, _ action: @escaping () -> Void)
    /// Starts a one-shot timer on the current run loop.
    func startTimer(interval: TimeInterval, _ action: @escaping () -> Void) -> LivenessTimer
}

/// The clock used outside tests.
struct LiveSocketClock: SocketClock {
    var now: Date { Date() }

    func randomFraction() -> Double { Double.random(in: 0...1) }

    func runAfter(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }

    func startTimer(interval: TimeInterval, _ action: @escaping () -> Void) -> LivenessTimer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() }
    }
}

///  The `ACWebSocketClient` class allows us to connect to an Azuracast websocket server
///  for realtime stream metadata updates via a  supplied callback.
public class ACWebSocketClient: ObservableObject {
    
    /// Singleton instance; used  (particularly in SwiftUI) to ensure that everyone is using the same ciient.
    public static let shared = ACWebSocketClient()
        
    // Anyone subscribed to the metadata stream
    private var subscribers: [MetadataCallback<ACStreamStatus>] = []
    
    /// Current status for this client. If this is the singleton client, this status should be the same
    /// for all references to the client.
    public var status = ACStreamStatus()
        
    private var webSocketTask: WebSocketTasking?
    private var makeSocket = ACWebSocketClient.liveSocketMaker()
    private var clock: SocketClock = LiveSocketClock()
    private var webSocketURL: URL?
    
    // Used to monitor connection to the metadata API. When we receive a connect
    // message, we clear out any old timer, then set a new one for a little after
    // the runtime of the track that's playing now. If all goes well, we'll get
    // another message before the time goes off, cancel it, and set a new one.
    // If we don't get a message before then, the timer pops, we close the socket,
    // and reconnect after the retry wait, like any other failure.
    //
    private var stillAliveTimer: LivenessTimer? {
        willSet {
            if let timer = stillAliveTimer {
                timer.invalidate()
            }
        }
        didSet {
            if stillAliveTimer != nil {
            }
        }
    }
    /// `serverName` is the name of the Azuracast server we're connecting to for the metadata stream
    var serverName: String?
    
    /// `shortCode` is the station name shortcode defined by Azuracast and found on the stations's profile page
    var shortCode: String?
    
    /// `defaultDJ`: the string to be retuned as the active DJ if no streamer is connected. Publically accessible.
    /// Set by `setDefaultDJ`.
    public var defaultDJ: String?
    
    /// `debugLevel`: for development only; set to  the sum of the flag values you want while debugging
    /// - 0: no debug outout is printed
    /// - 1: print the minimum data (track, artist, album, DJ)
    /// - 2: print the raw subsections the data is extracted from
    /// - 4: print the full set of JSON received from the stream before parsing`
    public var debugLevel: Int = 0
    
    private var lastResult: ACStreamStatus?
    private var consecutiveFailures: Int = 0
    // Moves on with every connect() and disconnect(), so a reconnect wait started before
    // either one can tell it's out of date when it finishes.
    private var reconnectGeneration: Int = 0
    private var lastKnownPingInterval: TimeInterval = 25.0
    // When the current connection got its first message. Nil unless it's connected.
    private var connectedAt: Date?

    // How long a connection must stay up before its earlier failures stop counting.
    // A first message isn't enough: a struggling server can reply and then close.
    private static let stablePeriod: TimeInterval = 60
    // How long a new socket has to deliver its first message.
    private static let openingTimeout: TimeInterval = 30
    // The ping comes from the server, so it only gets to move the liveness timer this far.
    private static let pingRange: ClosedRange<TimeInterval> = 10...120

    /// Centralized debug logging with ISO timestamps and component tags.
    private func debugLog(_ tag: String, _ message: String, _ flag: Int = ACConnectivityChecks) {
        guard debugLevel & flag != 0 else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        print("\(timestamp) \(tag) \(message)")
    }

    /// Constructs an empty `ACWebSoscketClient`, which must be initialized with
    /// `configurationDidChange` and `setDefaultDJ`.
    public init() {
        debugLog("[Init]", "Creating empty client", ACActivityTrace)
    }
    
    ///  Initializes an `ACWebSocketClient` instance with a preset server and station.
    /// - Parameters:
    ///   - serverName: The server name of the server to connect to
    ///   - `shortCode`: The Azuracast-defined shortcode from the station's profile page
    ///   - `defaultDJ`: The DJ name to supply if no streamer is active. Useful if the station is configured to play music when no streamer is active. Defaults to `""` if no value is specified.
    public init (serverName: String?, shortCode: String?, defaultDJ: String? = "") {
        debugLog("[Init]", "Creating configured client", ACActivityTrace)

        if let defaultDJ {
            self.defaultDJ = defaultDJ
        }
        if let serverName, let shortCode {
            self.serverName = serverName
            self.shortCode = shortCode
            constructWebSocketURL(serverName: serverName)
        }
    }
    
    /// Initializes a client for tests, with a fake clock and socket.
    init(serverName: String?, shortCode: String?, defaultDJ: String? = "",
         clock: SocketClock, makeSocket: @escaping (URL) -> WebSocketTasking) {
        self.clock = clock
        self.makeSocket = makeSocket
        self.defaultDJ = defaultDJ
        if let serverName, let shortCode {
            self.serverName = serverName
            self.shortCode = shortCode
            constructWebSocketURL(serverName: serverName)
        }
    }

    private static func liveSocketMaker() -> (URL) -> WebSocketTasking {
        let session = URLSession(configuration: .default)
        return { session.webSocketTask(with: $0) }
    }

    private func constructWebSocketURL(serverName: String) {
        // The name comes from the remote config. Without a usable address, `connect()` does
        // nothing, rather than crashing or reconnecting to the previous station's address.
        self.webSocketURL = URL(string: "wss://\(String(describing: serverName))/api/live/nowplaying/websocket")
        if self.webSocketURL == nil {
            debugLog("[Connect]", "Invalid server name for WebSocket URL: \(serverName)", ACActivityTrace | ACConnectivityChecks)
        }
    }

    
    /// Adds a subscriber to the metadata returned asynchronously by the Azuracast now-plaiing API.
    /// - Parameter callback: Callback function to be called when a change to the station metadata
    /// is detected.
    ///
    /// The callback has the form `callbackFunction(status: StreamStatus)`; the `callback`
    /// parameter should be given only `callbackFunction`.
    public func addSubscriber(callback: @escaping MetadataCallback<ACStreamStatus>) {
        debugLog("[Subscribe]", "adding subscriber", ACActivityTrace)
        subscribers.append(callback)
    }
    
    /// Sets the default value to be returned as the DJ name when no streamer is connected.
    /// - Parameter name: The string  to be returned as the DJ's name when no streamer is active.
    public func setDefaultDJ(name: String) {
        defaultDJ = name
    }
    
    /// Sets the debug output level for the JSON parsing.
    ///
    /// Sum the values desired and use them as the `to:` argument
    ///  - 0: No debug output
    ///  - 1: Print the final derived values only.
    ///  - 2: Print the subsections of the JSON that are used to extract the data.
    ///  - 4: Print the raw incoming JSON in its entirety.
    public func debug(to: Int) {
        debugLevel = to
    }
    
    // Notify all suscribers when an update occurs
    private func notifySubscribers(with data: ACStreamStatus) {
        debugLog("[Notify]", "sending notifications", ACActivityTrace)
        for callback in subscribers {
            callback(data)
        }
    }
    
    /// switchToStation lets us pass a RadioStation in to set all the relevant URLs, etc. and (re)connect
    /// the websocket.
    func switchToStation(_ station: RadioStation) {
        debugLog("[SwitchStation]", "Switching to station: \(station.shortCode)", ACActivityTrace)

        self.serverName = station.serverName
        self.shortCode = station.shortCode
        self.defaultDJ = station.defaultDJ
        // The failures so far were the previous server's.
        consecutiveFailures = 0
        // The status still describes the previous station. Left in place, it would be
        // republished as the new station's metadata until the first message arrives.
        self.status = ACStreamStatus()
        self.disconnect()
        self.constructWebSocketURL(serverName: station.serverName)
        self.connect()
        self.lastResult = ACStreamStatus()
    }
    
    /// Connects to the websocket API and sends the subscription message. Can be used to connect a
    /// currently-disconnected `ACWebSocketClient` or to reconnect an already-connected one.
    /// Marks the global status as `connected`.
    public func connect() {
        // turn off the liveness check; the first parse of the connect data will
        // turn it back on.
        debugLog("[Connect]", "connect() called, current state: \(status.connection)", ACActivityTrace | ACConnectivityChecks)
        reconnectGeneration += 1
        self.stillAliveTimer?.invalidate()
        if status.connection == ACConnectionState.connected {
            debugLog("[Connect]", "Already connected, disconnecting first", ACActivityTrace | ACConnectivityChecks)
            disconnect()
        }
        // A socket still opening is replaced below. Left alone, it would stay open.
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        if let _ = self.webSocketURL {
            debugLog("[Connect]", "Starting websocket task to \(self.webSocketURL!)", ACActivityTrace | ACConnectivityChecks)
            webSocketTask = makeSocket(self.webSocketURL!)
            webSocketTask?.resume()
            status.connection = .connecting
            debugLog("[Connect]", "State set to connecting", ACActivityTrace | ACConnectivityChecks)
            // A connection can open and then say nothing. The first message replaces this timer.
            stillAliveTimer = clock.startTimer(interval: Self.openingTimeout) { self.fellOver() }
            sendSubscriptionMessage()
            listenForMessages()
        } else {
            debugLog("[Connect]", "No webSocketURL, cannot connect", ACActivityTrace | ACConnectivityChecks)
        }
     }
    
    /// Disconnects from the WebSocket API.  Sets the global status to `disconnected`.
    /// Always notifies subscribers so downstream consumers (StationMetadataManager)
    /// track the actual connection state. Duplicate .disconnected notifications are
    /// harmless — removeDuplicates() on the Combine chain handles idempotency.
    ///
    /// Final: nothing reconnects until `connect()` is called again. It ends any reconnect wait
    /// and the liveness timer, and the cancelled socket's own late failure is ignored.
    public func disconnect() {
        debugLog("[Disconnect]", "disconnect() called, current state: \(status.connection)", ACActivityTrace | ACConnectivityChecks)
        reconnectGeneration += 1
        endConnection()
        status.connection = .disconnected
        debugLog("[Disconnect]", "State set to disconnected", ACActivityTrace | ACConnectivityChecks)
        notifySubscribers(with: status)
    }
    
    // Stops the timer and closes the socket, so nothing more from it counts. A connection
    // that stayed up long enough clears the failures that came before it.
    private func endConnection() {
        stillAliveTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        if let connectedAt, clock.now.timeIntervalSince(connectedAt) >= Self.stablePeriod {
            consecutiveFailures = 0
        }
        connectedAt = nil
    }

    // Called if the liveness timer goes off, or if a new socket never sends a first message.
    func fellOver() {
        debugLog("[FellOver]", "Timer expired, last ping \(lastKnownPingInterval) seconds, state: \(status.connection)")
        connectionFailed()
    }

    // Everything that ends a connection unasked comes here, and waits its turn to retry.
    private func connectionFailed() {
        endConnection()
        status.connection = .disconnected
        status.changed = true
        debugLog("[WebSocket]", "State set to disconnected after failure")
        // Notify subscribers of disconnection so NowPlayingVC can
        // stop AVPlayer (prevents aggressive internal retries).
        notifySubscribers(with: status)
        scheduleReconnect()
    }

    // Schedules a reconnection attempt after a failure.
    // Reconnects only if no connect() or disconnect() has happened since, and we're still
    // disconnected. Doesn't check whether the network is reachable.
    // Uses exponential backoff: 5s, 10s, 20s, 40s, 60s max. Each wait lands at random
    // between half that and all of it, so listeners dropped together don't return together.
    private func scheduleReconnect() {
        let baseDelay: TimeInterval = 5.0
        let maxDelay: TimeInterval = 60.0
        let longestDelay = min(baseDelay * pow(2.0, Double(consecutiveFailures)), maxDelay)
        let reconnectDelay = longestDelay * (0.5 + 0.5 * clock.randomFraction())
        consecutiveFailures += 1
        debugLog("[ScheduleReconnect]", "Scheduling reconnect in \(reconnectDelay) seconds (attempt \(consecutiveFailures)), current state: \(status.connection)")
        let generation = reconnectGeneration
        clock.runAfter(reconnectDelay) { [weak self] in
            guard let self = self, generation == self.reconnectGeneration else { return }
            self.debugLog("[ScheduleReconnect]", "Timer fired, state: \(self.status.connection)")
            if self.status.connection != .connected && self.status.connection != .connecting {
                self.debugLog("[ScheduleReconnect]", "Attempting connect")
                self.connect()
            } else {
                self.debugLog("[ScheduleReconnect]", "Already connected/connecting, skipping reconnect")
            }
        }
    }

    // Sends the subscription message for the specified station.
    // If the websocket task is already running, does nothing.
    // If the necessary parameters aren't set, does nothing and marks
    // `failedSubscribe` in the global status.
    // Otherwise generates the expected subscription message and sends it.
    private func sendSubscriptionMessage() {
        guard let webSocketTask = webSocketTask else { return }
        debugLog("[Subscribe]", "Subscribing", ACActivityTrace)
        guard let _ = self.serverName,
              let _ = self.shortCode else {
            status.connection = ACConnectionState.failedSubscribe
            status.changed = true
            debugLog("[Subscribe]", "Subscription failed!", ACActivityTrace)
            return
        }
        
        let subscriptionMessage = ["subs": ["station:\(self.shortCode!)": ["recover": true]]]
        if let jsonData = try? JSONSerialization.data(withJSONObject: subscriptionMessage, options: []) {
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            webSocketTask.send(.string(jsonString)) { error in
                if let error = error {
                    print("Failed to send subscription message: \(error)")
                    Self.onMain {
                        // A replaced or cancelled socket no longer speaks for this client.
                        guard webSocketTask === self.webSocketTask else { return }
                        self.status.connection = ACConnectionState.failedSubscribe
                        self.status.changed = true
                    }
                }
            }
        } else {
            
            debugLog("[Subscribe]", "Failed to encode subscription message", ACActivityTrace)
            status.connection = ACConnectionState.failedSubscribe
            status.changed = true
        }
        debugLog("[Subscribe]", "Subscription complete", ACActivityTrace)
    }
    
    // Listens for incoming messages from the WebSocket server.
    // All incoming messages should be text.
    private func listenForMessages() {
        debugLog("[Listen]", "Start listening for messages", ACActivityTrace)
        guard let socket = webSocketTask else { return }
        socket.receive { [weak self] result in
            // URLSession calls this on its own thread. Everything that decides whether a socket
            // is still current runs on main, like connect() and disconnect(), so they can't overlap.
            Self.onMain { self?.handleReceive(result, from: socket) }
        }
    }

    // Runs right away on main, so that a caller already there sees the result at once.
    private static func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>, from socket: WebSocketTasking) {
        // A replaced or cancelled socket no longer speaks for this client. Its late
        // failure isn't a dropped connection, and its messages aren't current.
        guard socket === webSocketTask else { return }

        debugLog("[Listen]", "message received", ACActivityTrace)
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                handleMessage(text, from: socket)
            case .data(let data):
                debugLog("[Received]","Received binary data: \(data)", ACExtractedData)
            @unknown default:
                debugLog("[Received]","Received unknown message type", ACExtractedData)
            }
        case .failure(let error):
            if debugLevel & ACConnectivityChecks != 0 {
                debugLog("[WebSocket]", "Error received: \(error), scheduling reconnect")
            } else {
                print("WebSocket error: \(error)")
            }
            // Don't keep listening on dead socket - schedule reconnection instead
            connectionFailed()
            return
        }

        // Keep listening for new messages (only on success)
        listenForMessages()
    }
    
    // Handles incoming messages and updates the status.
    private func handleMessage(_ message: String, from socket: WebSocketTasking) {
        debugLog("[HandleMessage]", "Handling message", ACActivityTrace)

        // First successful message confirms connection
        if status.connection == .connecting {
            status.connection = .connected
            connectedAt = clock.now
            debugLog("[HandleMessage]", "First message received, state set to connected", ACActivityTrace)
            // Notify subscribers immediately so downstream consumers
            // (StationMetadataManager) learn about reconnection even if
            // the metadata hasn't changed (e.g. same track still playing).
            notifySubscribers(with: status)
        }

        // Reset liveness timer BEFORE parsing. Any message at all proves
        // the WebSocket is alive — we don't need a successful parse for that.
        DispatchQueue.main.async {
            // The socket may have been disconnected or replaced since this was queued.
            guard socket === self.webSocketTask else { return }
            self.stillAliveTimer?.invalidate()
            let interval = self.lastKnownPingInterval * 1.5
            self.stillAliveTimer = self.clock.startTimer(interval: interval) { self.fellOver() }
            self.debugLog("[HandleMessage]", "liveness timer reset to \(interval)s (pingInterval \(self.lastKnownPingInterval)s + 50% leeway)", ACActivityTrace)
        }

        // Decode into data for parseWebSocketData.
        guard let data = message.data(using: .utf8) else {
            print("Failed to decode message to data")
            return
        }

        // Save last result.
        lastResult?.album = status.album
        lastResult?.artist = status.artist
        lastResult?.track = status.track
        lastResult?.artwork = status.artwork
        lastResult?.dj = status.dj

        do {
            // Attempt to parse the data. Parser will throw if it fails to work.
            let parser = ParseWebSocketData(data: data, defaultDJ: defaultDJ)
            parser.debug(to: debugLevel)

            // I can hard-unwrap this because I had to have a value to connect
            // at all. The shortCode is needed because one key contains it.
            let result = try parser.parse(shortCode: shortCode!)

            // Update stored pingInterval from successful parse
            if let ping = result.pingInterval, ping > 0 {
                lastKnownPingInterval = min(max(Double(ping), Self.pingRange.lowerBound), Self.pingRange.upperBound)
            }

            DispatchQueue.main.async {
                guard socket === self.webSocketTask else { return }
                if result != self.lastResult && result.changed {
                    // Status changed from old values. (Note that the initial
                    // connect message and one or more subsequent channel
                    // messages may contain the same data; if they do, we'll
                    // skip this.) Record the new status and call all the
                    // callbacks.
                    // Preserve connection and network state - these are managed
                    // separately from parsed data. The parser creates a new
                    // ACStreamStatus with connection = .disconnected by default,
                    // which would overwrite the actual connection state.
                    let currentConnection = self.status.connection
                    self.status = result
                    self.status.connection = currentConnection
                    self.notifySubscribers(with: self.status)
                }
            }
        } catch {
            // Parse should NEVER fail — the parser has been thoroughly tested.
            // If this fires, something fundamentally unexpected happened.
            debugLog("[HandleMessage]", "PARSE FAILURE — THIS SHOULD NEVER HAPPEN: \(error)")
            debugLog("[HandleMessage]", "Raw message (\(message.count) chars): \(String(message.prefix(500)))")
        }
    }
}
