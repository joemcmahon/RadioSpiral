//
//  DemoLiveShowTests.swift
//  ConfigClientTests
//
//  One subject: the Debug-only launch argument `-nowPlayingDemoLive on|off` that lets a UI test
//  decide whether Now Playing shows the live-show indicator, whatever is on air. Without a
//  recognised value the station's own live-show state decides, as it does for listeners.
//

import XCTest
@testable import RadioSpiral

final class DemoLiveShowTests: XCTestCase {

    func testNoOverrideFollowsTheStation() {
        XCTAssertFalse(DemoLiveShow.indicatorHidden(isLiveDJ: true, override: nil))
        XCTAssertTrue(DemoLiveShow.indicatorHidden(isLiveDJ: false, override: nil))
    }

    func testOnShowsTheIndicatorWhateverIsOnAir() {
        XCTAssertFalse(DemoLiveShow.indicatorHidden(isLiveDJ: false, override: "on"))
        XCTAssertFalse(DemoLiveShow.indicatorHidden(isLiveDJ: true, override: "on"))
    }

    func testOffHidesTheIndicatorWhateverIsOnAir() {
        XCTAssertTrue(DemoLiveShow.indicatorHidden(isLiveDJ: true, override: "off"))
        XCTAssertTrue(DemoLiveShow.indicatorHidden(isLiveDJ: false, override: "off"))
    }

    func testAnUnrecognisedValueIsIgnored() {
        XCTAssertFalse(DemoLiveShow.indicatorHidden(isLiveDJ: true, override: "maybe"))
        XCTAssertTrue(DemoLiveShow.indicatorHidden(isLiveDJ: false, override: ""))
    }
}
