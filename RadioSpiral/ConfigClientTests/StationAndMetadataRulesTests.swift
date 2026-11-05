//
//  StationAndMetadataRulesTests.swift
//  ConfigClientTests
//
//  Pins the rules that decide whether two stations or two metadata values count
//  as the same, and whether metadata is usable:
//
//  - RadioStation(from:) decides which config value lands in which field.
//  - RadioStation == decides whether a refreshed station list gets applied, and
//    whether the current station counts as gone from it (StationsManager.fetch).
//  - UnifiedMetadata == decides whether subscribers hear about an update
//    (StationMetadataManager.updateMetadata).
//  - ACStreamStatus == decides whether a socket message counts as new
//    (ACWebSocketClient.handleMessage).
//  - isValid decides whether socket metadata is used at all.
//
//  These capture what the code does today. Some of it looks wrong, and those
//  tests say so: see F1 and F5 in the findings log. A fix should turn them red,
//  and the test then changes to assert the new behaviour.
//

import XCTest
import UIKit
@testable import RadioSpiral

final class StationAndMetadataRulesTests: XCTestCase {

    // MARK: - Helpers

    private func makeStation() -> RadioStation {
        RadioStation(name: "Name",
                     streamURL: "https://example.test/stream",
                     imageURL: "https://example.test/image.png",
                     desc: "Desc",
                     longDesc: "Long desc",
                     serverName: "Server",
                     shortCode: "code",
                     defaultDJ: "DJ")
    }

    private func makeStatus() -> ACStreamStatus {
        ACStreamStatus(connection: .connected,
                       isLiveDJ: false,
                       track: "Track",
                       artist: "Artist",
                       album: "Album",
                       duration: 300,
                       elapsed: 10,
                       dj: "DJ",
                       artwork: URL(string: "https://example.test/art.png"))
    }

    private func makeMetadata(trackName: String = "Track",
                              albumName: String? = "Album") -> UnifiedMetadata {
        UnifiedMetadata(trackName: trackName,
                        artistName: "Artist",
                        albumName: albumName,
                        artworkURL: URL(string: "https://example.test/art.png"),
                        duration: 300,
                        elapsed: 10,
                        broadcastStart: Date(timeIntervalSince1970: 1_000),
                        djName: "DJ",
                        isLiveDJ: false)
    }

    // MARK: - RadioStation(from:)

    func testStationFromConfigPutsEveryValueInItsOwnField() {
        let config = RadioSpiral.StationConfig(name: "config name",
                                               streamURL: "config stream",
                                               imageURL: "config image",
                                               desc: "config desc",
                                               longDesc: "config long desc",
                                               serverName: "config server",
                                               shortCode: "config code",
                                               defaultDJ: "config dj")

        let station = RadioStation(from: config)

        XCTAssertEqual(station.name, "config name")
        XCTAssertEqual(station.streamURL, "config stream")
        XCTAssertEqual(station.imageURL, "config image")
        XCTAssertEqual(station.desc, "config desc")
        XCTAssertEqual(station.longDesc, "config long desc")
        XCTAssertEqual(station.serverName, "config server")
        XCTAssertEqual(station.shortCode, "config code")
        XCTAssertEqual(station.defaultDJ, "config dj")
    }

    // MARK: - RadioStation ==

    func testIdenticalStationsAreEqual() {
        XCTAssertEqual(makeStation(), makeStation())
    }

    func testStationsDifferWhenAComparedFieldDiffers() {
        let comparedFields: [(String, WritableKeyPath<RadioStation, String>)] = [
            ("name", \.name),
            ("streamURL", \.streamURL),
            ("imageURL", \.imageURL),
            ("desc", \.desc),
            ("longDesc", \.longDesc)
        ]

        for (label, field) in comparedFields {
            var changed = makeStation()
            changed[keyPath: field] = "something else"
            XCTAssertNotEqual(changed, makeStation(), "\(label) should make stations differ")
        }
    }

    func testStationsStayEqualWhenAnIgnoredFieldDiffers() {
        // Current behaviour: shortCode selects the station on the metadata socket,
        // yet two stations differing only in shortCode count as the same station.
        let ignoredFields: [(String, WritableKeyPath<RadioStation, String>)] = [
            ("shortCode", \.shortCode),
            ("serverName", \.serverName),
            ("defaultDJ", \.defaultDJ)
        ]

        for (label, field) in ignoredFields {
            var changed = makeStation()
            changed[keyPath: field] = "something else"
            XCTAssertEqual(changed, makeStation(), "\(label) should not make stations differ")
        }
    }

