//
//  ParseLiveShowBackfillTests.swift
//  ConfigClientTests
//
//  A live streamer's own metadata can leave the artist empty: on 2026-11-15 Cypress Rosewood's
//  54-minute show was served as title "MusicMeditationAmbientSunday" with no artist (from the
//  song history). The app needs a non-empty track and artist (`isValid`), so it showed the
//  station's name and blurb for the whole show, with the time bubble counting from zero.
//  A live show with no artist takes the streamer's name as the artist, and Cypress Rosewood's
//  track/artist swap applies only when he sent both.
//
//  Song values are the real entries from the song history; the rest of each message is the
//  captured message in ws-connect-message.json. Every scenario runs through the connect and
//  the channel message paths, as in ParseDJRulesTests.
//

import XCTest
@testable import RadioSpiral

final class ParseLiveShowBackfillTests: XCTestCase {

    private let shortCode = ConnectMessageFixture.shortCode
    private let tony = "Cypress Rosewood"

    private func parseBothPaths(streamer: String, title: String, artist: String,
                                defaultDJ: String? = nil) throws -> [(path: String, status: ACStreamStatus)] {
        var editedNP: [String: Any] = [:]
        let connectData = try ConnectMessageFixture.data { np in
            var live = np["live"] as? [String: Any] ?? [:]
            live["streamer_name"] = streamer
            np["live"] = live
            var nowPlaying = np["now_playing"] as? [String: Any] ?? [:]
            var song = nowPlaying["song"] as? [String: Any] ?? [:]
            song["title"] = title
            song["artist"] = artist
            song["album"] = ""
            nowPlaying["song"] = song
            np["now_playing"] = nowPlaying
            editedNP = np
        }
        let channelData = try JSONSerialization.data(withJSONObject: [
            "channel": "station:\(shortCode)",
            "pub": ["data": ["np": editedNP]]
        ] as [String: Any])
        return [
            ("connect", try ParseWebSocketData(data: connectData, defaultDJ: defaultDJ).parse(shortCode: shortCode)),
            ("channel", try ParseWebSocketData(data: channelData, defaultDJ: defaultDJ).parse(shortCode: shortCode))
        ]
    }

    private func assertSong(track: String, artist: String, valid: Bool,
                            streamer: String, title: String, artistSent: String, defaultDJ: String? = nil,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        for (path, status) in try parseBothPaths(streamer: streamer, title: title, artist: artistSent, defaultDJ: defaultDJ) {
            XCTAssertEqual(status.track, track, "\(path) track", file: file, line: line)
            XCTAssertEqual(status.artist, artist, "\(path) artist", file: file, line: line)
            XCTAssertEqual(status.isValid, valid, "\(path) isValid", file: file, line: line)
        }
    }

    // MARK: - The show that fell back to the station's name

    func testCypressRosewoodsShowTitleWithNoArtistIsShownWithHimAsTheArtist() throws {
        try assertSong(track: "MusicMeditationAmbientSunday", artist: tony, valid: true,
                       streamer: tony, title: "MusicMeditationAmbientSunday", artistSent: "")
    }

    func testAnotherLiveStreamerWithNoArtistGetsTheirNameAsTheArtist() throws {
        try assertSong(track: "Some Show", artist: "Night Owl", valid: true,
                       streamer: "Night Owl", title: "Some Show", artistSent: "")
    }

    // MARK: - What stays as it was

    func testCypressRosewoodsOwnTrackAndArtistAreStillSwappedWhenBothAreSent() throws {
        // His 18:01 entry from the history: title and artist arrive the wrong way round.
        try assertSong(track: "Cypress Rosewood LIVE for RAdioSpiral", artist: tony, valid: true,
                       streamer: tony, title: tony, artistSent: "Cypress Rosewood LIVE for RAdioSpiral")
    }

    func testAnArtistThatWasSentIsNotReplacedByTheStreamersName() throws {
        try assertSong(track: "Track", artist: "Real Artist", valid: true,
                       streamer: "Night Owl", title: "Track", artistSent: "Real Artist")
    }

    func testAShowWithNeitherTitleNorArtistStillFallsBackBecauseThereIsNoTrack() throws {
        // Seen once in the history, for 14 seconds. The streamer's name fills the artist, but there
        // is still no track, so it isn't valid and the station's own info shows.
        try assertSong(track: "", artist: "Night Owl", valid: false,
                       streamer: "Night Owl", title: "", artistSent: "")
    }

    func testNobodyLiveMeansNoBackfill() throws {
        // A default DJ is not a streamer: an empty artist stays empty, as before.
        try assertSong(track: "Song", artist: "", valid: false,
                       streamer: "", title: "Song", artistSent: "", defaultDJ: "House DJ")
    }
}
