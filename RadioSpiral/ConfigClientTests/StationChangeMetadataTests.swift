//
//  StationChangeMetadataTests.swift
//  ConfigClientTests
//
//  Changing station mustn't republish the previous station's track. The socket client's
//  status still holds it at that moment, and the new Now Playing screen shows whatever
//  the metadata manager has when it subscribes.
//
//  The new station's host can't resolve, so the socket opened by the change fails without
//  touching a real server. The shared manager is left disconnected afterwards.
//

import XCTest
@testable import RadioSpiral

final class StationChangeMetadataTests: XCTestCase {

    func testChangingStationReplacesThePreviousTrackWithTheNewStationsInfo() {
        let client = ACWebSocketClient.shared
        let manager = StationMetadataManager.shared
        addTeardownBlock { manager.disconnectCurrentStation() }

        let previous = ACStreamStatus()
        previous.track = "Previous Track"
        previous.artist = "Previous Artist"
        previous.artwork = URL(string: "https://example.invalid/previous.jpg")
        previous.changed = true
        previous.connection = client.status.connection
        client.status = previous

        let next = RadioStation(name: "Next Station",
                                streamURL: "https://example.invalid/next.mp3",
                                imageURL: "stationImage",
                                desc: "Next description",
                                serverName: "example.invalid",
                                shortCode: "next-station",
                                defaultDJ: "")
        manager.connectToStation(next)

        let metadata = manager.getCurrentMetadata()
        XCTAssertEqual(metadata?.trackName, "Next Station")
        XCTAssertEqual(metadata?.artistName, "Next description")
        XCTAssertNil(metadata?.artworkURL, "Nil artwork makes Now Playing use the station's art")
    }
}
