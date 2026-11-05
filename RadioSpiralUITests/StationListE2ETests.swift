//
//  StationListE2ETests.swift
//  RadioSpiralUITests
//
//  A cold launch against the test server, which lists several stations: the list appears,
//  choosing a station opens Now Playing for that station, and the play button changes state.
//  Live: needs network, GitHub and the test server. Plays real audio for a few seconds.
//

import XCTest

final class StationListE2ETests: XCTestCase {

    private let app = XCUIApplication()

    private var stationCells: XCUIElementQuery { app.collectionViews.cells }
    private var playPauseButton: XCUIElement { app.buttons["playPauseButton"] }

    @MainActor override func setUp() {
        super.setUp()
        continueAfterFailure = false
        // The argument lands in UserDefaults, where StationServer reads the tester's choice.
        // Debug builds honor it; production would list one station and skip the list.
        app.launchArguments += ["-stationServer", "test"]
        app.launch()
    }

    @MainActor override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    /// Waits for the list to show at least two stations. Not an exact count, so the test
    /// server can change.
    @MainActor private func waitForStationList() {
        XCTAssertTrue(stationCells.element(boundBy: 1).waitForExistence(timeout: 30),
                      "The station list never showed two stations")
    }

    @MainActor private func wait(for element: XCUIElement, isSelected: Bool, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isSelected == %@", NSNumber(value: isSelected))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor func testColdLaunchShowsSeveralStationsFromTheTestServer() {
        waitForStationList()
        XCTAssertGreaterThanOrEqual(stationCells.count, 2)
        // Shown only when the test server is really the one in use.
        XCTAssertTrue(app.staticTexts["TEST SERVER"].exists)
        XCTAssertFalse(playPauseButton.exists, "A cold launch stops at the list")
    }

    /// Chooses the second station, so a list that always opened the first would fail.
    @MainActor func testChoosingAStationOpensNowPlayingForThatStation() {
        waitForStationList()
        let cell = stationCells.element(boundBy: 1)
        let chosenName = cell.staticTexts.element(boundBy: 0).label
        XCTAssertFalse(chosenName.isEmpty)

        cell.tap()

        XCTAssertTrue(playPauseButton.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.staticTexts[chosenName].waitForExistence(timeout: 5),
                      "Now Playing's title isn't the chosen station, \(chosenName)")
    }

    /// Choosing a station leaves the phone waiting for play, by design. The button then
    /// follows the player: selected while playing, not selected once stopped.
    @MainActor func testPlayButtonChangesStateWhenPressed() {
        waitForStationList()
        stationCells.element(boundBy: 1).tap()
        XCTAssertTrue(playPauseButton.waitForExistence(timeout: 10))
        XCTAssertFalse(playPauseButton.isSelected, "The phone waits for play after choosing")

        playPauseButton.tap()
        XCTAssertTrue(wait(for: playPauseButton, isSelected: true, timeout: 30),
                      "The button never showed playing")

        // The reconnect that follows choosing a station can briefly interrupt audio started
        // before it finishes (task-32), so let it pass before pressing stop.
        sleep(8)
        XCTAssertTrue(playPauseButton.isSelected, "Still playing after the reconnect")

        playPauseButton.tap()
        XCTAssertTrue(wait(for: playPauseButton, isSelected: false, timeout: 10),
                      "The button never showed stopped")
    }
}
