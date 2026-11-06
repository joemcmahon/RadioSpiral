//
//  ParseChannelMessageTests.swift
//  ConfigClientTests
//
//  Pins what ParseWebSocketData does today with "channel" messages, the updates
//  that follow a connect message, and with messages it doesn't recognize.
//
//  No channel message has been captured from a server. These wrap the real "np"
//  block from ws-connect-message.json in the envelope the parser reads, which is
//  also what lets one song go down both paths for comparison.
//

import XCTest
@testable import RadioSpiral

final class ParseChannelMessageTests: XCTestCase {

    private let shortCode = ConnectMessageFixture.shortCode

    private func channelData(editingNP edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var np: [String: Any] = [:]
        _ = try ConnectMessageFixture.data { fixtureNP in
            edit(&fixtureNP)
            np = fixtureNP
        }
        let message: [String: Any] = [
            "channel": "station:\(shortCode)",
            "pub": ["data": ["np": np]]
        ]
        return try JSONSerialization.data(withJSONObject: message)
    }

    private func parseChannel(defaultDJ: String? = nil,
                              shortCode: String? = nil,
                              editingNP edit: (inout [String: Any]) -> Void = { _ in }) throws -> ACStreamStatus {
        let data = try channelData(editingNP: edit)
        return try ParseWebSocketData(data: data, defaultDJ: defaultDJ)
            .parse(shortCode: shortCode ?? self.shortCode)
    }

    private func parseConnect(defaultDJ: String? = nil,
                              editingNP edit: (inout [String: Any]) -> Void = { _ in }) throws -> ACStreamStatus {
        let data = try ConnectMessageFixture.data(editingNP: edit)
        return try ParseWebSocketData(data: data, defaultDJ: defaultDJ).parse(shortCode: shortCode)
    }

    private func parseRaw(_ text: String) throws -> ACStreamStatus {
        try ParseWebSocketData(data: Data(text.utf8), defaultDJ: nil).parse(shortCode: shortCode)
    }

    private func setNowPlaying(_ key: String, to value: Any?, in np: inout [String: Any]) {
        var nowPlaying = np["now_playing"] as? [String: Any] ?? [:]
        nowPlaying[key] = value
        np["now_playing"] = nowPlaying
    }

    private func setLive(_ key: String, to value: Any, in np: inout [String: Any]) {
        var live = np["live"] as? [String: Any] ?? [:]
        live[key] = value
        np["live"] = live
    }

    private func assertBlankMetadata(_ status: ACStreamStatus,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(status.track, "", file: file, line: line)
        XCTAssertEqual(status.artist, "", file: file, line: line)
        XCTAssertEqual(status.album, "", file: file, line: line)
        XCTAssertEqual(status.dj, "", file: file, line: line)
        XCTAssertEqual(status.duration, 0, file: file, line: line)
        XCTAssertNil(status.artwork, file: file, line: line)
    }

    // MARK: - Field mapping

    func testMapsSongFields() throws {
        let status = try parseChannel()

        XCTAssertEqual(status.track, "Lost Tape II")
        XCTAssertEqual(status.artist, "4T Thieves")
        XCTAssertEqual(status.album, "Futures End")
    }

    func testMapsDurationAndArtwork() throws {
        let status = try parseChannel()

        XCTAssertEqual(status.duration, 121)
        XCTAssertEqual(status.artwork?.absoluteString,
                       "https://spiraltest.harriman4.com/api/station/rs-one/art/f6ca7e2331309e86952a0a94")
    }

    func testMarksTheRecordAsAChangedChannelMessage() throws {
        let status = try parseChannel()

        XCTAssertEqual(status.recordType, .channel)
        XCTAssertTrue(status.changed)
    }

    func testOnlineStationIsConnected() throws {
        let status = try parseChannel { $0["is_online"] = true }

        XCTAssertEqual(status.connection, .connected)
    }

    func testOfflineStationIsDisconnected() throws {
        let status = try parseChannel { $0["is_online"] = false }

        XCTAssertEqual(status.connection, .disconnected)
    }

    func testBroadcastStartIsReadWhenPresent() throws {
        let status = try parseChannel { self.setLive("broadcast_start", to: 1_793_850_000, in: &$0) }

        XCTAssertEqual(status.broadcastStart, Date(timeIntervalSince1970: 1_793_850_000))
    }

    func testElapsedIsTimeSincePlayedAt() throws {
        // Elapsed reads the real clock, hence the tolerance.
        let playedAt = Int(Date().timeIntervalSince1970) - 100
        let status = try parseChannel { self.setNowPlaying("played_at", to: playedAt, in: &$0) }

        XCTAssertEqual(status.elapsed, 100, accuracy: 10)
    }