    func testStationsStayEqualWhenOnlyTheDefaultArtworkDiffers() {
        var changed = makeStation()
        changed.defaultArtwork = UIImage()

        XCTAssertEqual(changed, makeStation())
    }

    func testStationListDifferingOnlyInShortCodeCountsAsUnchanged() {
        // StationsManager.fetch skips a new list that compares equal, so today a
        // config edit that changes only a short code isn't applied by a refresh.
        var changed = makeStation()
        changed.shortCode = "new-code"

        XCTAssertFalse([makeStation()] != [changed])
    }

    func testCurrentStationIsStillFoundWhenOnlyItsShortCodeChanged() {
        var changed = makeStation()
        changed.shortCode = "new-code"

        XCTAssertEqual([changed].firstIndex(of: makeStation()), 0)
    }

    func testCurrentStationIsGoneWhenItsStreamURLChanged() {
        // The switch-day path: a station whose stream URL changed is treated as
        // gone from the list, which is what makes StationsManager.fetch reset.
        var changed = makeStation()
        changed.streamURL = "https://example.test/new-stream"

        XCTAssertNil([changed].firstIndex(of: makeStation()))
    }

    // MARK: - UnifiedMetadata ==

    func testMetadataWithTheSameTrackAndAlbumIsEqual() {
        XCTAssertEqual(makeMetadata(), makeMetadata())
    }

    func testMetadataDiffersWhenTheTrackDiffers() {
        XCTAssertNotEqual(makeMetadata(trackName: "Other Track"), makeMetadata())
    }

    func testMetadataDiffersWhenTheAlbumDiffers() {
        XCTAssertNotEqual(makeMetadata(albumName: "Other Album"), makeMetadata())
    }

    func testMetadataDiffersWhenOnlyOneHasAnAlbum() {
        XCTAssertNotEqual(makeMetadata(albumName: nil), makeMetadata())
    }

    func testMetadataComparisonIgnoresCaseInTrackAndAlbum() {
        XCTAssertEqual(makeMetadata(trackName: "TRACK"), makeMetadata())
        XCTAssertEqual(makeMetadata(albumName: "aLbUm"), makeMetadata())
    }

    func testMetadataComparisonTrimsTrackAndAlbum() {
        XCTAssertEqual(makeMetadata(trackName: "  Track\n"), makeMetadata())
        XCTAssertEqual(makeMetadata(albumName: "\tAlbum  "), makeMetadata())
    }

    func testMetadataComparisonKeepsSpacesInsideTheTrack() {
        XCTAssertNotEqual(makeMetadata(trackName: "Tr ack"), makeMetadata())
    }

    func testMissingAlbumEqualsBlankAlbum() {
        XCTAssertEqual(makeMetadata(albumName: nil), makeMetadata(albumName: ""))
        XCTAssertEqual(makeMetadata(albumName: nil), makeMetadata(albumName: "  \n"))
    }

    func testMetadataStaysEqualWhenAnythingButTrackOrAlbumDiffers() {
        // Current behaviour, finding F5: updateMetadata uses this rule to decide
        // whether metadata "has actually changed", so a new artist, artwork or DJ
        // on the same track and album sends subscribers no update.
        let base = makeMetadata()
        let variants: [(String, UnifiedMetadata)] = [
            ("artistName", UnifiedMetadata(trackName: "Track", artistName: "Other Artist", albumName: "Album",
                                           artworkURL: base.artworkURL, duration: 300, elapsed: 10,
                                           broadcastStart: base.broadcastStart, djName: "DJ", isLiveDJ: false)),
            ("artworkURL", UnifiedMetadata(trackName: "Track", artistName: "Artist", albumName: "Album",
                                           artworkURL: URL(string: "https://example.test/other.png"), duration: 300, elapsed: 10,
                                           broadcastStart: base.broadcastStart, djName: "DJ", isLiveDJ: false)),
            ("duration", UnifiedMetadata(trackName: "Track", artistName: "Artist", albumName: "Album",
                                         artworkURL: base.artworkURL, duration: 999, elapsed: 10,
                                         broadcastStart: base.broadcastStart, djName: "DJ", isLiveDJ: false)),
            ("elapsed", UnifiedMetadata(trackName: "Track", artistName: "Artist", albumName: "Album",
                                        artworkURL: base.artworkURL, duration: 300, elapsed: 99,
                                        broadcastStart: base.broadcastStart, djName: "DJ", isLiveDJ: false)),
            ("broadcastStart", UnifiedMetadata(trackName: "Track", artistName: "Artist", albumName: "Album",
                                               artworkURL: base.artworkURL, duration: 300, elapsed: 10,
                                               broadcastStart: Date(timeIntervalSince1970: 2_000), djName: "DJ", isLiveDJ: false)),
            ("djName", UnifiedMetadata(trackName: "Track", artistName: "Artist", albumName: "Album",
                                       artworkURL: base.artworkURL, duration: 300, elapsed: 10,
                                       broadcastStart: base.broadcastStart, djName: "Other DJ", isLiveDJ: false)),
            ("isLiveDJ", UnifiedMetadata(trackName: "Track", artistName: "Artist", albumName: "Album",
                                         artworkURL: base.artworkURL, duration: 300, elapsed: 10,
                                         broadcastStart: base.broadcastStart, djName: "DJ", isLiveDJ: true))
        ]

        for (label, variant) in variants {
            XCTAssertEqual(variant, base, "\(label) should not make metadata differ")
        }
    }

