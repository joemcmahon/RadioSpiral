//
//  NowPlayingRotationUITests.swift
//  RadioSpiralUITests
//
//  One subject: Now Playing lays out the same way after a rotation as it does after a fresh
//  launch in that orientation. A large phone changes size class when it rotates (regular width
//  in landscape, compact in portrait), so a layout read from stale size classes in the middle
//  of a rotation would stay wrong until something else triggered a layout.
//
//  Live, like NowPlayingFrameBaselineUITests: it needs GitHub and the production server (one
//  station, so Now Playing opens directly) and uses the Debug-only `-nowPlayingDemoTitle`
//  launch argument. Run it by hand on a large phone (iPhone 18 Pro Max, iPhone Air) and on
//  one that doesn't change size class (iPhone 17).
//

import XCTest

final class NowPlayingRotationUITests: XCTestCase {

    private let app = XCUIApplication()

    /// A short title, and the longest of the baseline's titles (it wraps differently in landscape).
    private let titles = [
        "Sunrise",
        "the sky is superimposed with myriads of drones preparing to wipe humanity off the face of the earth (Extended Version)",
    ]
    /// Whether the live-show indicator shows: "off" unless TEST_RUNNER_LAYOUT_LIVE=on, so what is on
    /// air never changes a dump (a live show adds the indicator and moves the DJ name).
    private let liveShow = ProcessInfo.processInfo.environment["LAYOUT_LIVE"] == "on" ? "on" : "off"
    private let artist = "Demo Artist"
    private let album = "Demo Album (2006-2023)"

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

    @MainActor private func launchNowPlaying(title: String) {
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

    /// The frames that carry the layout: art, text, slider, play button and the window itself.
    @MainActor private func frames(title: String) -> [String: CGRect] {
        let elements: [(String, XCUIElement)] = [
            ("window", app.windows.firstMatch),
            ("title", app.staticTexts[title]),
            ("artist", app.staticTexts[artist]),
            ("album", app.staticTexts[album]),
            ("slider", app.sliders.firstMatch),
            ("playPauseButton", app.buttons["playPauseButton"]),
            ("albumArt", app.descendants(matching: .any)["albumArt"]),
        ]
        var result: [String: CGRect] = [:]
        for (role, element) in elements {
            XCTAssertTrue(element.waitForExistence(timeout: 20), "the \(role) element never appeared")
            result[role] = element.frame
        }
        return result
    }

    private func assertSameLayout(_ actual: [String: CGRect], _ expected: [String: CGRect],
                                  _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        for (role, frame) in expected.sorted(by: { $0.key < $1.key }) {
            guard let other = actual[role] else { continue }
            let same = abs(frame.minX - other.minX) <= 0.5 && abs(frame.minY - other.minY) <= 0.5
                && abs(frame.width - other.width) <= 0.5 && abs(frame.height - other.height) <= 0.5
            XCTAssertTrue(same, "\(context): \(role) is \(other), expected \(frame)", file: file, line: line)
        }
    }

    // MARK: Tests

    /// Portrait, landscape, portrait, landscape: each orientation matches its first appearance.
    @MainActor func testRotatingBackAndForthRepeatsTheSameLayouts() {
        for title in titles {
            launchNowPlaying(title: title)
            rotate(to: .portrait)
            let portrait = frames(title: title)
            rotate(to: .landscapeLeft)
            let landscape = frames(title: title)
            rotate(to: .portrait)
            assertSameLayout(frames(title: title), portrait, "portrait again (\(title.prefix(12)))")
            rotate(to: .landscapeLeft)
            assertSameLayout(frames(title: title), landscape, "landscape again (\(title.prefix(12)))")
        }
    }

    /// A launch in landscape gives what a rotation into landscape gives.
    @MainActor func testLaunchingInLandscapeMatchesRotatingIntoIt() {
        for title in titles {
            launchNowPlaying(title: title)
            rotate(to: .landscapeLeft)
            let rotated = frames(title: title)

            app.terminate()
            rotate(to: .landscapeLeft)
            launchNowPlaying(title: title)
            assertSameLayout(frames(title: title), rotated, "fresh landscape launch (\(title.prefix(12)))")
        }
    }
}
