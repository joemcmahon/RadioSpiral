//
//  ParseMalformedMessageTests.swift
//  ConfigClientTests
//
//  A message the parser can't fully read must not crash the app. It's ignored, the
//  same as a message type the parser doesn't recognize, so the current metadata stays.
//

import XCTest
@testable import RadioSpiral

final class ParseMalformedMessageTests: XCTestCase {

    private let shortCode = ConnectMessageFixture.shortCode

    private func parse(_ message: [String: Any]) throws -> ACStreamStatus {
        let data = try JSONSerialization.data(withJSONObject: message)
        return try ParseWebSocketData(data: data, defaultDJ: nil).parse(shortCode: shortCode)
    }

    private func parseConnect(editingNP edit: (inout [String: Any]) -> Void) throws -> ACStreamStatus {
        let data = try ConnectMessageFixture.data(editingNP: edit)
        return try ParseWebSocketData(data: data, defaultDJ: nil).parse(shortCode: shortCode)
    }

    private func parseChannel(editingNP edit: (inout [String: Any]) -> Void) throws -> ACStreamStatus {
        var np: [String: Any] = [:]
        _ = try ConnectMessageFixture.data { fixtureNP in
            edit(&fixtureNP)
            np = fixtureNP
        }
        return try parse(["channel": "station:\(shortCode)", "pub": ["data": ["np": np]]])
    }

    /// A connect message carrying the given subscription contents.
    private func connectMessage(ping: Any = 25, subscription: [String: Any]) -> [String: Any] {
        ["connect": ["ping": ping, "subs": ["station:\(shortCode)": subscription]]]
    }

    private func assertIgnored(_ status: ACStreamStatus, as recordType: ACRecordType,
                               _ context: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(status.changed, context, file: file, line: line)
        XCTAssertEqual(status.recordType, recordType, context, file: file, line: line)
        XCTAssertEqual(status.track, "", context, file: file, line: line)
        XCTAssertEqual(status.artist, "", context, file: file, line: line)
        XCTAssertEqual(status.album, "", context, file: file, line: line)
        XCTAssertEqual(status.dj, "", context, file: file, line: line)
        XCTAssertEqual(status.duration, 0, context, file: file, line: line)
        XCTAssertNil(status.artwork, context, file: file, line: line)
    }

    /// Runs one edit down both the connect and channel paths.
    private func assertBothPathsIgnore(_ context: String,
                                       file: StaticString = #filePath, line: UInt = #line,
                                       editingNP edit: (inout [String: Any]) -> Void) throws {
        assertIgnored(try parseConnect(editingNP: edit), as: .connect, "connect: \(context)", file: file, line: line)
        assertIgnored(try parseChannel(editingNP: edit), as: .channel, "channel: \(context)", file: file, line: line)
    }

    private func edit(_ np: inout [String: Any], nowPlaying key: String, to value: Any?) {
        var nowPlaying = np["now_playing"] as? [String: Any] ?? [:]
        nowPlaying[key] = value
        np["now_playing"] = nowPlaying
    }

    private func edit(_ np: inout [String: Any], song key: String, to value: Any?) {
        var nowPlaying = np["now_playing"] as? [String: Any] ?? [:]
        var song = nowPlaying["song"] as? [String: Any] ?? [:]
        song[key] = value
        nowPlaying["song"] = song
        np["now_playing"] = nowPlaying
    }

    // MARK: - Fields inside now_playing, on both paths

    func testUnreadableNowPlayingIsIgnored() throws {
        try assertBothPathsIgnore("missing") { $0["now_playing"] = nil }
        try assertBothPathsIgnore("null") { $0["now_playing"] = NSNull() }
        try assertBothPathsIgnore("wrong type") { $0["now_playing"] = "not an object" }
    }

    func testUnreadableDurationIsIgnored() throws {
        try assertBothPathsIgnore("missing") { edit(&$0, nowPlaying: "duration", to: nil) }
        try assertBothPathsIgnore("null") { edit(&$0, nowPlaying: "duration", to: NSNull()) }
        try assertBothPathsIgnore("wrong type") { edit(&$0, nowPlaying: "duration", to: "long") }
    }

