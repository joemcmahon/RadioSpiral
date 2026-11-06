//
//  StationsManagerIntegrationTests.swift
//  ConfigClientTests
//
//  What the real StationsManager does when the station list changes, and how next and
//  previous move through the list. Lists arrive by the real path: fetch, DataManager, the
//  app's ConfigClient, then a canned config from StubURLProtocol.
//
//  The app is running behind these tests and shares these singletons, so:
//  - Its launch fetch must finish first, or its reply could replace a test's list.
//  - DataManager sets the config URL itself, so both servers' URLs get the canned reply.
//  - Stations use .invalid hosts and a bundled image, so nothing reaches a real server.
//  - Afterwards the original list and session are back, and no station is selected.
//

import XCTest
@testable import RadioSpiral

final class StationsManagerIntegrationTests: XCTestCase {

    private static var originalSession: URLSession?
    private static var originalStations: [RadioStation] = []

    private var manager: StationsManager { StationsManager.shared }
    private var observer: StationsObserverSpy!

    private let one = StationsManagerIntegrationTests.station("one")
    private let two = StationsManagerIntegrationTests.station("two")
    private let three = StationsManagerIntegrationTests.station("three")

    // MARK: Class setup

    override class func setUp() {
        super.setUp()
        // No signal says the launch fetch is done. A list means it succeeded; offline there's
        // never a list, so stop after its 10 second request timeout. The extra second lets the
        // app open a single station, which happens on the next layout pass.
        let deadline = Date().addingTimeInterval(12)
        while StationsManager.shared.stations.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1))

        originalStations = StationsManager.shared.stations
        originalSession = RadioSpiral.ConfigClient.shared.session
        RadioSpiral.ConfigClient.shared.session = StubURLProtocol.makeSession()
    }

    override class func tearDown() {
        StationsManager.shared.set(station: nil)
        if !originalStations.isEmpty {
            replyToConfigRequests(with: originalStations)
            let finished = XCTestExpectation(description: "original list restored")
            StationsManager.shared.fetch { _ in finished.fulfill() }
            _ = XCTWaiter.wait(for: [finished], timeout: 5)
        }
        StubURLProtocol.reset()
        if let originalSession {
            RadioSpiral.ConfigClient.shared.session = originalSession
        }
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        manager.set(station: nil)
        observer = StationsObserverSpy()
        manager.addObserver(observer)
    }

    override func tearDown() {
        manager.set(station: nil)
        observer = nil
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Helpers

    private static func station(_ code: String, desc: String? = nil, serverName: String? = nil,
                                shortCode: String? = nil, defaultDJ: String = "DJ") -> RadioStation {
        RadioStation(name: "\(code) name",
                     streamURL: "https://\(code).invalid/stream",
                     imageURL: "stationImage",
                     desc: desc ?? "\(code) desc",
                     longDesc: "\(code) long",
                     serverName: serverName ?? "\(code).invalid",
                     shortCode: shortCode ?? code,
                     defaultDJ: defaultDJ)
    }

    private static func replyToConfigRequests(with stations: [RadioStation]) {
        let entries = stations.map { station in
            ["name": station.name, "streamURL": station.streamURL, "imageURL": station.imageURL,
             "desc": station.desc, "longDesc": station.longDesc, "serverName": station.serverName,
             "shortCode": station.shortCode, "defaultDJ": station.defaultDJ]
        }
        let config: [String: Any] = ["configs": [["format": "static", "stations": entries]]]
        let body = try! JSONSerialization.data(withJSONObject: config)
        StubURLProtocol.reply(to: StationServer.production.configURL, with: .http(status: 200, body: body))
        StubURLProtocol.reply(to: StationServer.test.configURL, with: .http(status: 200, body: body))
    }

    /// Fetches the list through the real path. Returns what the fetch's completion received.
    @discardableResult
    private func deliver(_ stations: [RadioStation]) -> [RadioStation]? {
        Self.replyToConfigRequests(with: stations)
        return fetch()
    }

    @discardableResult
    private func fetch() -> [RadioStation]? {
        let finished = expectation(description: "fetch finished")
        var delivered: [RadioStation]?
        manager.fetch { result in
            delivered = try? result.get()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        return delivered
    }

    private func streamURL(of station: RadioStation) -> URL? { URL(string: station.streamURL) }

    /// Checks by short code as well, which `RadioStation ==` doesn't compare.
    private func assertCurrent(_ station: RadioStation, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(manager.currentStation?.shortCode, station.shortCode, file: file, line: line)
        XCTAssertEqual(RadioPlayer.shared.radioURL, streamURL(of: station), file: file, line: line)
    }

    // MARK: The list changes

    func testNewListIsAppliedInOrderAndObserversAreTold() {
        deliver([one, two])
        observer.reset()

        let delivered = deliver([three, one])

        XCTAssertEqual(manager.stations.map(\.shortCode), ["three", "one"])
        XCTAssertEqual(delivered?.map(\.shortCode), ["three", "one"])
        XCTAssertEqual(observer.updatedLists.map { $0.map(\.shortCode) }, [["three", "one"]])
    }

    func testSameListAgainDoesNotNotifyObservers() {
        deliver([one, two])
        observer.reset()

        deliver([one, two])

        XCTAssertTrue(observer.updatedLists.isEmpty)
    }

    func testCurrentStationVanishingResetsStationAndStream() {
        deliver([one, two])
        manager.set(station: two)
        observer.reset()

        deliver([one, three])

        XCTAssertNil(manager.currentStation)
        XCTAssertNil(RadioPlayer.shared.radioURL)
        XCTAssertEqual(RadioPlayer.shared.state, .idle)
        XCTAssertEqual(observer.changedStations, [nil], "Observers hear about the reset once")
        XCTAssertEqual(StationMetadataManager.shared.connectionState, .disconnected)
    }

    func testCurrentStationStayingInTheNewListIsLeftAlone() {
        deliver([one, two])
        manager.set(station: two)
        let player = RadioPlayer.shared.radioURL
        observer.reset()

        deliver([three, two])

        assertCurrent(two)
        XCTAssertEqual(RadioPlayer.shared.radioURL, player)
        XCTAssertTrue(observer.changedStations.isEmpty, "No station change, so no reconnect")
    }

    func testChangedStreamURLCountsAsTheCurrentStationVanishing() {
        var moved = two
        moved.streamURL = "https://two.invalid/new-stream"
        deliver([one, two])
        manager.set(station: two)

        deliver([one, moved])

        XCTAssertNil(manager.currentStation)
        XCTAssertNil(RadioPlayer.shared.radioURL)
    }

    func testChangedDescriptionStopsTheCurrentStation() {
        // Current behaviour: `==` compares the description, so editing it makes a refresh
        // treat the same station, with the same stream, as gone from the list.
        let edited = Self.station("two", desc: "edited description")
        deliver([one, two])
        manager.set(station: two)

        deliver([one, edited])

        XCTAssertEqual(manager.stations.map(\.desc), ["one desc", "edited description"])
        XCTAssertNil(manager.currentStation)
        XCTAssertNil(RadioPlayer.shared.radioURL)
    }

    func testListDifferingOnlyInFieldsEqualityIgnoresIsNotApplied() {
        // Current behaviour: `==` ignores these three fields, so the manager keeps its old
        // list even though the fetch's completion receives the new one.
        let edited = Self.station("two", serverName: "moved.invalid", shortCode: "moved",
                                  defaultDJ: "New DJ")
        deliver([one, two])
        manager.set(station: two)
        observer.reset()

        let delivered = deliver([one, edited])

        XCTAssertEqual(delivered?.map(\.shortCode), ["one", "moved"])
        XCTAssertEqual(delivered?.map(\.serverName), ["one.invalid", "moved.invalid"])
        XCTAssertEqual(delivered?.map(\.defaultDJ), ["DJ", "New DJ"])
        XCTAssertEqual(manager.stations.map(\.shortCode), ["one", "two"])
        XCTAssertEqual(manager.stations.map(\.serverName), ["one.invalid", "two.invalid"])
        XCTAssertEqual(manager.stations.map(\.defaultDJ), ["DJ", "DJ"])
        XCTAssertTrue(observer.updatedLists.isEmpty)
        assertCurrent(two)
    }

    func testFailedFetchKeepsTheListAndTheCurrentStation() {
        deliver([one, two])
        manager.set(station: two)
        observer.reset()
        StubURLProtocol.reset()

        let delivered = fetch()

        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1, "The canned failure was reached")
        XCTAssertEqual(delivered?.map(\.shortCode), ["one", "two"], "ConfigClient's cached list")
        XCTAssertEqual(manager.stations.map(\.shortCode), ["one", "two"])
        XCTAssertTrue(observer.updatedLists.isEmpty)
        assertCurrent(two)
    }

    // MARK: Next and previous

    func testNextMovesForwardAndWrapsToTheFirstStation() {
        deliver([one, two, three])
        manager.set(station: one)

        manager.setNext()
        assertCurrent(two)

        manager.setNext()
        assertCurrent(three)

        manager.setNext()
        assertCurrent(one)
    }

    func testPreviousMovesBackAndWrapsToTheLastStation() {
        deliver([one, two, three])
        manager.set(station: one)

        manager.setPrevious()
        assertCurrent(three)

        manager.setPrevious()
        assertCurrent(two)

        manager.setPrevious()
        assertCurrent(one)
    }

    func testNextAndPreviousStayPutOnASingleStationList() {
        deliver([one])
        manager.set(station: one)

        manager.setNext()
        assertCurrent(one)

        manager.setPrevious()
        assertCurrent(one)
    }

    func testNextAndPreviousDoNothingWithNoCurrentStation() {
        deliver([one, two])

        manager.setNext()
        XCTAssertNil(manager.currentStation)

        manager.setPrevious()
        XCTAssertNil(manager.currentStation)
        XCTAssertNil(RadioPlayer.shared.radioURL)
    }
}

private final class StationsObserverSpy: StationsManagerObserver {
    private(set) var updatedLists: [[RadioStation]] = []
    private(set) var changedStations: [RadioStation?] = []

    func reset() {
        updatedLists = []
        changedStations = []
    }

    func stationsManager(_ manager: StationsManager, stationsDidUpdate stations: [RadioStation]) {
        updatedLists.append(stations)
    }

    func stationsManager(_ manager: StationsManager, stationDidChange station: RadioStation?) {
        changedStations.append(station)
    }
}
