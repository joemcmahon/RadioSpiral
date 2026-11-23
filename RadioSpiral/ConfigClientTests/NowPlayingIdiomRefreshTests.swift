//
//  NowPlayingIdiomRefreshTests.swift
//  ConfigClientTests
//
//  Now Playing picks its layout and label scale partly from the idiom (a phone-idiom screen of
//  the Duo's inner-display shape gets the fold layout). The layout is applied once per
//  (layout, size, metrics) and kept, so it has to be applied again when the idiom changes
//  even if the size and the size classes stay the same.
//
//  The first test is the control: it shows this harness delivers a trait change to the screen
//  (it flips the size classes, which Now Playing already watches). Run on an iPhone simulator.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class NowPlayingIdiomRefreshTests: XCTestCase {

    /// The Duo's inner display, portrait, in points.
    private let foldSize = CGSize(width: 669, height: 951)
    /// An ordinary phone, portrait (the iPhone 17).
    private let phoneSize = CGSize(width: 402, height: 874)

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Now Playing in a window of the given size, laid out once.
    private func nowPlaying(in size: CGSize) throws -> NowPlayingViewController {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let controller = Storyboard.viewController as NowPlayingViewController
        window = try TestWindow.make(size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return controller
    }

    private func letTraitChangesSettle(_ window: UIWindow) {
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
    }

    /// Control. On a plain phone-sized screen, regular size classes in both directions give the
    /// layout the 1.4x scale, so the song label grows. If this fails, the harness is not
    /// delivering trait changes and the idiom test below proves nothing.
    func testTheLayoutAppliesAgainWhenTheSizeClassesChange() throws {
        let controller = try nowPlaying(in: phoneSize)
        let before = controller.songLabel.font.pointSize

        controller.traitOverrides.horizontalSizeClass = .regular
        controller.traitOverrides.verticalSizeClass = .regular
        letTraitChangesSettle(window)

        XCTAssertEqual(controller.traitCollection.horizontalSizeClass, .regular)
        XCTAssertEqual(controller.traitCollection.verticalSizeClass, .regular)
        XCTAssertGreaterThan(controller.songLabel.font.pointSize, before,
                             "regular size classes should scale the song label up")
    }

    /// The break this catches: the idiom changes, the size and the size classes do not, and the
    /// screen keeps the layout it chose for the old idiom. A phone-idiom screen of the Duo's
    /// shape gets the fold layout (label scale 1.35); the same screen as a pad does not (1.0
    /// times the metrics' scale), so the song label's font size has to change.
    func testTheLayoutAppliesAgainWhenOnlyTheIdiomChanges() throws {
        let controller = try nowPlaying(in: foldSize)
        let foldFont = controller.songLabel.font.pointSize
        let classesBefore = (controller.traitCollection.horizontalSizeClass,
                             controller.traitCollection.verticalSizeClass)

        controller.traitOverrides.userInterfaceIdiom = .pad
        letTraitChangesSettle(window)

        XCTAssertEqual(controller.traitCollection.userInterfaceIdiom, .pad)
        XCTAssertEqual(controller.traitCollection.horizontalSizeClass, classesBefore.0)
        XCTAssertEqual(controller.traitCollection.verticalSizeClass, classesBefore.1)
        XCTAssertNotEqual(controller.songLabel.font.pointSize, foldFont,
                          "the fold layout should be replaced once the screen is no longer a phone")
    }
}

/// The iOS 16 fallback (traitCollectionDidChange) decides what changed with these comparisons;
/// the iOS 17 registrations name the same traits. The fallback itself only runs on iOS 16, which
/// no simulator here has, so the comparisons are checked directly: each trait the screens react
/// to must count, and one they don't react to must not.
@MainActor
final class TraitChangeComparisonTests: XCTestCase {

    private let base = UITraitCollection(traitsFrom: [
        UITraitCollection(horizontalSizeClass: .compact),
        UITraitCollection(verticalSizeClass: .regular),
        UITraitCollection(userInterfaceIdiom: .phone),
        UITraitCollection(displayScale: 3),
    ])

    private func changing(_ trait: UITraitCollection) -> UITraitCollection {
        UITraitCollection(traitsFrom: [base, trait])
    }

    func testTheLayoutCountsEachSizeClassAndTheIdiom() {
        let layoutChanged = NowPlayingViewController.layoutTraitsChanged(from:to:)
        XCTAssertTrue(layoutChanged(base, changing(UITraitCollection(horizontalSizeClass: .regular))))
        XCTAssertTrue(layoutChanged(base, changing(UITraitCollection(verticalSizeClass: .compact))))
        XCTAssertTrue(layoutChanged(base, changing(UITraitCollection(userInterfaceIdiom: .pad))))
    }

    func testTheLayoutIgnoresTraitsItDoesNotReadAndNoChange() {
        let layoutChanged = NowPlayingViewController.layoutTraitsChanged(from:to:)
        XCTAssertFalse(layoutChanged(base, base))
        XCTAssertFalse(layoutChanged(base, changing(UITraitCollection(displayScale: 2))))
        XCTAssertFalse(layoutChanged(base, changing(UITraitCollection(preferredContentSizeCategory: .extraLarge))))
    }

    func testTheArtworkCountsOnlyTheDisplayScale() {
        let scaleChanged = NowPlayingViewController.displayScaleChanged(from:to:)
        XCTAssertTrue(scaleChanged(base, changing(UITraitCollection(displayScale: 2))))
        XCTAssertFalse(scaleChanged(base, base))
        XCTAssertFalse(scaleChanged(base, changing(UITraitCollection(horizontalSizeClass: .regular))))
    }

    func testTheStationColumnsCountOnlyTheHorizontalSizeClass() {
        let columnsChanged = StationsViewController.columnTraitsChanged(from:to:)
        XCTAssertTrue(columnsChanged(base, changing(UITraitCollection(horizontalSizeClass: .regular))))
        XCTAssertFalse(columnsChanged(base, base))
        XCTAssertFalse(columnsChanged(base, changing(UITraitCollection(verticalSizeClass: .compact))))
        XCTAssertFalse(columnsChanged(base, changing(UITraitCollection(userInterfaceIdiom: .pad))))
    }
}
