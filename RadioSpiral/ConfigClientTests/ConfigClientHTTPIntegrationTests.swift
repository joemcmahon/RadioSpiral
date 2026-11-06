//
//  ConfigClientHTTPIntegrationTests.swift
//  ConfigClientTests
//
//  ConfigClient and CreditsClient over HTTP, with canned responses and no network.
//  The two live smoke tests are in LiveServerSmokeTests at the end of this file.
//

import XCTest
@testable import RadioSpiral

final class ConfigClientHTTPIntegrationTests: XCTestCase {

    private let configURL = "https://config.invalid/config.json"
    private let onePublic = "https://one.invalid/api/stations"
    private let oneAdmin = "https://one.invalid/api/admin/stations"
    private let twoPublic = "https://two.invalid/api/stations"
    private let twoAdmin = "https://two.invalid/api/admin/stations"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: Helpers

    private func makeClient() -> ConfigClient {
        let client = ConfigClient(configURL: configURL)
        client.session = StubURLProtocol.makeSession()
        return client
    }

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func azuracast(_ server: String, exclude: [String] = []) -> [String: Any] {
        ["format": "azuracast", "server": server, "exclude": exclude]
    }

    private func staticSource(_ code: String) -> [String: Any] {
        ["format": "static",
         "stations": [["name": "\(code) name", "streamURL": "https://\(code).invalid/stream",
                       "imageURL": "https://\(code).invalid/art.png", "desc": "\(code) desc",
                       "longDesc": "\(code) long", "serverName": "\(code).invalid",
                       "shortCode": code, "defaultDJ": "\(code) DJ"]]]
    }

    private func serveConfig(_ sources: [[String: Any]]) throws {
        StubURLProtocol.reply(to: configURL, with: .http(status: 200, body: try json(["configs": sources])))
    }

    private func publicStations(_ codes: String...) throws -> StubURLProtocol.Reply {
        let stations: [[String: Any]] = codes.enumerated().map { index, code in
            ["id": index + 1, "name": "\(code) name", "shortcode": code, "description": "\(code) desc",
             "listen_url": "https://\(code).invalid/live", "url": "https://\(code).invalid"]
        }
        return .http(status: 200, body: try json(stations))
    }

    private func adminStations(_ codes: String...) throws -> StubURLProtocol.Reply {
        let stations: [[String: Any]] = codes.map { code in
            ["id": "\(code)-id", "name": "\(code) name", "short_code": code,
             "description": "\(code) desc", "is_enabled": true]
        }
        return .http(status: 200, body: try json(stations))
    }

    private func stationsBody(public isPublic: Bool) throws -> Data {
        let reply = isPublic ? try publicStations("ignored") : try adminStations("ignored")
        guard case .http(_, let body) = reply else { throw URLError(.badServerResponse) }
        return body
    }

