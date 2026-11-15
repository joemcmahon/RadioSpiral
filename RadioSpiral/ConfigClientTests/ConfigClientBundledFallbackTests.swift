//
//  ConfigClientBundledFallbackTests.swift
//  ConfigClientTests
//
//  Task-27: when the production config can't be had at all (GitHub down, every source failing)
//  and nothing is cached, ConfigClient shows the stations bundled in the app instead of failing.
//
//  It applies to any config (Production, Preview or Test), and the app says so while it is in use
//  (the "FORCED FALLBACK" banner), so a tester can tell a fallback from a working config.
//
//  Replies are canned (StubURLProtocol), so nothing reaches the network. Most tests inject the
//  bundled list; one reads the real resource.
//

import XCTest
@testable import RadioSpiral

final class ConfigClientBundledFallbackTests: XCTestCase {

    private let otherConfigURL = "https://config.invalid/config.json"

    private func station(_ code: String) -> StationConfig {
        StationConfig(name: "\(code) name", streamURL: "https://\(code).invalid/stream",
                      imageURL: "https://\(code).invalid/art.png", desc: "\(code) desc",
                      longDesc: "\(code) long", serverName: "\(code).invalid",
                      shortCode: code, defaultDJ: "DJ")
    }

    private func makeClient(configURL: String, bundled: [StationConfig]) -> ConfigClient {
        let client = ConfigClient(configURL: configURL)
        client.session = StubURLProtocol.makeSession()
        client.bundledFallback = { bundled }
        return client
    }

    private func fetch(_ client: ConfigClient) -> Result<[StationConfig], Error> {
        var result: Result<[StationConfig], Error>?
        let done = expectation(description: "fetched")
        client.fetchStations { result = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return result!
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: The fallback is used

    func testProductionConfigUnreachableShowsTheBundledStations() throws {
        let client = makeClient(configURL: ConfigClient.productionConfigURL, bundled: [station("a"), station("b")])
        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .failure(.cannotFindHost))

        let stations = try fetch(client).get()

        XCTAssertEqual(stations.map(\.shortCode), ["a", "b"])
    }

    func testEverySourceFailingShowsTheBundledStations() throws {
        let client = makeClient(configURL: ConfigClient.productionConfigURL, bundled: [station("a")])
        let body = try JSONSerialization.data(withJSONObject: [
            "configs": [["format": "azuracast", "server": "down.invalid"]]
        ])
        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .http(status: 200, body: body))
        StubURLProtocol.reply(to: "https://down.invalid/api/stations", with: .http(status: 500))

        let stations = try fetch(client).get()

        XCTAssertEqual(stations.map(\.shortCode), ["a"])
    }

    func testTheBundledStationsAreAvailableToMetadataFallbackAfterwards() throws {
        let client = makeClient(configURL: ConfigClient.productionConfigURL, bundled: [station("a")])
        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .failure(.timedOut))

        _ = try fetch(client).get()

