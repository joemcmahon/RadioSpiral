//
//  NowPlayingViewDirectionTests.swift
//  ConfigClientTests
//
//  The mini Now Playing bar fills its margins the same way in a left-to-right and a
//  right-to-left layout: its content stack sits 8 pt inside the layout margins on both sides.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class NowPlayingViewDirectionTests: XCTestCase {

    func testTheStackFillsTheViewTheSameWayInBothDirections() throws {
        let width: CGFloat = 402
        for attribute in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
            let bar = NowPlayingView()
            bar.frame = CGRect(x: 0, y: 0, width: width, height: 80)
            bar.semanticContentAttribute = attribute
            // Unequal margins, so a mix-up of the two sides cannot cancel out.
            bar.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 20)
            bar.layoutIfNeeded()

            let stack = try XCTUnwrap(bar.subviews.compactMap { $0 as? UIStackView }.first,
                                      "the content stack is a direct subview")
            let name = attribute == .forceLeftToRight ? "left to right" : "right to left"
            XCTAssertEqual(stack.frame.minX, bar.layoutMargins.left + 8, accuracy: 0.5, "\(name): left edge")
            XCTAssertEqual(stack.frame.maxX, width - bar.layoutMargins.right - 8, accuracy: 0.5, "\(name): right edge")
        }
    }
}
