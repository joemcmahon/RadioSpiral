//
//  AppFontTests.swift
//  ConfigClientTests
//
//  The display font (Zen Dots) used for big, short, high-impact text: the song title, the artist
//  line, and channel names. Body text, captions, the connection banner and the time bubble stay
//  in the system font. The tests run inside the app, so the font file is registered by the app's
//  Info.plist, exactly as on a device.
//

import XCTest
@testable import RadioSpiral

final class AppFontTests: XCTestCase {

    private let large = UITraitCollection(preferredContentSizeCategory: .large)
    private let huge = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)

    func testDisplayFontIsZenDots() {
        let font = AppFont.display(.title1, compatibleWith: large)
        XCTAssertEqual(font.fontName, "ZenDots-Regular")
        XCTAssertEqual(font.familyName, "Zen Dots")
    }

    func testDisplayFontStartsAtTheSystemSizeForTheStyle() {
        for style: UIFont.TextStyle in [.title1, .title3, .headline] {
            let system = UIFont.preferredFont(forTextStyle: style, compatibleWith: large)
            XCTAssertEqual(AppFont.display(style, compatibleWith: large).pointSize, system.pointSize,
                           "\(style.rawValue) should start at the system size")
        }
    }

    func testDisplayFontGrowsWithDynamicType() {
        let normal = AppFont.display(.title3, compatibleWith: large).pointSize
        let bigger = AppFont.display(.title3, compatibleWith: huge).pointSize
        XCTAssertGreaterThan(bigger, normal)
    }

    func testMissingFontFallsBackToTheSystemFontForTheStyle() {
        let font = AppFont.display(.title1, fontName: "NoSuchFont-Regular", compatibleWith: large)
        let system = UIFont.preferredFont(forTextStyle: .title1, compatibleWith: large)
        XCTAssertEqual(font.fontName, system.fontName)
        XCTAssertEqual(font.pointSize, system.pointSize)
    }

    /// The nav-bar title on Now Playing (the channel name). A title view, so only that screen
    /// changes: the nav bar's font is shared by every screen.
    func testTitleLabelShowsTheTextInTheDisplayFontAndShrinksToFit() {
        let label = AppFont.titleLabel("Inner Sanctum")
        XCTAssertEqual(label.text, "Inner Sanctum")
        XCTAssertEqual(label.font.fontName, "ZenDots-Regular")
        XCTAssertTrue(label.adjustsFontSizeToFitWidth)
        XCTAssertLessThan(label.minimumScaleFactor, 1)
        XCTAssertEqual(label.textColor, .white)
        XCTAssertTrue(label.accessibilityTraits.contains(.header))
    }

    func testTitleLabelWithNoTextIsEmpty() {
        XCTAssertEqual(AppFont.titleLabel(nil).text ?? "", "")
    }

    // MARK: - Large title (the channel list's "RadioSpiral streams")

    /// A large title can't wrap or shrink by itself, so its font is sized to the width.
    func testLargeTitleFitsOnOneLineInTheWidth() {
        let text = "RadioSpiral streams"
        let font = AppFont.largeTitle(text, fitting: 300, compatibleWith: large)
        XCTAssertEqual(font.fontName, "ZenDots-Regular")
        XCTAssertEqual(TitleFit.lineCount(of: text, font: font, width: 300), 1)
    }

    func testLargeTitleThatAlreadyFitsKeepsTheFullSize() {
        let full = AppFont.display(.largeTitle, compatibleWith: large).pointSize
        let font = AppFont.largeTitle("Hi", fitting: 600, compatibleWith: large)
        XCTAssertEqual(font.pointSize, full)
    }

    func testLargeTitleShrinksMoreInANarrowerWidth() {
        let text = "RadioSpiral streams"
        let wide = AppFont.largeTitle(text, fitting: 360, compatibleWith: large).pointSize
        let narrow = AppFont.largeTitle(text, fitting: 280, compatibleWith: large).pointSize
        XCTAssertLessThan(narrow, wide)
    }

    func testLargeTitleNeverGoesBelowTheMinimumTextSize() {
        let font = AppFont.largeTitle("RadioSpiral streams", fitting: 20, compatibleWith: large)
        XCTAssertGreaterThanOrEqual(font.pointSize, 10.9)
    }

    /// Shrinking a title to fit calls `withSize`, which must keep the family.
    func testShrinkingKeepsTheDisplayFont() {
        let shrunk = AppFont.display(.title1, compatibleWith: large).withSize(14)
        XCTAssertEqual(shrunk.fontName, "ZenDots-Regular")
        XCTAssertEqual(shrunk.pointSize, 14)
    }
}