    func testPlayedAtInTheFutureGivesZeroElapsed() throws {
        let playedAt = Int(Date().timeIntervalSince1970) + 1000
        let status = try parseChannel { self.setNowPlaying("played_at", to: playedAt, in: &$0) }

        XCTAssertEqual(status.elapsed, 0)
    }

    // MARK: - Same song through both paths

    private func assertBothPathsAgree(editingNP edit: (inout [String: Any]) -> Void = { _ in },
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let connect = try parseConnect(defaultDJ: "House DJ", editingNP: edit)
        let channel = try parseChannel(defaultDJ: "House DJ", editingNP: edit)

        XCTAssertEqual(channel.track, connect.track, "track", file: file, line: line)
        XCTAssertEqual(channel.artist, connect.artist, "artist", file: file, line: line)
        XCTAssertEqual(channel.album, connect.album, "album", file: file, line: line)
        XCTAssertEqual(channel.duration, connect.duration, "duration", file: file, line: line)
        XCTAssertEqual(channel.artwork, connect.artwork, "artwork", file: file, line: line)
        XCTAssertEqual(channel.dj, connect.dj, "dj", file: file, line: line)
        XCTAssertEqual(channel.isLiveDJ, connect.isLiveDJ, "isLiveDJ", file: file, line: line)
        XCTAssertEqual(channel.connection, connect.connection, "connection", file: file, line: line)
        XCTAssertEqual(channel.broadcastStart, connect.broadcastStart, "broadcastStart", file: file, line: line)
        XCTAssertEqual(channel.elapsed, connect.elapsed, accuracy: 10, "elapsed", file: file, line: line)
    }

    func testBothPathsAgreeOnTheRealMessage() throws {
        try assertBothPathsAgree()
    }

    func testBothPathsAgreeWithALiveDJ() throws {
        try assertBothPathsAgree { np in
            self.setLive("streamer_name", to: "Some DJ", in: &np)
            self.setLive("broadcast_start", to: 1_793_850_000, in: &np)
        }
    }

    func testBothPathsAgreeWhenOffline() throws {
        try assertBothPathsAgree { $0["is_online"] = false }
    }

    func testBothPathsAgreeWhenPlayedAtIsMissing() throws {
        try assertBothPathsAgree { self.setNowPlaying("played_at", to: nil, in: &$0) }
    }

    // MARK: - Where the two paths differ today

    func testChannelMessageCarriesNoPingInterval() throws {
        // Only connect messages have a ping; channel messages leave the default.
        let status = try parseChannel()

        XCTAssertEqual(status.pingInterval, 0)
    }

    func testChannelMessageIgnoresTheShortCode() throws {
        // Current behaviour: unlike a connect message, a channel message is never
        // checked against the station, so an unknown short code still parses.
        let status = try parseChannel(shortCode: "no-such-station")

        XCTAssertEqual(status.track, "Lost Tape II")
        XCTAssertEqual(status.recordType, .channel)
    }

    // MARK: - Unrecognized messages

    func testEmptyObjectIsMarkedEmptyAndUnchanged() throws {
        let status = try parseRaw("{}")

        XCTAssertEqual(status.recordType, .empty)
        XCTAssertFalse(status.changed)
        assertBlankMetadata(status)
    }

    func testUnknownKeyIsMarkedEmptyAndUnchanged() throws {
        let status = try parseRaw(#"{"push": {"track": "not a song"}}"#)

        XCTAssertEqual(status.recordType, .empty)
        XCTAssertFalse(status.changed)
        assertBlankMetadata(status)
    }

    // MARK: - JSON that can't be used

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try parseRaw("this is not JSON"))
    }

    func testTruncatedJSONThrows() {
        XCTAssertThrowsError(try parseRaw(#"{"channel": "station:rs-one", "pub": {"#))
    }

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try parseRaw(""))
    }

    func testUnquotedKeyThrows() {
        // Pins strict parsing. The key is deliberately not "channel" or "connect":
        // if this ever parsed, those paths' force-casts would crash the test run.
        XCTAssertThrowsError(try parseRaw(#"{push: 1}"#))
    }

    func testJSONThatIsNotAnObjectIsMarkedEmptyAndUnchanged() throws {
        let status = try parseRaw("[1, 2, 3]")

        XCTAssertEqual(status.recordType, .empty)
        XCTAssertFalse(status.changed)
        assertBlankMetadata(status)
    }
}
