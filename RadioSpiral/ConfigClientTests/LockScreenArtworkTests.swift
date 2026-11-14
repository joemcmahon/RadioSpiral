//
//  LockScreenArtworkTests.swift
//  ConfigClientTests
//
//  Task-33: the lock screen must not keep the previous track's artwork
//  when the current track has none.
//

import XCTest
import MediaPlayer
import UIKit
@testable import RadioSpiral

final class LockScreenArtworkTests: XCTestCase {

    private func artwork() -> MPMediaItemArtwork {
        let image = UIImage()
        return MPMediaItemArtwork(boundsSize: CGSize(width: 1, height: 1)) { _ in image }
    }

    func testNewTrackDoesNotKeepPreviousTracksArtwork() {
        let existing: [String: Any] = [MPMediaItemPropertyTitle: "Old", MPMediaItemPropertyArtwork: artwork()]
        let metadata = UnifiedMetadata(trackName: "New", artistName: "Artist")

        let info = StationsManager.trackInfo(from: existing, metadata: metadata, artistLine: "Artist")

        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "New")
        XCTAssertNil(info[MPMediaItemPropertyArtwork], "old artwork must not carry over to a track")
    }
}
