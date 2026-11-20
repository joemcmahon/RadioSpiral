//
//  AboutCreditsFitTests.swift
//  ConfigClientTests
//
//  The About credits roll only when they overflow the space they have. The loop needs a second
//  copy of the credits to wrap without a seam; when everything already fits (a tall iPad window),
//  a second copy would just show the credits and the attribution twice, so the credits stay still
//  and show once. Run on an iPhone simulator; the tall window stands in for an iPad.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class AboutCreditsFitTests: XCTestCase {

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func makeAbout(size: CGSize, compact: Bool) throws -> AboutViewController {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let controller = AboutViewController()
        if compact { controller.traitOverrides.verticalSizeClass = .compact }
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        settle()
        return controller
    }

    private func settle() {
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    /// The credits scroll view: the one that holds the attribution.
    private func creditsScroll(in about: AboutViewController) throws -> UIScrollView {
        let scrolls = allSubviews(of: about.view).compactMap { $0 as? UIScrollView }
        return try XCTUnwrap(scrolls.first { scroll in
            allSubviews(of: scroll).contains { ($0 as? UILabel)?.text?.hasPrefix("Based on Swift Radio Pro") == true }
        })
    }

    /// The attributions a listener can see: the loop's second copy is hidden when it is not used.
    private func shownAttributions(in about: AboutViewController) throws -> [UILabel] {
        allSubviews(of: try creditsScroll(in: about)).compactMap { $0 as? UILabel }
            .filter { $0.text?.hasPrefix("Based on Swift Radio Pro") == true && !$0.isHidden }
    }

    // MARK: - Everything fits

    func testCreditsThatFitAreShownOnceAndStayStill() throws {
        let about = try makeAbout(size: CGSize(width: 402, height: 1600), compact: false)
        let scroll = try creditsScroll(in: about)

        XCTAssertEqual(try shownAttributions(in: about).count, 1, "the attribution shows once")

        scroll.contentOffset.y = 0
        about.scrollCredits()
        about.scrollCredits()
        XCTAssertEqual(scroll.contentOffset.y, 0, "credits that fit do not scroll")
    }

    // MARK: - They overflow

    func testCreditsThatOverflowStillLoopWithBothCopies() throws {
        let about = try makeAbout(size: CGSize(width: 874, height: 402), compact: true)
        let scroll = try creditsScroll(in: about)

        // Harness check: the first copy really is taller than the space, or this proves nothing.
        let first = try XCTUnwrap(allSubviews(of: scroll).compactMap { $0 as? UILabel }
            .first { $0.text?.hasPrefix("Based on Swift Radio Pro") == true })
        XCTAssertGreaterThan(first.convert(first.bounds, to: scroll).maxY, scroll.bounds.height,
                             "harness: the credits overflow in this window")

        XCTAssertEqual(try shownAttributions(in: about).count, 2, "both copies are shown")

        // The credits hold still for a moment when they appear (AboutCreditsStartDelayTests).
        RunLoop.main.run(until: Date().addingTimeInterval(AboutViewController.startDelay + 0.3))
        scroll.contentOffset.y = 0
        about.scrollCredits()
        XCTAssertGreaterThan(scroll.contentOffset.y, 0, "credits that overflow scroll")
    }

    // MARK: - The window changes size

    func testResizingTheWindowSwitchesBetweenStillAndLooping() throws {
        let about = try makeAbout(size: CGSize(width: 402, height: 1600), compact: false)
        XCTAssertEqual(try shownAttributions(in: about).count, 1, "tall: shown once")

        window.frame = CGRect(x: 0, y: 0, width: 402, height: 560)
        settle()
        XCTAssertEqual(try shownAttributions(in: about).count, 2, "short: both copies, looping")

        window.frame = CGRect(x: 0, y: 0, width: 402, height: 1600)
        settle()
        XCTAssertEqual(try shownAttributions(in: about).count, 1, "tall again: shown once")
    }
}
