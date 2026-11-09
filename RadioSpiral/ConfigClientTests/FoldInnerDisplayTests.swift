//
//  FoldInnerDisplayTests.swift
//  ConfigClientTests
//
//  Which screens Now Playing treats as the iPhone Duo's inner display (the wide fold layout and
//  the larger text). Sizes are in points, from the simulator device profiles: the Duo's inner
//  display is 2007 x 2853 px and its outer display 1398 x 2034 px, both at 3x; an iPhone 17 is
//  1206 x 2622 px at 3x.
//

import XCTest
@testable import RadioSpiral

final class FoldInnerDisplayTests: XCTestCase {

    private func isFold(_ width: CGFloat, _ height: CGFloat, isPhone: Bool = true) -> Bool {
        NowPlayingViewController.isFoldInnerDisplay(CGSize(width: width, height: height), isPhone: isPhone)
    }

    func testDuoInnerDisplayIsFoldInBothOrientations() {
        XCTAssertTrue(isFold(669, 951))
        XCTAssertTrue(isFold(951, 669))
    }

    func testDuoOuterDisplayIsNotFold() {
        XCTAssertFalse(isFold(466, 678))
        XCTAssertFalse(isFold(678, 466))
    }

    /// The bug: these are as long as the Duo's inner display, and were treated as one.
    func testLongSlabIPhonesAreNotFold() {
        XCTAssertFalse(isFold(402, 874), "iPhone 17 and 17 Pro")
        XCTAssertFalse(isFold(874, 402), "iPhone 17 landscape")
        XCTAssertFalse(isFold(420, 912), "iPhone Air")
        XCTAssertFalse(isFold(440, 956), "iPhone 17 Pro Max")
        XCTAssertFalse(isFold(956, 440), "iPhone 17 Pro Max landscape")
    }

    func testShorterIPhonesAreNotFold() {
        XCTAssertFalse(isFold(390, 844), "iPhone 13 Pro, the test phone")
        XCTAssertFalse(isFold(375, 667), "iPhone SE")
    }

    func testIPadIsNeverFold() {
        XCTAssertFalse(isFold(1032, 1376, isPhone: false))
        XCTAssertFalse(isFold(669, 951, isPhone: false))
    }

    func testAZeroSizeIsNotFold() {
        XCTAssertFalse(isFold(0, 0))
    }
}
