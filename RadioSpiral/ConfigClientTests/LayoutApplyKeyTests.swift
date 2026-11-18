//
//  LayoutApplyKeyTests.swift
//  ConfigClientTests
//
//  The key that decides whether Now Playing's layout needs applying again. A trait change that
//  leaves the layout and the size alone (an iPad window whose size classes change, a split
//  that moves a size across a class boundary) must still produce a different key.
//

import XCTest
@testable import RadioSpiral

final class LayoutApplyKeyTests: XCTestCase {

    private let size = CGSize(width: 874, height: 402)
    private let phone = NowPlayingMetrics.phone
    private let ipad = NowPlayingMetrics(horizontal: .regular, vertical: .regular, isFoldInner: false)

    func testKeysAreEqualWhenLayoutSizeAndMetricsMatch() {
        XCTAssertEqual(LayoutApplyKey(layout: .landscape, size: size, metrics: phone),
                       LayoutApplyKey(layout: .landscape, size: size, metrics: phone))
    }

    func testKeysDifferWhenOnlyTheMetricsDiffer() {
        XCTAssertNotEqual(LayoutApplyKey(layout: .landscape, size: size, metrics: phone),
                          LayoutApplyKey(layout: .landscape, size: size, metrics: ipad))
    }

    func testKeysDifferWhenOnlyTheSizeDiffers() {
        XCTAssertNotEqual(LayoutApplyKey(layout: .landscape, size: size, metrics: phone),
                          LayoutApplyKey(layout: .landscape, size: CGSize(width: 874, height: 403), metrics: phone))
    }

    func testKeysDifferWhenOnlyTheLayoutDiffers() {
        XCTAssertNotEqual(LayoutApplyKey(layout: .landscape, size: size, metrics: phone),
                          LayoutApplyKey(layout: .portrait, size: size, metrics: phone))
    }
}
