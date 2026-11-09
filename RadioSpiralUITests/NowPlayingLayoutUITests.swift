//
//  NowPlayingLayoutUITests.swift
//  RadioSpiralUITests
//
//  Now Playing with very long titles: every label has to be on screen, none squeezed to nothing
//  or overlapping another or the volume slider. Run it on each device
//  that matters (a short phone like the iPhone 17e or SE, the iPhone 17, a Pro Max, an iPad).
//
//  Live, like StationListE2ETests: it needs GitHub and the production server (one station, so it
//  opens Now Playing directly). Only a listener connection is made; nothing is played or changed.
//  Debug builds replace the labels' text through the `-nowPlayingDemoTitle` launch argument,
//  so the result doesn't depend on what is playing. Set TEST_RUNNER_LAYOUT_SERVER=test to use
//  the test server and its station list instead.
//
//  To keep screenshots as files, set TEST_RUNNER_LAYOUT_SHOT_DIR to a folder when running
//  xcodebuild. They are always attached to the test result as well.
//

import XCTest

final class NowPlayingLayoutUITests: XCTestCase {

    private let app = XCUIApplication()

    private let titles = [
        "Puja in the Temple of Sound (with Lam Sadashiva) — Excerpt",
        // A real track from the library, the longest seen so far.
        "the sky is superimposed with myriads of drones preparing to wipe humanity off the face of the earth (Extended Version)",
    ]
    private let artist = "Demo Artist"
    private let album = "Demo Album (2006-2023)"
    private let dj = "Demo DJ"

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    override func tearDown() {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: Helpers

    @MainActor private func openNowPlaying(title: String) {
        app.terminate()
        // Production has one station and opens Now Playing directly, so it needs no station
        // list. LAYOUT_SERVER=test (TEST_RUNNER_LAYOUT_SERVER) uses the test server's list.
        let useTestServer = ProcessInfo.processInfo.environment["LAYOUT_SERVER"] == "test"
        app.launchArguments = (useTestServer ? ["-stationServer", "test"] : [])
            + ["-nowPlayingDemoTitle", title]
        app.launch()
        let playButton = app.buttons["playPauseButton"]
        if !playButton.waitForExistence(timeout: 20) {
            let cells = app.collectionViews.cells
            XCTAssertTrue(cells.element(boundBy: 0).waitForExistence(timeout: 20),
                          "Neither Now Playing nor a station list appeared")
            cells.element(boundBy: 0).tap()
            XCTAssertTrue(playButton.waitForExistence(timeout: 10))
        }
    }

    @MainActor private func rotate(to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        sleep(2)
    }

    @MainActor private func attachScreenshot(named name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["LAYOUT_SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let file = name.replacingOccurrences(of: " ", with: "_") + ".png"
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + file))
        }
    }

    /// The four text labels, each fully inside the window, with room to read, in a column without
    /// overlap, and above the volume slider.
    @MainActor private func assertLabelsFit(title: String, context: String) {
        let names = ["title": title, "artist": artist, "album": album, "DJ": dj]
        let window = app.windows.firstMatch.frame
        var frames: [(String, CGRect)] = []

        for (role, text) in names.sorted(by: { $0.key < $1.key }) {
            let label = app.staticTexts[text]
            guard label.waitForExistence(timeout: 20) else {
                XCTFail("\(context): the \(role) label never appeared")
                continue
            }
            let frame = label.frame
            XCTAssertGreaterThanOrEqual(frame.height, 10, "\(context): the \(role) label is squeezed (\(frame))")
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame),
                          "\(context): the \(role) label is outside the screen (\(frame) in \(window))")
            frames.append((role, frame))
        }

        let ordered = frames.sorted { $0.1.minY < $1.1.minY }
        for (upper, lower) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThanOrEqual(upper.1.maxY, lower.1.minY + 1,
                                     "\(context): the \(upper.0) label overlaps the \(lower.0) label")
        }

        // The slider is below the labels in landscape and above them in portrait, so only check
        // that no label shares vertical space with it.
        let slider = app.sliders.firstMatch
        if slider.exists {
            for (role, frame) in ordered {
                let clear = frame.maxY <= slider.frame.minY + 1 || frame.minY >= slider.frame.maxY - 1
                XCTAssertTrue(clear, "\(context): the \(role) label overlaps the volume slider (\(frame) vs \(slider.frame))")
            }
        }
    }

    // MARK: Tests

    @MainActor func testLongTitlesFitInLandscape() {
        for (index, title) in titles.enumerated() {
            openNowPlaying(title: title)
            rotate(to: .landscapeLeft)
            assertLabelsFit(title: title, context: "landscape, title \(index + 1)")
            attachScreenshot(named: "landscape title \(index + 1)")
        }
    }

    @MainActor func testLongTitlesFitInPortrait() {
        for (index, title) in titles.enumerated() {
            openNowPlaying(title: title)
            rotate(to: .portrait)
            assertLabelsFit(title: title, context: "portrait, title \(index + 1)")
            attachScreenshot(named: "portrait title \(index + 1)")
        }
    }
}
