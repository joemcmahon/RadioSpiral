//
//  ConfigClientTests.swift
//  ConfigClientTests
//
//  Created by Joe McMahon on 11/12/25.
//  Copyright © 2025 matthewfecher.com. All rights reserved.
//

import XCTest
@testable import RadioSpiral

class ConfigClientTests: XCTestCase {

    // MARK: - Early-Stop and Fallback Chain Tests

    func testAzuracastStationParsing() {
        guard let testConfigPath = Bundle(for: ConfigClientTests.self).path(forResource: "test-config-with-fallback", ofType: "json") else {
            XCTFail("Could not find test config file")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: testConfigPath))
            let config = try JSONDecoder().decode(ConfigWrapper.self, from: data)

            if let staticConfig = config.configs.first(where: { $0.format == .static }) {
                let stations = staticConfig.safeStations
                XCTAssertEqual(stations.count, 1, "Should have one station in static config")

                if let station = stations.first {
                    // Verify all required fields are present
                    XCTAssertEqual(station.name, "Test Station", "Station name should match")
                    XCTAssertEqual(station.shortCode, "test_station", "Short code should match")
                    XCTAssertFalse(station.desc.isEmpty, "Description should not be empty")
                    XCTAssertFalse(station.longDesc.isEmpty, "Long description should not be empty")
                    XCTAssertEqual(station.serverName, "test.local", "Server name should match")
                    XCTAssertFalse(station.streamURL.isEmpty, "Stream URL should not be empty")
                }
            } else {
                XCTFail("Could not find static config source")
            }
        } catch {
            XCTFail("Failed to decode config: \(error)")
        }
    }

    func testEarlyStopWithMultipleStaticSources() {
        guard let testConfigPath = Bundle(for: ConfigClientTests.self).path(forResource: "test-config-with-real-server", ofType: "json") else {
            XCTFail("Could not find test config with real server")
            return
        }

        let testURL = URL(fileURLWithPath: testConfigPath).absoluteString
        let client = ConfigClient(configURL: testURL)
        let expectation = self.expectation(description: "Early stop with multiple static sources")

        client.fetchStations { result in
            switch result {
            case .success(let stations):
                // Should have exactly 2 stations from first static config
                // (verifying we stopped at first success and didn't continue to second static config)
                XCTAssertEqual(stations.count, 2, "Should get exactly 2 stations from first config, not more from fallback")

                // Verify we got the first station
                if let firstStation = stations.first(where: { $0.shortCode == "test_static_1" }) {
                    XCTAssertEqual(firstStation.name, "Test Station - Direct Static", "Should have first station")
                } else {
                    XCTFail("Should have test_static_1 station")
                }

                // Verify we do NOT have the fallback station
                let hasFallback = stations.contains { $0.shortCode == "fallback_station" }
                XCTAssertFalse(hasFallback, "Should not have fallback_station (should have early-stopped)")

                expectation.fulfill()
            case .failure(let error):
                XCTFail("Failed to fetch stations: \(error)")
            }
        }

        waitForExpectations(timeout: 15.0)
    }

    // MARK: - CreditsClient Tests

    func testCreditsClientFetchFromLocalFile() {
        let testBundle = Bundle(for: ConfigClientTests.self)
        guard let path = testBundle.path(forResource: "test-credits", ofType: "json") else {
            XCTFail("test-credits.json not found in test bundle")
            return
        }
        let url = URL(fileURLWithPath: path).absoluteString
        let client = CreditsClient(creditsURL: url)
        let expectation = self.expectation(description: "Fetch credits from file")

        client.fetchCredits { credits in
            XCTAssertEqual(credits.count, 2)
            XCTAssertEqual(credits[0].role, "Test Role 1")
            XCTAssertEqual(credits[0].name, "Test Person 1")
            XCTAssertEqual(credits[1].role, "Test Role 2")
            XCTAssertEqual(credits[1].name, "Test Person 2")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 15.0)
    }

    func testCreditsClientFallbackOnInvalidURL() {
        let client = CreditsClient(creditsURL: "file:///nonexistent/credits.json")
        let expectation = self.expectation(description: "Fallback credits")

        client.fetchCredits { credits in
            XCTAssertEqual(credits, fallbackCredits)
            XCTAssertFalse(credits.isEmpty)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 15.0)
    }

    func testCreditPairCodable() {
        let json = """
        {"role": "DJ", "name": "Spud"}
        """.data(using: .utf8)!

        let decoded = try! JSONDecoder().decode(CreditPair.self, from: json)
        XCTAssertEqual(decoded.role, "DJ")
        XCTAssertEqual(decoded.name, "Spud")

        let encoded = try! JSONEncoder().encode(decoded)
        let reDecoded = try! JSONDecoder().decode(CreditPair.self, from: encoded)
        XCTAssertEqual(reDecoded, decoded)
    }

    // MARK: - InterruptionPreference Tests

    func testDefaultPreferenceIsAutomatic() {
        InterruptionPreference.reset()
        XCTAssertEqual(InterruptionPreference.current, .automatic)
    }

    func testSavingPreferenceRoundTrips() {
        for preference in [InterruptionPreference.pause, .lowerVolume, .automatic] {
            InterruptionPreference.current = preference
            XCTAssertEqual(InterruptionPreference.current, preference)
        }
        InterruptionPreference.reset()
    }

    func testResetRestoresDefault() {
        InterruptionPreference.current = .pause
        InterruptionPreference.reset()
        XCTAssertEqual(InterruptionPreference.current, .automatic)
    }

    func testOldMenuChoicesCarryOver() {
        // Values saved by the old audio mode menu and banner, under the same key.
        let carried: [String: InterruptionPreference] = [
            "ask": .automatic,               // Auto-select
            "alwaysStability": .pause,       // Pitch lock
            "neverStability": .lowerVolume,  // Continuous audio lock
        ]
        for (raw, expected) in carried {
            UserDefaults.standard.set(raw, forKey: "audioStabilityPreference")
            XCTAssertEqual(InterruptionPreference.current, expected, raw)
        }
        InterruptionPreference.reset()
    }

    func testUnknownStoredValueFallsBackToAutomatic() {
        UserDefaults.standard.set("bogus", forKey: InterruptionPreference.key)
        XCTAssertEqual(InterruptionPreference.current, .automatic)
        InterruptionPreference.reset()
    }

    func testModeForPreference() {
        XCTAssertEqual(InterruptionPreference.automatic.mode(hearingAidsConnected: true), .pause)
        XCTAssertEqual(InterruptionPreference.automatic.mode(hearingAidsConnected: false), .lowerVolume)
        XCTAssertEqual(InterruptionPreference.pause.mode(hearingAidsConnected: false), .pause)
        XCTAssertEqual(InterruptionPreference.pause.mode(hearingAidsConnected: true), .pause)
        XCTAssertEqual(InterruptionPreference.lowerVolume.mode(hearingAidsConnected: true), .lowerVolume)
        XCTAssertEqual(InterruptionPreference.lowerVolume.mode(hearingAidsConnected: false), .lowerVolume)
    }

    func testSettingsBundleMatchesPreference() throws {
        // The Settings app page must offer exactly the preference's values, on its key.
        let bundle = Bundle(for: RadioPlayer.self)
        let url = try XCTUnwrap(bundle.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle"))
        let root = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        let specifiers = try XCTUnwrap(root["PreferenceSpecifiers"] as? [[String: Any]])
        let item = try XCTUnwrap(specifiers.first { $0["Key"] as? String == InterruptionPreference.key })
        XCTAssertEqual(item["Values"] as? [String], ["ask", "alwaysStability", "neverStability"])
        XCTAssertEqual(item["DefaultValue"] as? String, InterruptionPreference.automatic.rawValue)
    }

    // MARK: - StationServer Tests

    func testAppStoreAlwaysUsesProduction() {
        XCTAssertEqual(StationServer.effective(selected: .test, environment: .appStore), .production)
        XCTAssertEqual(StationServer.effective(selected: .production, environment: .appStore), .production)
    }

    func testUnresolvedEnvironmentUsesProduction() {
        XCTAssertEqual(StationServer.effective(selected: .test, environment: nil), .production)
    }

    func testTestersGetTheirChoice() {
        for environment in [InstallEnvironment.testFlight, .xcode] {
            XCTAssertEqual(StationServer.effective(selected: .test, environment: environment), .test)
            XCTAssertEqual(StationServer.effective(selected: .production, environment: environment), .production)
        }
    }

    func testOnlyTestersMaySwitch() {
        XCTAssertFalse(InstallEnvironment.appStore.allowsTestServer)
        XCTAssertTrue(InstallEnvironment.testFlight.allowsTestServer)
        XCTAssertTrue(InstallEnvironment.xcode.allowsTestServer)
    }

    func testSelectedDefaultsToProduction() {
        UserDefaults.standard.removeObject(forKey: StationServer.key)
        XCTAssertEqual(StationServer.selected, .production)
        UserDefaults.standard.set("bogus", forKey: StationServer.key)
        XCTAssertEqual(StationServer.selected, .production)
        StationServer.selected = .test
        XCTAssertEqual(StationServer.selected, .test)
        UserDefaults.standard.removeObject(forKey: StationServer.key)
    }

    func testServerConfigURLs() {
        XCTAssertTrue(StationServer.production.configURL.hasSuffix("/config.json"))
        XCTAssertTrue(StationServer.test.configURL.hasSuffix("/config-test.json"))
        // The production URL must stay the one ConfigClient has always used.
        XCTAssertEqual(StationServer.production.configURL,
                       "https://raw.githubusercontent.com/joemcmahon/radiospiral-config/master/config.json")
    }
}

