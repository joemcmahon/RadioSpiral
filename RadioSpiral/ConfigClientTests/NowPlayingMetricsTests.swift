//
//  NowPlayingMetricsTests.swift
//  ConfigClientTests
//
//  The Now Playing layout numbers, chosen from the screen's size classes instead of the device
//  idiom: a full-screen iPad gets the iPad values, a narrow iPad window gets the phone's, a large
//  phone in landscape takes only the values tied to a regular width, and the Duo's inner display
//  (found by its own check, `isFoldInner`) always keeps the phone values.
//

import XCTest
@testable import RadioSpiral

final class NowPlayingMetricsTests: XCTestCase {

    private func assertMetrics(
        _ metrics: NowPlayingMetrics,
        uiScale: CGFloat,
        portraitAlbumHeightFraction: CGFloat,
        landscapeArtBoxCentered: Bool,
        landscapeArtWidthFraction: CGFloat,
        landscapeSideMarginBase: CGFloat,
        fitsLabelsToPanel: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(metrics.uiScale, uiScale, "uiScale", file: file, line: line)
        XCTAssertEqual(metrics.portraitAlbumHeightFraction, portraitAlbumHeightFraction,
                       "portraitAlbumHeightFraction", file: file, line: line)
        XCTAssertEqual(metrics.landscapeArtBoxCentered, landscapeArtBoxCentered,
                       "landscapeArtBoxCentered", file: file, line: line)
        XCTAssertEqual(metrics.landscapeArtWidthFraction, landscapeArtWidthFraction,
                       "landscapeArtWidthFraction", file: file, line: line)
        XCTAssertEqual(metrics.landscapeSideMarginBase, landscapeSideMarginBase,
                       "landscapeSideMarginBase", file: file, line: line)
        XCTAssertEqual(metrics.fitsLabelsToPanel, fitsLabelsToPanel,
                       "fitsLabelsToPanel", file: file, line: line)
    }

    func testFullScreenIPad() {
        let metrics = NowPlayingMetrics(horizontal: .regular, vertical: .regular, isFoldInner: false)
        assertMetrics(metrics, uiScale: 1.4, portraitAlbumHeightFraction: 0.55,
                      landscapeArtBoxCentered: true, landscapeArtWidthFraction: 0.35,
                      landscapeSideMarginBase: 40, fitsLabelsToPanel: false)
    }

    /// A phone in portrait is compact x regular, the same as a narrow iPad window, so its landscape
    /// art box flag reads "centered" (vertical regular). The flag is only used by the landscape
    /// layout, so it has no effect in portrait; rotating re-reads the classes.
    func testPhonePortrait() {
        let metrics = NowPlayingMetrics(horizontal: .compact, vertical: .regular, isFoldInner: false)
        assertMetrics(metrics, uiScale: 1.0, portraitAlbumHeightFraction: 0.40,
                      landscapeArtBoxCentered: true, landscapeArtWidthFraction: 0.40,
                      landscapeSideMarginBase: 12, fitsLabelsToPanel: false)
    }

    func testPhoneLandscape() {
        let metrics = NowPlayingMetrics(horizontal: .compact, vertical: .compact, isFoldInner: false)
        assertMetrics(metrics, uiScale: 1.0, portraitAlbumHeightFraction: 0.40,
                      landscapeArtBoxCentered: false, landscapeArtWidthFraction: 0.40,
                      landscapeSideMarginBase: 12, fitsLabelsToPanel: true)
    }

    /// A large phone in landscape reports a regular width and a compact height: it takes the values
    /// tied to the width (portrait album height, art width, margin) and keeps the phone's scale,
    /// pinned art box and label fit.
    func testPlusMaxLandscapeTakesOnlyTheWidthValues() {
        let metrics = NowPlayingMetrics(horizontal: .regular, vertical: .compact, isFoldInner: false)
        assertMetrics(metrics, uiScale: 1.0, portraitAlbumHeightFraction: 0.55,
                      landscapeArtBoxCentered: false, landscapeArtWidthFraction: 0.35,
                      landscapeSideMarginBase: 40, fitsLabelsToPanel: true)
    }

    /// An iPad window as narrow as a phone's: phone numbers, except the art box is centered
    /// because the height is regular.
    func testNarrowIPadWindow() {
        let metrics = NowPlayingMetrics(horizontal: .compact, vertical: .regular, isFoldInner: false)
        assertMetrics(metrics, uiScale: 1.0, portraitAlbumHeightFraction: 0.40,
                      landscapeArtBoxCentered: true, landscapeArtWidthFraction: 0.40,
                      landscapeSideMarginBase: 12, fitsLabelsToPanel: false)
    }

    func testFoldInnerIsAlwaysPhone() {
        let combinations: [(UIUserInterfaceSizeClass, UIUserInterfaceSizeClass)] = [
            (.regular, .regular), (.compact, .regular), (.regular, .compact),
        ]
        for (horizontal, vertical) in combinations {
            let metrics = NowPlayingMetrics(horizontal: horizontal, vertical: vertical, isFoldInner: true)
            XCTAssertEqual(metrics, .phone, "fold inner display, \(horizontal.rawValue) x \(vertical.rawValue)")
        }
    }

    func testUnspecifiedIsNeverRegular() {
        let metrics = NowPlayingMetrics(horizontal: .unspecified, vertical: .unspecified, isFoldInner: false)
        assertMetrics(metrics, uiScale: 1.0, portraitAlbumHeightFraction: 0.40,
                      landscapeArtBoxCentered: false, landscapeArtWidthFraction: 0.40,
                      landscapeSideMarginBase: 12, fitsLabelsToPanel: false)
    }
}
