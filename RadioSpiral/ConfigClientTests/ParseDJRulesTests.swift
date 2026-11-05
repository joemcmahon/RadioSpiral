//
//  ParseDJRulesTests.swift
//  ConfigClientTests
//
//  Pins how ParseWebSocketData picks the DJ and repairs song metadata today:
//  the default DJ, isLiveDJ, the Cypress Rosewood swap, "track - album"
//  splitting and the garbled DJ name.
//
//  Connect and channel messages reach these rules through separate calls, so
//  every scenario runs through both. The song and DJ values are hand-edited
//  variants of the captured message in ws-connect-message.json.
//

import XCTest
@testable import RadioSpiral

final class ParseDJRulesTests: XCTestCase {

    private enum Streamer {
        case named(String)
        case blank
        case missingKey
        case notAString
        case noLiveBlock
    }

    private let shortCode = ConnectMessageFixture.shortCode

    /// The garbled name as the Mixxx to AzuraCast pipeline delivers it.
    private let garbledDJ = "?u\u{FFFD}0??S"
    /// The same name repaired: ʞu¡0ɹʞS
    private let repairedDJ = "\u{029E}u\u{00A1}0\u{0279}\u{029E}S"

    // MARK: - Helpers

    private func edit(_ np: inout [String: Any],
                      streamer: Streamer,
                      title: String,
                      artist: String,
                      album: String) {
        var live = np["live"] as? [String: Any] ?? [:]
        switch streamer {
        case .named(let name): live["streamer_name"] = name
        case .blank: live["streamer_name"] = ""
        case .missingKey: live["streamer_name"] = nil
        case .notAString: live["streamer_name"] = 42
        case .noLiveBlock: live = [:]
        }
        if case .noLiveBlock = streamer {
            np["live"] = nil
        } else {
            np["live"] = live
        }

        var nowPlaying = np["now_playing"] as? [String: Any] ?? [:]
        var song = nowPlaying["song"] as? [String: Any] ?? [:]
        song["title"] = title
        song["artist"] = artist
        song["album"] = album
        nowPlaying["song"] = song
        np["now_playing"] = nowPlaying
    }

    /// The results of the same scenario sent as a connect message and as a
    /// channel message, labeled for failure messages.
    private func parseBothPaths(defaultDJ: String? = nil,
                                streamer: Streamer = .blank,
                                title: String = "Track",
                                artist: String = "Artist",
                                album: String = "Album") throws -> [(path: String, status: ACStreamStatus)] {
        var editedNP: [String: Any] = [:]
        let connectData = try ConnectMessageFixture.data { np in
            edit(&np, streamer: streamer, title: title, artist: artist, album: album)
            editedNP = np
        }
        let channelMessage: [String: Any] = [
            "channel": "station:\(shortCode)",
            "pub": ["data": ["np": editedNP]]
        ]
        let channelData = try JSONSerialization.data(withJSONObject: channelMessage)

        return [
            ("connect", try ParseWebSocketData(data: connectData, defaultDJ: defaultDJ).parse(shortCode: shortCode)),
            ("channel", try ParseWebSocketData(data: channelData, defaultDJ: defaultDJ).parse(shortCode: shortCode))
        ]
    }

    private func assertDJ(_ expectedDJ: String,
                          isLive expectedLive: Bool,
                          defaultDJ: String? = nil,
                          streamer: Streamer,
                          file: StaticString = #filePath,
                          line: UInt = #line) throws {
        for (path, status) in try parseBothPaths(defaultDJ: defaultDJ, streamer: streamer) {
            XCTAssertEqual(status.dj, expectedDJ, "\(path) dj", file: file, line: line)
            XCTAssertEqual(status.isLiveDJ, expectedLive, "\(path) isLiveDJ", file: file, line: line)
        }
    }

    private func assertSong(track expectedTrack: String,
                            artist expectedArtist: String,
                            album expectedAlbum: String,
                            defaultDJ: String? = nil,
                            streamer: Streamer,
                            title: String = "Track",
                            artist: String = "Artist",
                            album: String = "Album",
                            file: StaticString = #filePath,
                            line: UInt = #line) throws {
        let results = try parseBothPaths(defaultDJ: defaultDJ, streamer: streamer,
                                         title: title, artist: artist, album: album)
        for (path, status) in results {
            XCTAssertEqual(status.track, expectedTrack, "\(path) track", file: file, line: line)
            XCTAssertEqual(status.artist, expectedArtist, "\(path) artist", file: file, line: line)
            XCTAssertEqual(status.album, expectedAlbum, "\(path) album", file: file, line: line)
        }
    }

    // MARK: - Choosing the DJ

    func testNamedStreamerIsUsedOverTheDefaultAndIsLive() throws {
        try assertDJ("Night Owl", isLive: true, defaultDJ: "House DJ", streamer: .named("Night Owl"))
    }

    func testBlankStreamerUsesTheDefaultAndIsNotLive() throws {
        try assertDJ("House DJ", isLive: false, defaultDJ: "House DJ", streamer: .blank)
    }

    func testMissingStreamerNameUsesTheDefaultAndIsNotLive() throws {
        try assertDJ("House DJ", isLive: false, defaultDJ: "House DJ", streamer: .missingKey)
    }

    func testStreamerNameThatIsNotAStringUsesTheDefaultAndIsNotLive() throws {
        try assertDJ("House DJ", isLive: false, defaultDJ: "House DJ", streamer: .notAString)
    }

    func testMissingLiveBlockUsesTheDefaultAndIsNotLive() throws {
        try assertDJ("House DJ", isLive: false, defaultDJ: "House DJ", streamer: .noLiveBlock)
    }