    private func fetch(_ client: ConfigClient) -> Result<[StationConfig], Error>? {
        let done = expectation(description: "fetchStations finished")
        var outcome: Result<[StationConfig], Error>?
        client.fetchStations { result in
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return outcome
    }

    private func codes(_ outcome: Result<[StationConfig], Error>?) throws -> [String] {
        let result = try XCTUnwrap(outcome, "fetchStations didn't finish")
        return try result.get().map(\.shortCode)
    }

    // MARK: Source order

    func testFirstSourceThatWorksStopsTheSearch() throws {
        try serveConfig([azuracast("one.invalid"), azuracast("two.invalid"), staticSource("backup")])
        StubURLProtocol.reply(to: onePublic, with: try publicStations("first"))

        let outcome = fetch(makeClient())

        XCTAssertEqual(try codes(outcome), ["first"])
        XCTAssertEqual(StubURLProtocol.requestedURLs, [configURL, onePublic])
    }

    func testAdminAPIIsTriedAfterThePublicOneFailsOnTheSameServer() throws {
        try serveConfig([azuracast("one.invalid"), azuracast("two.invalid")])
        StubURLProtocol.reply(to: onePublic, with: .http(status: 404))
        StubURLProtocol.reply(to: oneAdmin, with: try adminStations("fromadmin"))

        let outcome = fetch(makeClient())

        XCTAssertEqual(try codes(outcome), ["fromadmin"])
        XCTAssertEqual(StubURLProtocol.requestedURLs, [configURL, onePublic, oneAdmin])
    }

    func testNextServerIsTriedOnlyAfterBothAPIsOfTheFirstFail() throws {
        try serveConfig([azuracast("one.invalid"), azuracast("two.invalid")])
        StubURLProtocol.reply(to: onePublic, with: .http(status: 500))
        StubURLProtocol.reply(to: oneAdmin, with: .http(status: 403))
        StubURLProtocol.reply(to: twoPublic, with: try publicStations("second"))

        let outcome = fetch(makeClient())

        XCTAssertEqual(try codes(outcome), ["second"])
        XCTAssertEqual(StubURLProtocol.requestedURLs, [configURL, onePublic, oneAdmin, twoPublic])
    }

    func testStaticListIsUsedOnceEveryServerHasFailed() throws {
        try serveConfig([azuracast("one.invalid"), azuracast("two.invalid"), staticSource("backup")])
        StubURLProtocol.reply(to: onePublic, with: .failure(.timedOut))
        StubURLProtocol.reply(to: oneAdmin, with: .failure(.timedOut))
        StubURLProtocol.reply(to: twoPublic, with: .failure(.notConnectedToInternet))
        StubURLProtocol.reply(to: twoAdmin, with: .http(status: 200, body: Data("not json".utf8)))

        let outcome = fetch(makeClient())

        XCTAssertEqual(try codes(outcome), ["backup"])
        XCTAssertEqual(StubURLProtocol.requestedURLs, [configURL, onePublic, oneAdmin, twoPublic, twoAdmin])
    }

    func testStaticSourceListedFirstMakesNoServerRequests() throws {
        try serveConfig([staticSource("backup"), azuracast("one.invalid")])

        let outcome = fetch(makeClient())

        XCTAssertEqual(try codes(outcome), ["backup"])
        XCTAssertEqual(StubURLProtocol.requestedURLs, [configURL])
    }

    // MARK: Excluded stations

    func testExcludedStationIsLeftOutOfAPublicAPIResult() throws {
        try serveConfig([azuracast("one.invalid", exclude: ["hidden"])])
        StubURLProtocol.reply(to: onePublic, with: try publicStations("hidden", "shown"))

        XCTAssertEqual(try codes(fetch(makeClient())), ["shown"])
    }

    func testServerWithOnlyExcludedStationsFallsThroughToTheStaticList() throws {
        try serveConfig([azuracast("one.invalid", exclude: ["hidden"]), staticSource("backup")])
        StubURLProtocol.reply(to: onePublic, with: try publicStations("hidden"))
        StubURLProtocol.reply(to: oneAdmin, with: .http(status: 403))

        let outcome = fetch(makeClient())

        XCTAssertEqual(try codes(outcome), ["backup"])
        XCTAssertEqual(StubURLProtocol.requestedURLs, [configURL, onePublic, oneAdmin])
    }

    // MARK: Failures and the cache

    func testEverySourceFailingWithNothingCachedIsAFailure() throws {
        try serveConfig([azuracast("one.invalid")])
        // Usable bodies, so only the status code can make these count as failures.
        StubURLProtocol.reply(to: onePublic, with: .http(status: 500, body: try stationsBody(public: true)))
        StubURLProtocol.reply(to: oneAdmin, with: .http(status: 500, body: try stationsBody(public: false)))

        let outcome = try XCTUnwrap(fetch(makeClient()))

        XCTAssertThrowsError(try outcome.get())
    }

    func testConfigServerErrorWithNothingCachedIsAFailure() throws {
        // A usable body, so only the status code can make this count as a failure.
        let usable = try json(["configs": [staticSource("backup")]])
        StubURLProtocol.reply(to: configURL, with: .http(status: 503, body: usable))

        let outcome = try XCTUnwrap(fetch(makeClient()))

        XCTAssertThrowsError(try outcome.get())
        XCTAssertEqual(StubURLProtocol.requestedURLs, [configURL])
    }

    func testCachedStationsAreReturnedWhenTheConfigServerGoesAway() throws {
        try serveConfig([azuracast("one.invalid")])
        StubURLProtocol.reply(to: onePublic, with: try publicStations("first"))
        let client = makeClient()
        XCTAssertEqual(try codes(fetch(client)), ["first"])

        StubURLProtocol.reply(to: configURL, with: .failure(.notConnectedToInternet))

        XCTAssertEqual(try codes(fetch(client)), ["first"])
    }

    func testCachedStationsAreReturnedWhenEveryServerGoesAway() throws {
        try serveConfig([azuracast("one.invalid")])
        StubURLProtocol.reply(to: onePublic, with: try publicStations("first"))
        let client = makeClient()
        XCTAssertEqual(try codes(fetch(client)), ["first"])

        StubURLProtocol.reply(to: onePublic, with: .http(status: 500))
        StubURLProtocol.reply(to: oneAdmin, with: .http(status: 500))

        XCTAssertEqual(try codes(fetch(client)), ["first"])
    }

    // MARK: Production session settings

    func testProductionSessionsKeepTheirTimeoutAndCachePolicy() {
        let sessions = [ConfigClient().session, ConfigClient.shared.session,
                        CreditsClient().session, CreditsClient.shared.session]

        for session in sessions {
            XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 10)
            XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        }
    }
}

