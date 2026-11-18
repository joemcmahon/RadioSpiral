//
//  NowPlayingFrameBaselineUITests.swift
//  RadioSpiralUITests
//
//  One subject: dump where every Now Playing element sits, as text, so a layout change can be
//  compared with the layout before it (`diff -r`). It asserts nothing about the layout itself.
//
//  Set TEST_RUNNER_LAYOUT_BASELINE_DIR to a folder when running xcodebuild; each run writes
//  `<device>-<orientation>-title<N>.txt` there, one line per element: `role x y width height`,
//  rounded to 0.5 pt. Without the variable nothing is written. Set TEST_RUNNER_LAYOUT_SHOT_DIR
//  to also keep a screenshot beside each dump (same name, .png).
//
//  Live, like NowPlayingLayoutUITests: it needs GitHub and the production server (one station,
//  so Now Playing opens directly). Debug builds replace the labels' text through the
//  `-nowPlayingDemoTitle` launch argument. The live-show indicator is pinned off through `-nowPlayingDemoLive`
//  (TEST_RUNNER_LAYOUT_LIVE=on shows it), so a live DJ on air cannot change a dump. TEST_RUNNER_LAYOUT_SERVER=test uses the test server.
//

import XCTest

final class NowPlayingFrameBaselineUITests: XCTestCase {

    private let app = XCUIApplication()

    /// title1 is short, title2 is the first title of `NowPlayingLayoutUITests`, title3 its longest.
    private let titles = [
        "Sunrise",
        "Puja in the Temple of Sound (with Lam Sadashiva) — Excerpt",
        "the sky is superimposed with myriads of drones preparing to wipe humanity off the face of the earth (Extended Version)",
    ]
    /// Whether the live-show indicator shows: "off" unless TEST_RUNNER_LAYOUT_LIVE=on, so what is on
    /// air never changes a dump (a live show adds the indicator and moves the DJ name).
    private let liveShow = ProcessInfo.processInfo.environment["LAYOUT_LIVE"] == "on" ? "on" : "off"
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
        let useTestServer = ProcessInfo.processInfo.environment["LAYOUT_SERVER"] == "test"
        app.launchArguments = (useTestServer ? ["-stationServer", "test"] : [])
            + ["-nowPlayingDemoTitle", title, "-nowPlayingDemoLive", liveShow]
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

    private func rounded(_ value: CGFloat) -> String {
        let half = Double((value * 2).rounded() / 2)
        return half == half.rounded() ? String(Int(half)) : String(half)
    }

    private func line(_ role: String, _ frame: CGRect) -> String {
        [role, rounded(frame.minX), rounded(frame.minY), rounded(frame.width), rounded(frame.height)]
            .joined(separator: " ")
    }

    private var deviceName: String {
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name
        return name.replacingOccurrences(of: " ", with: "_")
    }

    /// Dumps the elements in a fixed order. A missing element fails the test and is left out.
    @MainActor private func dumpFrames(title: String, orientation: String, titleNumber: Int) {
        var lines: [String] = []

        func add(_ role: String, _ element: XCUIElement) {
            guard element.waitForExistence(timeout: 20) else {
                XCTFail("\(orientation) title\(titleNumber): the \(role) element never appeared")
                return
            }
            lines.append(line(role, element.frame))
        }

        add("window", app.windows.firstMatch)
        add("title", app.staticTexts[title])
        add("artist", app.staticTexts[artist])
        add("album", app.staticTexts[album])
        add("dj", app.staticTexts[dj])
        add("slider", app.sliders.firstMatch)
        add("playPauseButton", app.buttons["playPauseButton"])
        add("infoButton", app.buttons["infoButton"])
        add("albumArt", app.descendants(matching: .any)["albumArt"])

        // Every other button, by identifier or label, in screen order.
        let known: Set<String> = ["playPauseButton", "infoButton"]
        var others: [(String, CGRect)] = []
        for button in app.buttons.allElementsBoundByIndex where button.exists {
            let role = button.identifier.isEmpty ? button.label : button.identifier
            if known.contains(role) { continue }
            others.append((role.isEmpty ? "button" : role, button.frame))
        }
        others.sort { ($0.1.minY, $0.1.minX, $0.0) < ($1.1.minY, $1.1.minX, $1.0) }
        for (role, frame) in others { lines.append(line("button:" + role, frame)) }

        let name = "\(deviceName)-\(orientation)-title\(titleNumber)"
        let env = ProcessInfo.processInfo.environment
        if let dir = env["LAYOUT_BASELINE_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let text = lines.joined(separator: "\n") + "\n"
            try? text.write(toFile: dir + "/" + name + ".txt", atomically: true, encoding: .utf8)
        }
        if let dir = env["LAYOUT_SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let shot = app.windows.firstMatch.screenshot()
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
        }
    }

    // MARK: Tests

    @MainActor func testDumpPortraitFrames() {
        for (index, title) in titles.enumerated() {
            openNowPlaying(title: title)
            rotate(to: .portrait)
            dumpFrames(title: title, orientation: "portrait", titleNumber: index + 1)
        }
    }

    @MainActor func testDumpLandscapeFrames() {
        for (index, title) in titles.enumerated() {
            openNowPlaying(title: title)
            rotate(to: .landscapeLeft)
            dumpFrames(title: title, orientation: "landscape", titleNumber: index + 1)
        }
    }
}
