//
//  SecureURLTests.swift
//  ConfigClientTests
//
//  URLs from the server and config are used only if they're https. Nothing here
//  reaches the network: the addresses don't resolve, and rejected ones aren't loaded.
//

import XCTest
@testable import RadioSpiral

final class SecureURLTests: XCTestCase {
    private let shortCode = ConnectMessageFixture.shortCode

    // MARK: The rule

    func testOnlyHTTPSIsAccepted() {
        let cases: [(string: String, accepted: Bool)] = [
            ("https://radio.example/art.png", true),
            ("HTTPS://radio.example/art.png", true),
            ("http://radio.example/art.png", false),
            ("HTTP://radio.example/art.png", false),
            ("file:///etc/hosts", false),
            ("ftp://radio.example/art.png", false),
            ("radio.example/art.png", false),
            ("https-not-really://radio.example", false),
            ("", false)
        ]
        for (string, accepted) in cases {
            XCTAssertEqual(SecureURL.https(string) != nil, accepted, string)
        }
    }

    func testAnAcceptedURLIsUnchanged() {
        XCTAssertEqual(SecureURL.https("https://radio.example:8000/a.mp3?b=1")?.absoluteString,
                       "https://radio.example:8000/a.mp3?b=1")
    }

    // MARK: Artwork

    private func editingArt(_ art: String) -> (inout [String: Any]) -> Void {
        { np in
            guard var nowPlaying = np["now_playing"] as? [String: Any],
                  var song = nowPlaying["song"] as? [String: Any] else {
                return XCTFail("the fixture has no song")
            }
            song["art"] = art
            nowPlaying["song"] = song
            np["now_playing"] = nowPlaying
        }
    }

    private func parseConnect(art: String) throws -> ACStreamStatus {
        let data = try ConnectMessageFixture.data(editingNP: editingArt(art))
        return try ParseWebSocketData(data: data, defaultDJ: nil).parse(shortCode: shortCode)
    }

    private func parseChannel(art: String) throws -> ACStreamStatus {
        var np: [String: Any] = [:]
        _ = try ConnectMessageFixture.data { fixtureNP in
            self.editingArt(art)(&fixtureNP)
            np = fixtureNP
        }
        let message: [String: Any] = ["channel": "station:\(shortCode)", "pub": ["data": ["np": np]]]
        let data = try JSONSerialization.data(withJSONObject: message)
        return try ParseWebSocketData(data: data, defaultDJ: nil).parse(shortCode: shortCode)
    }

    /// With no artwork URL, Now Playing shows the station's art.
    func testArtworkThatIsNotHTTPSIsDropped() throws {
        for art in ["http://radio.example/art.png", "file:///etc/hosts"] {
            XCTAssertNil(try parseConnect(art: art).artwork, "connect message, \(art)")
            XCTAssertNil(try parseChannel(art: art).artwork, "channel message, \(art)")
        }
    }

    func testHTTPSArtworkIsKept() throws {
        let art = "https://radio.example/art.png"
        XCTAssertEqual(try parseConnect(art: art).artwork?.absoluteString, art)
        XCTAssertEqual(try parseChannel(art: art).artwork?.absoluteString, art)
    }

    /// Rejected art shouldn't take the song's other details with it.
    func testDroppedArtworkKeepsTheRestOfTheSong() throws {
        let https = try parseConnect(art: "https://radio.example/art.png")
        let http = try parseConnect(art: "http://radio.example/art.png")

        XCTAssertFalse(https.track.isEmpty)
        XCTAssertEqual(http.track, https.track)
        XCTAssertEqual(http.artist, https.artist)
    }

    // MARK: Streams

    func testAStreamThatIsNotHTTPSIsNotPlayed() {
        let player = RadioPlayer.shared
        addTeardownBlock { player.radioURL = nil }

        player.radioURL = URL(string: "https://secure-url-test.invalid/stream")
        XCTAssertEqual(player.state, .loading)

        player.radioURL = URL(string: "http://secure-url-test.invalid/stream")
        XCTAssertEqual(player.state, .idle, "the screen says the station's URL isn't valid")

        player.play()
        XCTAssertNotEqual(player.playbackState, .playing)
    }

    // MARK: Station images

    private func image(for imageURL: String) -> UIImage? {
        let station = RadioStation(name: "Test", streamURL: "https://secure-url-test.invalid/stream",
                                   imageURL: imageURL, desc: "", serverName: "secure-url-test.invalid",
                                   shortCode: "test", defaultDJ: "")
        var result: UIImage?
        // A rejected address never goes to the network, so this answers before returning.
        station.getImage { result = $0 }
        return result
    }

    func testAStationImageThatIsNotHTTPSUsesTheDefault() throws {
        let image = try XCTUnwrap(image(for: "http://secure-url-test.invalid/station.png"))
        let standard = try XCTUnwrap(UIImage(named: "stationImage",
                                             in: Bundle(for: RadioPlayer.self), compatibleWith: nil))

        XCTAssertEqual(image.pngData(), standard.pngData())
    }

    func testABundledStationImageStillLoads() throws {
        let image = try XCTUnwrap(image(for: "albumArt"))
        let bundled = try XCTUnwrap(UIImage(named: "albumArt",
                                            in: Bundle(for: RadioPlayer.self), compatibleWith: nil))

        XCTAssertEqual(image.pngData(), bundled.pngData())
    }
}
