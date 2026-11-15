//
//  ChannelStatusMessagesTests.swift
//  ConfigClientTests
//
//  Task-44: what the listener is told when a channel is offline or can't be described.
//  The phone shows it in the Now Playing banner; the lock screen and CarPlay show it as the
//  title. "Channel" is the word the station's management uses for a stream.
//
//  Audio outranks metadata, so a frozen stream ("Connection lost") comes before a message
//  about the channel's information, and only an offline channel, which makes the audio stop too,
//  comes before it.
//

import XCTest
import MediaPlayer
@testable import RadioSpiral

final class ChannelStatusMessagesTests: XCTestCase {

    // MARK: The phone's banner

    func testAnOfflineChannelSaysSo() {
        XCTAssertEqual(ChannelStatusMessages.phoneBanner(connection: .offline, isStalled: false), "This channel is offline")
    }

    func testAnOfflineChannelSaysSoEvenWhenTheAudioHasStalledToo() {
        XCTAssertEqual(ChannelStatusMessages.phoneBanner(connection: .offline, isStalled: true), "This channel is offline",
                       "An offline channel stalls the audio; that is the reason, not a lost connection")
    }

    func testAFailedSubscriptionSaysTheInformationCantBeLoaded() {
        XCTAssertEqual(ChannelStatusMessages.phoneBanner(connection: .failed, isStalled: false),
                       "Can't load this channel's information")
    }

    func testAStalledStreamComesBeforeAFailedSubscription() {
        XCTAssertEqual(ChannelStatusMessages.phoneBanner(connection: .failed, isStalled: true),
                       "Connection lost — reconnecting…", "The audio stopping matters more than missing track info")
    }

    func testAStalledStreamStillSaysConnectionLost() {
        for connection in [MetadataConnectionState.connected, .connecting, .disconnected, .reconnecting] {
            XCTAssertEqual(ChannelStatusMessages.phoneBanner(connection: connection, isStalled: true),
                           "Connection lost — reconnecting…", "\(connection)")
        }
    }

    func testNothingIsWrongSoThereIsNoBanner() {
        for connection in [MetadataConnectionState.connected, .connecting, .disconnected, .reconnecting] {
            XCTAssertNil(ChannelStatusMessages.phoneBanner(connection: connection, isStalled: false), "\(connection)")
        }
    }

    // MARK: The time bubble

    /// An offline channel has no track to time. Without this the bubble would count up from zero.
    func testAnOfflineChannelHasNoTimeToShow() {
        XCTAssertTrue(ChannelStatusMessages.showsNoTime(connection: .offline))
        for connection in [MetadataConnectionState.connected, .connecting, .disconnected, .reconnecting, .failed] {
            XCTAssertFalse(ChannelStatusMessages.showsNoTime(connection: connection), "\(connection)")
        }
    }

    // MARK: The lock screen and CarPlay title

    func testTheTitleSaysChannelOfflineOrUnavailable() {
        XCTAssertEqual(ChannelStatusMessages.nowPlayingTitle(connection: .offline), "Channel offline")
        XCTAssertEqual(ChannelStatusMessages.nowPlayingTitle(connection: .failed), "Channel unavailable")
    }

    func testTheTitleIsLeftAloneWhenNothingIsWrong() {
        for connection in [MetadataConnectionState.connected, .connecting, .disconnected, .reconnecting] {
            XCTAssertNil(ChannelStatusMessages.nowPlayingTitle(connection: connection), "\(connection)")
        }
    }

    func testANoticeReplacesTheTitleAndNothingElse() {
        let existing: [String: Any] = [MPMediaItemPropertyTitle: "Old"]
        let metadata = UnifiedMetadata(trackName: "Song", artistName: "Artist", albumName: "Album", duration: 200, elapsed: 75)

        let info = StationsManager.trackInfo(from: existing, metadata: metadata, artistLine: "Artist", notice: "Channel offline")

        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Channel offline")
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "Artist")
        XCTAssertEqual(info[MPMediaItemPropertyAlbumTitle] as? String, "Album")
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double, 200)
    }

    func testWithNoNoticeTheTrackNameIsTheTitle() {
        let metadata = UnifiedMetadata(trackName: "Song", artistName: "Artist")

        let info = StationsManager.trackInfo(from: [:], metadata: metadata, artistLine: "Artist", notice: nil)

        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Song")
    }
}
