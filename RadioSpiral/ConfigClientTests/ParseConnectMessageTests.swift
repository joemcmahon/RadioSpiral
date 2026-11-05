//
//  ParseConnectMessageTests.swift
//  ConfigClientTests
//
//  Pins what ParseWebSocketData does today with an AzuraCast "connect" message.
//  ws-connect-message.json is one real message captured from the test server;
//  variants are made by editing it in code, so each test shows what it changed.
//

import XCTest
@testable import RadioSpiral

/// Loads the captured connect message and rebuilds it with edits to the `np`
/// ("now playing") block, which is where the parser finds nearly everything.
enum ConnectMessageFixture {
    static let shortCode = "rs-one"
    private static let subscription = "station:\(shortCode)"

    static func data(editingNP edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: ParseConnectMessageTests.self)
            .url(forResource: "ws-connect-message", withExtension: "json"))
        var message = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])

        var connect = try XCTUnwrap(message["connect"] as? [String: Any])
        var subs = try XCTUnwrap(connect["subs"] as? [String: Any])
        var sub = try XCTUnwrap(subs[subscription] as? [String: Any])
        var publications = try XCTUnwrap(sub["publications"] as? [[String: Any]])
        var payload = try XCTUnwrap(publications.first?["data"] as? [String: Any])
        var np = try XCTUnwrap(payload["np"] as? [String: Any])

        edit(&np)

        payload["np"] = np
        publications[0]["data"] = payload
        sub["publications"] = publications
        subs[subscription] = sub
        connect["subs"] = subs
        message["connect"] = connect
        return try JSONSerialization.data(withJSONObject: message)
    }
}

final class ParseConnectMessageTests: XCTestCase {

    private func parse(defaultDJ: String? = nil,
                       shortCode: String = ConnectMessageFixture.shortCode,
                       editingNP edit: (inout [String: Any]) -> Void = { _ in }) throws -> ACStreamStatus {
        let data = try ConnectMessageFixture.data(editingNP: edit)
        return try ParseWebSocketData(data: data, defaultDJ: defaultDJ).parse(shortCode: shortCode)
    }

    private func setNowPlaying(_ key: String, to value: Any?, in np: inout [String: Any]) {
        var nowPlaying = np["now_playing"] as? [String: Any] ?? [:]
        nowPlaying[key] = value
        np["now_playing"] = nowPlaying
    }

    private func setBroadcastStart(_ value: Any, in np: inout [String: Any]) {
        var live = np["live"] as? [String: Any] ?? [:]
        live["broadcast_start"] = value
        np["live"] = live
    }

    // MARK: - Field mapping

    func testMapsSongFieldsFromTheRealMessage() throws {
        let status = try parse()

        XCTAssertEqual(status.track, "Lost Tape II")
        XCTAssertEqual(status.artist, "4T Thieves")
        XCTAssertEqual(status.album, "Futures End")
    }

    func testMapsDurationArtworkAndPingFromTheRealMessage() throws {
        let status = try parse()

        XCTAssertEqual(status.duration, 121)
        XCTAssertEqual(status.pingInterval, 25)
        XCTAssertEqual(status.artwork?.absoluteString,
                       "https://spiraltest.harriman4.com/api/station/rs-one/art/f6ca7e2331309e86952a0a94")
    }

    func testMarksTheRecordAsAChangedConnectMessage() throws {
        let status = try parse()

        XCTAssertEqual(status.recordType, .connect)
        XCTAssertTrue(status.changed)
    }

    // MARK: - is_online

    func testOnlineStationIsConnected() throws {
        let status = try parse { $0["is_online"] = true }

        XCTAssertEqual(status.connection, .connected)
    }

    func testOfflineStationIsDisconnected() throws {
        let status = try parse { $0["is_online"] = false }

        XCTAssertEqual(status.connection, .disconnected)
    }

    // MARK: - Broadcast start

    func testBroadcastStartIsReadWhenPresent() throws {
        let status = try parse { self.setBroadcastStart(1_793_850_000, in: &$0) }

        XCTAssertEqual(status.broadcastStart, Date(timeIntervalSince1970: 1_793_850_000))
    }

    func testBroadcastStartIsNilWhenNull() throws {
        // The captured message has a null broadcast_start: nobody is live.
        let status = try parse()

        XCTAssertNil(status.broadcastStart)
    }

    // MARK: - Unknown short code

    func testUnknownShortCodeReportsFailedSubscribe() throws {
        let status = try parse(shortCode: "no-such-station")

        XCTAssertEqual(status.connection, .failedSubscribe)
        XCTAssertEqual(status.recordType, .connect)
    }

    func testUnknownShortCodeLeavesTheMetadataEmptyAndMarkedChanged() throws {
        // Current behaviour, possibly not the right one: the ping is kept, the
        // metadata is blank, and the blank status still says it changed.
        let status = try parse(shortCode: "no-such-station")

        XCTAssertEqual(status.pingInterval, 25)
        XCTAssertEqual(status.track, "")
        XCTAssertEqual(status.artist, "")
        XCTAssertEqual(status.album, "")
        XCTAssertEqual(status.duration, 0)
        XCTAssertNil(status.artwork)
        XCTAssertTrue(status.changed)
    }

    // MARK: - Elapsed time

    func testElapsedIsTimeSincePlayedAt() throws {
        // Elapsed reads the real clock, hence the tolerance.
        let playedAt = Int(Date().timeIntervalSince1970) - 100
        let status = try parse { self.setNowPlaying("played_at", to: playedAt, in: &$0) }

        XCTAssertEqual(status.elapsed, 100, accuracy: 10)
    }

    func testPlayedAtInTheFutureGivesZeroElapsed() throws {
        let playedAt = Int(Date().timeIntervalSince1970) + 1000
        let status = try parse { self.setNowPlaying("played_at", to: playedAt, in: &$0) }

        XCTAssertEqual(status.elapsed, 0)
    }

    func testMissingPlayedAtGivesZeroElapsed() throws {
        let status = try parse { self.setNowPlaying("played_at", to: nil, in: &$0) }

        XCTAssertEqual(status.elapsed, 0)
    }
}
