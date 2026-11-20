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
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
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