// MARK: - Config and credits from local files

/// Pins how ConfigClient and CreditsClient load from local files: exact values,
/// the failure paths, and what the caches do. Every test builds its own temp file
/// and no source names a server, so none of these touch the network.
///
/// Sources that fail here are the ones that can fail offline: an AzuraCast source
/// with no server, and a static source with no usable stations. Stubbed HTTP comes
/// with Phase 9.
final class ConfigOfflineTests: XCTestCase {

    private let alpha = ConfigOfflineTests.station("alpha")
    private let beta = ConfigOfflineTests.station("beta")

    private static let fieldNames = ["name", "streamURL", "imageURL", "desc", "longDesc",
                                     "serverName", "shortCode", "defaultDJ"]

    // MARK: Helpers

    /// Every value is distinct, so a value landing in the wrong field fails the test.
    private static func station(_ tag: String) -> [String: String] {
        ["name": "\(tag) name",
         "streamURL": "https://\(tag).test/stream",
         "imageURL": "https://\(tag).test/image.png",
         "desc": "\(tag) desc",
         "longDesc": "\(tag) long desc",
         "serverName": "\(tag).server",
         "shortCode": "\(tag)_code",
         "defaultDJ": "\(tag) DJ"]
    }

    private func fields(_ station: StationConfig) -> [String: String] {
        ["name": station.name,
         "streamURL": station.streamURL,
         "imageURL": station.imageURL,
         "desc": station.desc,
         "longDesc": station.longDesc,
         "serverName": station.serverName,
         "shortCode": station.shortCode,
         "defaultDJ": station.defaultDJ]
    }