    func testUnreadableSongIsIgnored() throws {
        try assertBothPathsIgnore("missing") { edit(&$0, nowPlaying: "song", to: nil) }
        try assertBothPathsIgnore("null") { edit(&$0, nowPlaying: "song", to: NSNull()) }
        try assertBothPathsIgnore("wrong type") { edit(&$0, nowPlaying: "song", to: 5) }
    }

    func testUnreadableTitleIsIgnored() throws { try assertUnreadableSongFieldIsIgnored("title") }
    func testUnreadableArtistIsIgnored() throws { try assertUnreadableSongFieldIsIgnored("artist") }
    func testUnreadableAlbumIsIgnored() throws { try assertUnreadableSongFieldIsIgnored("album") }
    func testUnreadableArtIsIgnored() throws { try assertUnreadableSongFieldIsIgnored("art") }

    private func assertUnreadableSongFieldIsIgnored(_ key: String,
                                                    file: StaticString = #filePath, line: UInt = #line) throws {
        try assertBothPathsIgnore("\(key) missing", file: file, line: line) { edit(&$0, song: key, to: nil) }
        try assertBothPathsIgnore("\(key) null", file: file, line: line) { edit(&$0, song: key, to: NSNull()) }
        try assertBothPathsIgnore("\(key) wrong type", file: file, line: line) { edit(&$0, song: key, to: 5) }
    }

    /// Empty strings are real values: AzuraCast sends them, and the album is often empty.
    func testEmptySongFieldsAreStillAChange() throws {
        let status = try parseChannel { edit(&$0, song: "album", to: "") }
        XCTAssertTrue(status.changed)
        XCTAssertEqual(status.album, "")
        XCTAssertFalse(status.track.isEmpty)
    }

    // MARK: - The channel envelope

    func testChannelWithAnUnreadableEnvelopeIsIgnored() throws {
        let channel = "station:\(shortCode)"
        let messages: [(String, [String: Any])] = [
            ("no pub", ["channel": channel]),
            ("pub null", ["channel": channel, "pub": NSNull()]),
            ("pub wrong type", ["channel": channel, "pub": 5]),
            ("no data", ["channel": channel, "pub": [:] as [String: Any]]),
            ("data wrong type", ["channel": channel, "pub": ["data": 5]]),
            ("no np", ["channel": channel, "pub": ["data": [:] as [String: Any]]]),
            ("np wrong type", ["channel": channel, "pub": ["data": ["np": 5]]]),
        ]
        for (context, message) in messages {
            assertIgnored(try parse(message), as: .channel, context)
        }
    }

    // MARK: - The connect envelope

    func testConnectThatIsNotAnObjectIsIgnored() throws {
        assertIgnored(try parse(["connect": 5]), as: .connect)
        assertIgnored(try parse(["connect": NSNull()]), as: .connect)
    }

    func testEmptyPublicationsAreIgnored() throws {
        assertIgnored(try parse(connectMessage(subscription: ["publications": [] as [Any]])), as: .connect)
    }

    func testPublicationWithoutNowPlayingDataIsIgnored() throws {
        let publications: [(String, [Any])] = [
            ("not an object", [5]),
            ("no data", [[:] as [String: Any]]),
            ("data wrong type", [["data": 5]]),
            ("no np", [["data": [:] as [String: Any]]]),
            ("np wrong type", [["data": ["np": 5]]]),
        ]
        for (context, publication) in publications {
            assertIgnored(try parse(connectMessage(subscription: ["publications": publication])), as: .connect, context)
        }
    }

    /// The liveness timer needs the ping even when there's no song to show yet.
    func testIgnoredConnectMessageStillCarriesItsPing() throws {
        let status = try parse(connectMessage(ping: 25, subscription: ["publications": [] as [Any]]))
        XCTAssertEqual(status.pingInterval, 25)
    }

    /// The ping isn't metadata, and the client keeps its previous interval without one,
    /// so the song is still worth showing.
    func testUnreadablePingStillGivesTheSong() throws {
        let data = try ConnectMessageFixture.data()
        var message = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var connect = try XCTUnwrap(message["connect"] as? [String: Any])

        for ping in [nil, NSNull(), "soon"] as [Any?] {
            connect["ping"] = ping
            message["connect"] = connect
            let status = try parse(message)
            XCTAssertTrue(status.changed)
            XCTAssertFalse(status.track.isEmpty)
            XCTAssertEqual(status.pingInterval, 0)
        }
    }
}