    // MARK: - ACStreamStatus ==

    func testIdenticalStatusesAreEqual() {
        XCTAssertEqual(makeStatus(), makeStatus())
    }

    func testStatusesDifferWhenAComparedFieldDiffers() {
        let changes: [(String, (ACStreamStatus) -> Void)] = [
            ("connection", { $0.connection = .disconnected }),
            ("isLiveDJ", { $0.isLiveDJ = true }),
            ("track", { $0.track = "Other" }),
            ("artist", { $0.artist = "Other" }),
            ("album", { $0.album = "Other" }),
            ("dj", { $0.dj = "Other" })
        ]

        for (label, change) in changes {
            let changed = makeStatus()
            change(changed)
            XCTAssertNotEqual(changed, makeStatus(), "\(label) should make statuses differ")
        }
    }

    func testStatusesDifferWhenOnlyElapsedDiffers() {
        // Current behaviour, finding F1: elapsed is compared, so the same song
        // moments later counts as a new status. The comment in handleMessage says
        // messages with the same data are skipped.
        let changed = makeStatus()
        changed.elapsed = 11

        XCTAssertNotEqual(changed, makeStatus())
    }

    func testStatusesStayEqualWhenAnIgnoredFieldDiffers() {
        let changes: [(String, (ACStreamStatus) -> Void)] = [
            ("changed", { $0.changed = false }),
            ("duration", { $0.duration = 999 }),
            ("artwork", { $0.artwork = URL(string: "https://example.test/other.png") }),
            ("broadcastStart", { $0.broadcastStart = Date(timeIntervalSince1970: 2_000) }),
            ("recordType", { $0.recordType = .channel }),
            ("pingInterval", { $0.pingInterval = 25 })
        ]

        for (label, change) in changes {
            let changed = makeStatus()
            change(changed)
            XCTAssertEqual(changed, makeStatus(), "\(label) should not make statuses differ")
        }
    }

    // MARK: - UnifiedMetadata.isValid

    func testMetadataWithTrackAndArtistIsValid() {
        XCTAssertTrue(UnifiedMetadata(trackName: "Track", artistName: "Artist").isValid)
    }

    func testMetadataWithAnEmptyTrackIsNotValid() {
        XCTAssertFalse(UnifiedMetadata(trackName: "", artistName: "Artist").isValid)
    }

    func testMetadataWithAnEmptyArtistIsNotValid() {
        XCTAssertFalse(UnifiedMetadata(trackName: "Track", artistName: "").isValid)
    }

    func testMetadataWithABlankButNotEmptyTrackIsValid() {
        // Current behaviour: only an empty string fails. Equality trims; this doesn't.
        XCTAssertTrue(UnifiedMetadata(trackName: "  ", artistName: "Artist").isValid)
    }

    // MARK: - ACStreamStatus.isValid

    func testStatusWithTrackAndArtistMarkedChangedIsValid() {
        XCTAssertTrue(makeStatus().isValid)
    }

    func testStatusWithAnEmptyTrackIsNotValid() {
        let status = makeStatus()
        status.track = ""

        XCTAssertFalse(status.isValid)
    }

    func testStatusWithAnEmptyArtistIsNotValid() {
        let status = makeStatus()
        status.artist = ""

        XCTAssertFalse(status.isValid)
    }

    func testStatusNotMarkedChangedIsNotValid() {
        let status = makeStatus()
        status.changed = false

        XCTAssertFalse(status.isValid)
    }

    func testNewBlankStatusIsNotValid() {
        XCTAssertFalse(ACStreamStatus().isValid)
    }
}