    private func staticSource(_ stations: [[String: String]]) -> [String: Any] {
        ["format": "static", "stations": stations]
    }

    /// An AzuraCast source that fails before any request is made.
    private let azuracastWithNoServer: [String: Any] = ["format": "azuracast"]

    private func configData(_ sources: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["configs": sources])
    }

    private func tempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("config-offline-\(UUID().uuidString).json")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeClient(_ sources: [[String: Any]]) throws -> (client: ConfigClient, file: URL) {
        let file = try tempFile(try configData(sources))
        return (ConfigClient(configURL: file.absoluteString), file)
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

    private func assertFetch(_ client: ConfigClient,
                             returns expected: [[String: String]],
                             _ message: String = "",
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        switch fetch(client) {
        case .success(let stations):
            XCTAssertEqual(stations.map(fields), expected, message, file: file, line: line)
        case .failure(let error):
            XCTFail("Fetch failed: \(error). \(message)", file: file, line: line)
        case nil:
            XCTFail("Fetch never finished. \(message)", file: file, line: line)
        }
    }

    /// Every failure reaches the caller as dataNotFound, whatever the cause.
    private func assertFetchFails(_ client: ConfigClient,
                                  _ message: String = "",
                                  file: StaticString = #filePath,
                                  line: UInt = #line) {
        switch fetch(client) {
        case .failure(let error):
            XCTAssertEqual(error as? ConfigClientError, .dataNotFound, message, file: file, line: line)
        case .success(let stations):
            XCTFail("Expected failure, got \(stations.count) stations. \(message)", file: file, line: line)
        case nil:
            XCTFail("Fetch never finished. \(message)", file: file, line: line)
        }
    }

    // MARK: Config URL

    func testDefaultConfigURLIsTheProductionConfig() {
        XCTAssertEqual(ConfigClient().configURL,
                       "https://raw.githubusercontent.com/joemcmahon/radiospiral-config/master/config.json")
    }

    func testCustomConfigURLIsKept() {
        XCTAssertEqual(ConfigClient(configURL: "file:///test/path/config.json").configURL,
                       "file:///test/path/config.json")
    }

    // MARK: Loading stations

    func testFetchReturnsEveryFieldOfEveryStationInOrder() throws {
        let (client, _) = try makeClient([staticSource([alpha, beta])])
        assertFetch(client, returns: [alpha, beta])
    }

    func testLookupFindsOnlyLoadedStations() throws {
        let (client, _) = try makeClient([staticSource([alpha, beta])])
        XCTAssertNil(client.getStationInfo(byShortCode: "beta_code"), "Nothing is loaded yet")

        assertFetch(client, returns: [alpha, beta])

        XCTAssertEqual(client.getStationInfo(byShortCode: "beta_code").map(fields), beta)
        XCTAssertNil(client.getStationInfo(byShortCode: "unknown_code"))
    }

    func testConfigDecodesEverySourceExactly() throws {
        let data = try configData([
            ["format": "azuracast", "server": "primary.test", "exclude": ["rstest", "other"]],
            azuracastWithNoServer,
            staticSource([alpha]),
        ])

        let sources = try JSONDecoder().decode(ConfigWrapper.self, from: data).configs

        XCTAssertEqual(sources.map(\.format), [.azuracast, .azuracast, .static])
        XCTAssertEqual(sources[0].safeServer, "primary.test")
        XCTAssertEqual(sources[0].safeExclude, ["rstest", "other"])
        XCTAssertEqual(sources[1].safeServer, "")
        XCTAssertEqual(sources[1].safeExclude, [])
        XCTAssertEqual(sources[0].safeStations.count, 0)
        XCTAssertEqual(sources[2].safeStations.map(fields), [alpha])
    }

    // MARK: Moving past a source that fails

    func testFailedSourcesAreSkippedAndTheFirstGoodOneWins() throws {
        let (client, _) = try makeClient([azuracastWithNoServer,
                                          staticSource([]),
                                          staticSource([alpha]),
                                          staticSource([beta])])
        assertFetch(client, returns: [alpha])
    }

    func testStaticEntryMissingAnyFieldIsDropped() throws {
        for field in Self.fieldNames {
            var incomplete = alpha
            incomplete.removeValue(forKey: field)
            let (client, _) = try makeClient([staticSource([incomplete, beta])])
            assertFetch(client, returns: [beta], "missing \(field)")
        }
    }

    func testSourceWithOnlyIncompleteEntriesCountsAsFailed() throws {
        var incomplete = alpha
        incomplete.removeValue(forKey: "defaultDJ")
        let (client, _) = try makeClient([staticSource([incomplete]), staticSource([beta])])
        assertFetch(client, returns: [beta])
    }

    // MARK: Fetches that fail

    func testMalformedConfigFails() throws {
        let malformed = [
            "not JSON": "this is not json",
            "wrong top-level key": #"{"sources": []}"#,
            "top-level array": "[]",
            "unknown format": #"{"configs": [{"format": "bogus"}]}"#,
            "non-string station value": #"{"configs": [{"format": "static", "stations": [{"name": 5}]}]}"#,
        ]
        for (label, text) in malformed {
            let file = try tempFile(Data(text.utf8))
            assertFetchFails(ConfigClient(configURL: file.absoluteString), label)
        }
    }

    func testMissingConfigFileFails() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("config-offline-absent-\(UUID().uuidString).json")
        assertFetchFails(ConfigClient(configURL: file.absoluteString))
    }

    func testUnusableConfigURLFails() {
        assertFetchFails(ConfigClient(configURL: ""))
    }

    func testEmptyStaticListFails() throws {
        assertFetchFails(try makeClient([staticSource([])]).client, "empty list")
        assertFetchFails(try makeClient([["format": "static"]]).client, "no list at all")
    }

    func testAllSourcesFailingFails() throws {
        var incomplete = alpha
        incomplete.removeValue(forKey: "name")
        let (client, _) = try makeClient([azuracastWithNoServer,
                                          staticSource([]),
                                          staticSource([incomplete])])
        assertFetchFails(client)
        XCTAssertNil(client.getStationInfo(byShortCode: "alpha_code"))
    }

    func testConfigWithNoSourcesFails() throws {
        assertFetchFails(try makeClient([]).client)
    }

    // MARK: The station cache

    func testCachedStationsAreReturnedWhenTheConfigTurnsMalformed() throws {
        let (client, file) = try makeClient([staticSource([alpha, beta])])
        assertFetch(client, returns: [alpha, beta])

        try Data("this is not json".utf8).write(to: file)

        assertFetch(client, returns: [alpha, beta])
        XCTAssertEqual(client.getStationInfo(byShortCode: "alpha_code").map(fields), alpha)
    }

    func testCachedStationsAreReturnedWhenTheConfigDisappears() throws {
        let (client, file) = try makeClient([staticSource([alpha])])
        assertFetch(client, returns: [alpha])

        try FileManager.default.removeItem(at: file)

        assertFetch(client, returns: [alpha])
    }

    func testCachedStationsAreReturnedWhenEverySourceFails() throws {
        let (client, file) = try makeClient([staticSource([alpha])])
        assertFetch(client, returns: [alpha])

        try configData([azuracastWithNoServer, staticSource([])]).write(to: file)

        assertFetch(client, returns: [alpha])
        XCTAssertEqual(client.getStationInfo(byShortCode: "alpha_code").map(fields), alpha)
    }

    func testASuccessfulFetchReplacesTheCache() throws {
        let (client, file) = try makeClient([staticSource([alpha])])
        assertFetch(client, returns: [alpha])

        try configData([staticSource([beta])]).write(to: file)

        assertFetch(client, returns: [beta])
        XCTAssertNil(client.getStationInfo(byShortCode: "alpha_code"))
        XCTAssertEqual(client.getStationInfo(byShortCode: "beta_code").map(fields), beta)
    }

    func testChangingConfigURLDropsCachedStations() throws {
        let (client, file) = try makeClient([staticSource([alpha])])
        assertFetch(client, returns: [alpha])

        client.configURL = file.absoluteString
        XCTAssertNotNil(client.getStationInfo(byShortCode: "alpha_code"), "The same URL keeps the cache")

        client.configURL = "file:///nonexistent.json"
        XCTAssertNil(client.getStationInfo(byShortCode: "alpha_code"))
        assertFetchFails(client, "The dropped cache can't answer a failed fetch either")
    }

    // MARK: The credits cache

    private func credits(_ pairs: [CreditPair]) throws -> Data {
        try JSONEncoder().encode(CreditsWrapper(credits: pairs))
    }

    private func fetchCredits(_ client: CreditsClient) -> [CreditPair]? {
        let done = expectation(description: "fetchCredits finished")
        var outcome: [CreditPair]?
        client.fetchCredits { credits in
            outcome = credits
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return outcome
    }

    func testCreditsAreServedFromTheCacheAfterTheFileChanges() throws {
        let original = [CreditPair(role: "Original role", name: "Original name")]
        let file = try tempFile(try credits(original))
        let client = CreditsClient(creditsURL: file.absoluteString)
        XCTAssertEqual(client.credits, [], "Nothing is cached before the first fetch")

        XCTAssertEqual(fetchCredits(client), original)

        try credits([CreditPair(role: "New role", name: "New name")]).write(to: file)

        XCTAssertEqual(fetchCredits(client), original)
        XCTAssertEqual(client.credits, original)
    }
}
