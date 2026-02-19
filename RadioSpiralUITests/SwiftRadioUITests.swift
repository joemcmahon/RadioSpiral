//
//  SwiftRadioUITests.swift
//  SwiftRadioUITests
//
//  Created by Jonah Stiennon on 12/3/15.
//  Copyright © 2015 matthewfecher.com. All rights reserved.
//

import XCTest


class SwiftRadioUITests: XCTestCase {

    let app = XCUIApplication()

    // Lazy element queries — resolved at access time, after app.launch()
    var playPauseButton: XCUIElement { app.buttons["playPauseButton"] }
    var shareButton: XCUIElement { app.buttons["shareButton"] }
    var infoButton: XCUIElement { app.buttons["infoButton"] }
    var okButton: XCUIElement { app.buttons["okButton"] }
    var volume: XCUIElement { app.sliders.element(boundBy: 0) }

    @MainActor override func setUp() {
        super.setUp()
        continueAfterFailure = false
        setupSnapshot(app)
        app.launch()
    }

    override func tearDown() {
        super.tearDown()
    }

    @MainActor func testTransitionToNowPlaying() {
        XCTAssertTrue(playPauseButton.waitForExistence(timeout: 30.0))
        // Wait for stream to connect and deliver real track metadata
        sleep(10)
        XCUIDevice.shared.orientation = .portrait
        snapshot("01playing_portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        snapshot("01playing_landscape")
    }

    @MainActor func testSharing() {
        XCTAssertTrue(shareButton.waitForExistence(timeout: 10.0))
        // Wait for stream to connect and deliver real track metadata
        // so the share text shows actual track info, not the station description
        sleep(10)
        shareButton.tap()
        // Wait for share sheet to appear
        sleep(2)
        XCUIDevice.shared.orientation = .portrait
        snapshot("02share_portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        snapshot("02share_landscape")
    }

    @MainActor func testInfo() {
        XCTAssertTrue(infoButton.waitForExistence(timeout: 10.0))
        infoButton.tap()
        XCTAssertTrue(okButton.waitForExistence(timeout: 10.0))
        XCUIDevice.shared.orientation = .portrait
        snapshot("03info_portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        snapshot("03info_landscape")
        okButton.tap()
    }
}
