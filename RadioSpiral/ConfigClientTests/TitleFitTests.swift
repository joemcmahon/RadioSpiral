//
//  TitleFitTests.swift
//  ConfigClientTests
//
//  Fitting a track title into a given width and number of lines by shrinking its font, never
//  below the iOS minimum text size of 11 pt (Human Interface Guidelines, Typography).
//  Fonts are fixed sizes, not Dynamic Type, so the results don't depend on the test device's
//  settings.
//

import XCTest
@testable import RadioSpiral

final class TitleFitTests: XCTestCase {

    private let font = UIFont.systemFont(ofSize: 28)   // Title 1 at the default size
    private let width: CGFloat = 400

    private let long = "Puja in the Temple of Sound (with Lam Sadashiva) — Excerpt"
    private let outlier = "the sky is superimposed with myriads of drones preparing to wipe humanity off the face of the earth (Extended Version)"

    private func lines(_ text: String, scale: CGFloat, width: CGFloat? = nil) -> Int {
        TitleFit.lineCount(of: text, font: font.withSize(font.pointSize * scale), width: width ?? self.width)
    }

    func testAShortTitleKeepsFullSize() {
        XCTAssertEqual(TitleFit.scale(for: "Short", font: font, width: width, maxLines: 2), 1.0)
    }

    func testAnEmptyTitleKeepsFullSize() {
        XCTAssertEqual(TitleFit.scale(for: "", font: font, width: width, maxLines: 2), 1.0)
    }

    func testATitleThatFitsInTwoLinesIsNotShrunk() {
        XCTAssertLessThanOrEqual(lines(long, scale: 1.0), 2, "fixture: the title must fit at full size")
        XCTAssertEqual(TitleFit.scale(for: long, font: font, width: width, maxLines: 2), 1.0)
    }

    func testATooLongTitleShrinksUntilItFitsTheLines() {
        XCTAssertGreaterThan(lines(outlier, scale: 1.0), 2, "fixture: the title must not fit at full size")
        let scale = TitleFit.scale(for: outlier, font: font, width: width, maxLines: 2)
        XCTAssertLessThan(scale, 1.0)
        XCTAssertLessThanOrEqual(lines(outlier, scale: scale), 2)
    }

    func testItDoesNotShrinkMoreThanNeeded() {
        let scale = TitleFit.scale(for: outlier, font: font, width: width, maxLines: 2)
        // A slightly larger size no longer fits (the search steps by about 1%).
        XCTAssertGreaterThan(lines(outlier, scale: scale + 0.03), 2)
    }

    func testNeverGoesBelowTheMinimumTextSize() {
        let absurd = String(repeating: "drone ", count: 300)
        let scale = TitleFit.scale(for: absurd, font: font, width: 120, maxLines: 2, minPoints: 11)
        XCTAssertGreaterThanOrEqual(font.pointSize * scale, 11 - 0.01)
        XCTAssertLessThanOrEqual(font.pointSize * scale, 11 + 0.3, "an impossible title settles at the floor")
    }

    func testWiderSpaceNeverShrinksMore() {
        let narrow = TitleFit.scale(for: outlier, font: font, width: 300, maxLines: 2)
        let wide = TitleFit.scale(for: outlier, font: font, width: 500, maxLines: 2)
        XCTAssertGreaterThanOrEqual(wide, narrow)
    }

    func testOneLineNeedsAtLeastAsMuchShrinkingAsTwo() {
        let one = TitleFit.scale(for: long, font: font, width: width, maxLines: 1)
        let two = TitleFit.scale(for: long, font: font, width: width, maxLines: 2)
        XCTAssertLessThanOrEqual(one, two)
        XCTAssertLessThanOrEqual(lines(long, scale: one), 1)
    }

    func testLineCountOfOneWordIsOne() {
        XCTAssertEqual(TitleFit.lineCount(of: "Excerpt", font: font, width: width), 1)
    }

    /// Not an assertion: Xcode reports the average time of a hundred fits of the outlier title,
    /// so a slowdown shows up. The fit runs once per track change.
    func testTimingOfAFitIsSmall() {
        measure {
            for _ in 0..<100 {
                _ = TitleFit.scale(for: outlier, font: font, width: width, maxLines: 2)
            }
        }
    }

    func testAZeroWidthDoesNotCrashAndSettlesAtTheFloor() {
        let scale = TitleFit.scale(for: long, font: font, width: 0, maxLines: 2, minPoints: 11)
        XCTAssertEqual(font.pointSize * scale, 11, accuracy: 0.3)
    }
}
