//
//  AboutCreditsStartDelayTests.swift
//  ConfigClientTests
//
//  The About credits wait a moment before they start to roll, so the first credit can be read
//  before it leaves the top of the view. Run on an iPhone simulator; landscape is used because
//  its credits overflow the space, so they roll (a tall window shows them still).
//

import XCTest
@testable import RadioSpiral

@MainActor
final class AboutCreditsStartDelayTests: XCTestCase {

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func makeLandscapeAbout() throws -> AboutViewController {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let controller = AboutViewController()
        controller.traitOverrides.verticalSizeClass = .compact
        window = try TestWindow.make(size: CGSize(width: 874, height: 402))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
        return controller
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private func creditsScroll(in about: AboutViewController) throws -> UIScrollView {
        let scrolls = allSubviews(of: about.view).compactMap { $0 as? UIScrollView }
        return try XCTUnwrap(scrolls.first { scroll in
            allSubviews(of: scroll).contains { ($0 as? UILabel)?.text?.hasPrefix("Based on Swift Radio Pro") == true }
        })
    }

    /// Harness check: these credits overflow, so that they would roll if nothing held them back.
    private func assertTheCreditsOverflow(_ scroll: UIScrollView) throws {
        let attribution = try XCTUnwrap(allSubviews(of: scroll).compactMap { $0 as? UILabel }
            .first { $0.text?.hasPrefix("Based on Swift Radio Pro") == true })
        XCTAssertGreaterThan(attribution.convert(attribution.bounds, to: scroll).maxY, scroll.bounds.height,
                             "harness: the credits overflow in this window")
    }

    func testTheCreditsHoldStillRightAfterTheScreenAppears() throws {
        let about = try makeLandscapeAbout()
        let scroll = try creditsScroll(in: about)
        try assertTheCreditsOverflow(scroll)

        scroll.contentOffset.y = 0
        about.scrollCredits()
        about.scrollCredits()
        XCTAssertEqual(scroll.contentOffset.y, 0, "the first credit stays put while it is read")
    }

    func testTheCreditsStartRollingAfterTheDelay() throws {
        let about = try makeLandscapeAbout()
        let scroll = try creditsScroll(in: about)

        RunLoop.main.run(until: Date().addingTimeInterval(AboutViewController.startDelay + 0.3))
        scroll.contentOffset.y = 0
        about.scrollCredits()
        XCTAssertGreaterThan(scroll.contentOffset.y, 0, "after the delay the credits roll")
    }

    /// A rebuild (rotation, or credits arriving late) puts the credits back at the top, so the
    /// first credit needs the same moment to be read again.
    func testARebuildHoldsTheCreditsStillAgain() throws {
        let about = try makeLandscapeAbout()
        RunLoop.main.run(until: Date().addingTimeInterval(AboutViewController.startDelay + 0.3))

        about.rebuildBody()
        window.layoutIfNeeded()
        let scroll = try creditsScroll(in: about)
        scroll.contentOffset.y = 0
        about.scrollCredits()
        XCTAssertEqual(scroll.contentOffset.y, 0, "after a rebuild the first credit is held again")
    }
}