        XCTAssertEqual(client.getStationInfo(byShortCode: "a")?.name, "a name")
    }

    // MARK: The fallback is not used

    func testStationsAlreadyHeldAreUsedInsteadOfTheBundledOnes() throws {
        let client = makeClient(configURL: ConfigClient.productionConfigURL, bundled: [station("bundled")])
        let live = try JSONSerialization.data(withJSONObject: [
            "configs": [["format": "static", "stations": [[
                "name": "live name", "streamURL": "https://live.invalid/s", "imageURL": "https://live.invalid/a.png",
                "desc": "d", "longDesc": "l", "serverName": "live.invalid", "shortCode": "live", "defaultDJ": "DJ"]]]]
        ])
        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .http(status: 200, body: live))
        _ = try fetch(client).get()

        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .failure(.timedOut))
        let stations = try fetch(client).get()

        XCTAssertEqual(stations.map(\.shortCode), ["live"])
    }

    func testAnotherServersConfigFailingFallsBackToo() throws {
        let client = makeClient(configURL: otherConfigURL, bundled: [station("a")])
        StubURLProtocol.reply(to: otherConfigURL, with: .failure(.cannotFindHost))

        let stations = try fetch(client).get()

        XCTAssertEqual(stations.map(\.shortCode), ["a"])
    }

    func testWithNoBundledStationsAFailureIsStillAFailure() {
        let client = makeClient(configURL: ConfigClient.productionConfigURL, bundled: [])
        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .failure(.cannotFindHost))

        switch fetch(client) {
        case .success: XCTFail("There was nothing to fall back to")
        case .failure: break
        }
    }

    // MARK: Saying so

    func testItSaysWhenTheBundledStationsAreInUse() throws {
        let client = makeClient(configURL: ConfigClient.productionConfigURL, bundled: [station("a")])
        XCTAssertFalse(client.isUsingBundledFallback)
        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .failure(.timedOut))

        _ = try fetch(client).get()

        XCTAssertTrue(client.isUsingBundledFallback)
    }

    func testALiveConfigAfterwardsClearsIt() throws {
        let client = makeClient(configURL: ConfigClient.productionConfigURL, bundled: [station("bundled")])
        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .failure(.timedOut))
        _ = try fetch(client).get()
        let live = try JSONSerialization.data(withJSONObject: [
            "configs": [["format": "static", "stations": [[
                "name": "live name", "streamURL": "https://live.invalid/s", "imageURL": "https://live.invalid/a.png",
                "desc": "d", "longDesc": "l", "serverName": "live.invalid", "shortCode": "live", "defaultDJ": "DJ"]]]]
        ])
        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .http(status: 200, body: live))

        _ = try fetch(client).get()

        XCTAssertFalse(client.isUsingBundledFallback)
    }

    func testChangingServerClearsIt() throws {
        let client = makeClient(configURL: ConfigClient.productionConfigURL, bundled: [station("a")])
        StubURLProtocol.reply(to: ConfigClient.productionConfigURL, with: .failure(.timedOut))
        _ = try fetch(client).get()

        client.configURL = otherConfigURL

        XCTAssertFalse(client.isUsingBundledFallback, "The bundled list belongs to the old server's failure")
    }

    // MARK: The bundled resources, and the launch date

    private let launch = ConfigClient.launchDate

    func testBeforeTheLaunchTheBundledListIsRadioSpiralAlone() {
        let stations = ConfigClient.bundledStations(in: .main, now: launch.addingTimeInterval(-1))  // .main: the app the tests run in

        XCTAssertEqual(stations.map(\.shortCode), ["radiospiral"])
        assertUsable(stations)
    }

    func testFromTheLaunchTheBundledListIsTheFourLaunchStations() {
        let stations = ConfigClient.bundledStations(in: .main, now: launch)

        XCTAssertEqual(stations.map(\.shortCode), ["radiospiral", "inner_sanctum", "outer_limits", "pulse"])
        assertUsable(stations)
    }

    func testLongAfterTheLaunchItIsStillTheFourStations() {
        let stations = ConfigClient.bundledStations(in: .main, now: launch.addingTimeInterval(365 * 24 * 3600))

        XCTAssertEqual(stations.count, 4)
    }

    func testTheLaunchIsThe19thOfDecember2026At1200UTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: launch)

        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 12, 19, 12, 0])
    }

    func testTheDefaultBundledListFollowsTheClock() {
        // With the real clock, whichever side of the launch it is, there are stations to show.
        let client = ConfigClient()
        XCTAssertFalse(client.bundledFallback().isEmpty)
    }

    /// Streams and art come from spiral.radio, not GitHub, so the fallback still works when GitHub is what's down.
    private func assertUsable(_ stations: [StationConfig], file: StaticString = #filePath, line: UInt = #line) {
        for station in stations {
            XCTAssertTrue(station.streamURL.hasPrefix("https://"), "\(station.shortCode): \(station.streamURL)", file: file, line: line)
            XCTAssertTrue(station.imageURL.hasPrefix("https://spiral.radio/"), "\(station.shortCode): \(station.imageURL)", file: file, line: line)
            XCTAssertFalse(station.name.isEmpty, file: file, line: line)
        }
    }
}