    func testBlankStreamerWithNoDefaultLeavesTheDJBlankAndNotLive() throws {
        try assertDJ("", isLive: false, defaultDJ: nil, streamer: .blank)
    }

    func testNamedStreamerWithNoDefaultIsStillLive() throws {
        try assertDJ("Night Owl", isLive: true, defaultDJ: nil, streamer: .named("Night Owl"))
    }

    func testWhitespaceStreamerNameCountsAsALiveDJ() throws {
        // Current behaviour: only the empty string counts as blank.
        try assertDJ(" ", isLive: true, defaultDJ: "House DJ", streamer: .named(" "))
    }

    // MARK: - Cypress Rosewood swap

    func testLiveCypressRosewoodSwapsTrackAndArtist() throws {
        try assertSong(track: "Artist", artist: "Track", album: "Album",
                       streamer: .named("Cypress Rosewood"))
    }

    func testCypressRosewoodAsTheDefaultDJAlsoSwaps() throws {
        // Current behaviour: the rule reads the final DJ name, so it applies
        // when nobody is live and Cypress Rosewood is only the default.
        try assertSong(track: "Artist", artist: "Track", album: "Album",
                       defaultDJ: "Cypress Rosewood", streamer: .blank)
    }

    func testCypressRosewoodIsNotSplitOnTheDelimiter() throws {
        try assertSong(track: "Artist", artist: "One - Two", album: "",
                       streamer: .named("Cypress Rosewood"),
                       title: "One - Two", album: "")
    }

    func testOtherDJsAreNotSwapped() throws {
        try assertSong(track: "Track", artist: "Artist", album: "Album",
                       streamer: .named("Night Owl"))
    }

    func testTheCypressRosewoodMatchIsCaseSensitive() throws {
        try assertSong(track: "Track", artist: "Artist", album: "Album",
                       streamer: .named("cypress rosewood"))
    }

    // MARK: - "track - album" splitting

    func testTwoPartTitleBecomesTrackAndAlbum() throws {
        try assertSong(track: "One", artist: "Artist", album: "Two",
                       streamer: .named("Night Owl"),
                       title: "One - Two", album: "")
    }

    func testThreePartTitleTakesTheLastPartAsTheAlbum() throws {
        try assertSong(track: "One - Two", artist: "Artist", album: "Three",
                       streamer: .named("Night Owl"),
                       title: "One - Two - Three", album: "")
    }

    func testFourPartTitleTakesOnlyTheLastPartAsTheAlbum() throws {
        try assertSong(track: "One - Two - Three", artist: "Artist", album: "Four",
                       streamer: .named("Night Owl"),
                       title: "One - Two - Three - Four", album: "")
    }

    func testTitleIsNotSplitWhenAnAlbumExists() throws {
        try assertSong(track: "One - Two", artist: "Artist", album: "Album",
                       streamer: .named("Night Owl"),
                       title: "One - Two", album: "Album")
    }

    func testTitleIsNotSplitWhenThereIsNoDJ() throws {
        try assertSong(track: "One - Two", artist: "Artist", album: "",
                       defaultDJ: nil, streamer: .blank,
                       title: "One - Two", album: "")
    }

    func testDefaultDJIsEnoughToSplitTheTitle() throws {
        try assertSong(track: "One", artist: "Artist", album: "Two",
                       defaultDJ: "House DJ", streamer: .blank,
                       title: "One - Two", album: "")
    }

    func testTitleWithNoDelimiterIsLeftAlone() throws {
        try assertSong(track: "One", artist: "Artist", album: "",
                       streamer: .named("Night Owl"),
                       title: "One", album: "")
    }

    func testHyphenWithoutSpacesIsNotADelimiter() throws {
        try assertSong(track: "One-Two", artist: "Artist", album: "",
                       streamer: .named("Night Owl"),
                       title: "One-Two", album: "")
    }

    func testDelimiterAtTheStartLeavesTheTrackBlank() throws {
        // Current behaviour: a blank track fails both isValid checks in
        // StationMetadataManager.swift, so this song wouldn't count as valid.
        try assertSong(track: "", artist: "Artist", album: "Two",
                       streamer: .named("Night Owl"),
                       title: " - Two", album: "")
    }

    func testDelimiterAtTheEndLeavesTheAlbumBlank() throws {
        try assertSong(track: "One", artist: "Artist", album: "",
                       streamer: .named("Night Owl"),
                       title: "One - ", album: "")
    }

    func testDelimiterInTheArtistIsNotSplit() throws {
        try assertSong(track: "Track", artist: "One - Two", album: "",
                       streamer: .named("Night Owl"),
                       artist: "One - Two", album: "")
    }

    // MARK: - Garbled DJ name

    func testGarbledLiveDJNameIsRepairedAndStaysLive() throws {
        try assertDJ(repairedDJ, isLive: true, streamer: .named(garbledDJ))
    }

    func testGarbledDefaultDJNameIsRepairedAndIsNotLive() throws {
        try assertDJ(repairedDJ, isLive: false, defaultDJ: garbledDJ, streamer: .blank)
    }

    func testANameThatOnlyResemblesTheGarbledOneIsLeftAlone() throws {
        try assertDJ("?u?0??S", isLive: true, streamer: .named("?u?0??S"))
    }

    func testRepairedDJStillGetsItsTitleSplit() throws {
        try assertSong(track: "One", artist: "Artist", album: "Two",
                       streamer: .named(garbledDJ),
                       title: "One - Two", album: "")
    }
}
