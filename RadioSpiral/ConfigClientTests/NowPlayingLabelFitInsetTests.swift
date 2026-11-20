//
//  NowPlayingLabelFitInsetTests.swift
//  ConfigClientTests
//
//  On a phone in landscape the Now Playing labels are shrunk to fit the room above the toolbar,
//  and that room starts below the top safe-area inset. The fit is remembered so it only reruns
//  when something it depends on changed; the top inset is one of those things. The inset is
//  simulated with `additionalSafeAreaInsets`. Run on an iPhone simulator.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class NowPlayingLabelFitInsetTests: XCTestCase {

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func makeLandscapeNowPlaying() throws -> NowPlayingViewController {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let controller = Storyboard.viewController as NowPlayingViewController
        // A phone in landscape has a compact height, which is what turns the label fit on.
        controller.traitOverrides.verticalSizeClass = .compact
        window = try TestWindow.make(size: CGSize(width: 874, height: 402))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        settle()
        XCTAssertEqual(controller.traitCollection.verticalSizeClass, .compact, "harness: compact height")
        return controller
    }

    private func settle() {
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
    }

    func testTheLabelsAreFittedAgainWhenTheTopInsetChanges() throws {
        let controller = try makeLandscapeNowPlaying()

        // Short text first: the labels keep their full size.
        controller.songLabel.text = "Short"
        controller.artistLabel.text = "Artist"
        controller.releaseLabel.text = "Release"
        settle()
        let fullSize = controller.songLabel.font.pointSize

        // A long title and long names: the fit has to shrink them. If it does not, the fit is not
        // active in this window and the rest proves nothing.
        let long = String(repeating: "A long title that needs room ", count: 3)
        controller.songLabel.text = long
        controller.artistLabel.text = long
        controller.releaseLabel.text = long
        settle()
        let fitted = controller.songLabel.font.pointSize
        XCTAssertLessThan(fitted, fullSize, "harness: the long text is shrunk to fit")
        XCTAssertGreaterThan(fitted, 11, "harness: not already at the 11 pt floor")

        // Less room above the toolbar: a top inset moves the panel's top down. The column width
        // and the toolbar do not move, so only the inset tells the fit that the room changed.
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 150, left: 0, bottom: 0, right: 0)
        settle()
        XCTAssertLessThan(controller.songLabel.font.pointSize, fitted,
                          "with less room the labels are shrunk further")
    }
}