// MARK: - CreditsClient

final class CreditsClientHTTPIntegrationTests: XCTestCase {

    private let creditsURL = "https://config.invalid/credits.json"
    private let served = [CreditPair(role: "Served role", name: "Served name")]

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient() -> CreditsClient {
        let client = CreditsClient(creditsURL: creditsURL)
        client.session = StubURLProtocol.makeSession()
        return client
    }

    private func body() throws -> Data {
        try JSONEncoder().encode(CreditsWrapper(credits: served))
    }

    private func fetch(_ client: CreditsClient) -> [CreditPair]? {
        let done = expectation(description: "fetchCredits finished")
        var outcome: [CreditPair]?
        client.fetchCredits { credits in
            outcome = credits
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return outcome
    }

    func testServedCreditsAreReturnedAndCached() throws {
        StubURLProtocol.reply(to: creditsURL, with: .http(status: 200, body: try body()))
        let client = makeClient()

        XCTAssertEqual(fetch(client), served)

        XCTAssertEqual(client.credits, served)
        XCTAssertEqual(StubURLProtocol.requestedURLs, [creditsURL])
    }

    func testSecondFetchMakesNoRequest() throws {
        StubURLProtocol.reply(to: creditsURL, with: .http(status: 200, body: try body()))
        let client = makeClient()
        _ = fetch(client)

        XCTAssertEqual(fetch(client), served)

        XCTAssertEqual(StubURLProtocol.requestedURLs, [creditsURL])
    }

    func testServerErrorGivesTheFallbackCreditsAndCachesNothing() throws {
        // A usable body, so only the status code can make this count as a failure.
        StubURLProtocol.reply(to: creditsURL, with: .http(status: 500, body: try body()))
        let client = makeClient()

        XCTAssertEqual(fetch(client), fallbackCredits)

        XCTAssertEqual(client.credits, [])
    }

    func testConnectionFailureGivesTheFallbackCredits() {
        StubURLProtocol.reply(to: creditsURL, with: .failure(.notConnectedToInternet))

        XCTAssertEqual(fetch(makeClient()), fallbackCredits)
    }

    func testMalformedResponseGivesTheFallbackCredits() {
        StubURLProtocol.reply(to: creditsURL, with: .http(status: 200, body: Data("not json".utf8)))

        XCTAssertEqual(fetch(makeClient()), fallbackCredits)
    }
}

// MARK: - Live smoke tests

/// SMOKE TESTS: the only tests in this file that use the network, one request each.
/// They catch a real change in a format the app depends on. A connection problem or a server
/// error skips the test instead of failing it, so an outage can't look like a code regression.
final class LiveServerSmokeTests: XCTestCase {

    private func liveData(from address: String) async throws -> Data {
        let url = try XCTUnwrap(URL(string: address))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw XCTSkip("Couldn't reach \(address): \(error.localizedDescription)")
        }

        let status = try XCTUnwrap(response as? HTTPURLResponse).statusCode
        if status >= 500 { throw XCTSkip("\(address) returned HTTP \(status)") }
        XCTAssertEqual(status, 200, "\(address) returned HTTP \(status)")
        return data
    }

    func testSmokeLiveAzuracastStationsStillDecode() async throws {
        let data = try await liveData(from: "https://spiral.radio/api/stations")

        let stations = try JSONDecoder().decode([PublicAzuracastStation].self, from: data)

        XCTAssertFalse(stations.isEmpty)
        for station in stations {
            XCTAssertFalse(station.shortcode.isEmpty)
            XCTAssertNotNil(URL(string: station.listen_url), "listen_url of \(station.shortcode)")
        }
    }

    func testSmokeLiveProductionConfigStillDecodes() async throws {
        let data = try await liveData(from: ConfigClient().configURL)

        let config = try JSONDecoder().decode(ConfigWrapper.self, from: data)

        XCTAssertFalse(config.configs.isEmpty)
    }
}
