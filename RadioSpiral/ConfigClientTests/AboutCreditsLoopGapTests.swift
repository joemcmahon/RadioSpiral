//
//  AboutCreditsLoopGapTests.swift
//  ConfigClientTests
//
//  The credits roll continuously: when one pass ends, the next begins right below it. A little
//  space between the last credit of one pass and the first of the next tells the listener that a
//  new pass is starting. Run on an iPhone simulator; landscape is used because its credits
//  overflow, so both passes are shown.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class AboutCreditsLoopGapTests: XCTestCase {

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    func testThereIsRoomBetweenTheEndOfOnePassAndTheStartOfTheNext() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let about = AboutViewController()
        about.traitOverrides.verticalSizeClass = .compact
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        window.rootViewController = about
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()

        let scrolls = allSubviews(of: about.view).compactMap { $0 as? UIScrollView }
        let scroll = try XCTUnwrap(scrolls.first { scroll in
            allSubviews(of: scroll).contains { ($0 as? UILabel)?.text?.hasPrefix("Based on Swift Radio Pro") == true }
        })
        // The first tick, which the display link delivers within a frame of the screen appearing.
        about.scrollCredits()
        let attributions = allSubviews(of: scroll).compactMap { $0 as? UILabel }
            .filter { $0.text?.hasPrefix("Based on Swift Radio Pro") == true && !$0.isHidden }
        XCTAssertEqual(attributions.count, 2, "harness: both passes are shown")
        let firstPassEnd = try XCTUnwrap(attributions.map { $0.convert($0.bounds, to: scroll).maxY }.min())

        // creditsLoopLength is where the next pass starts, in the scroll view's coordinates.
        let gap = about.creditsLoopLength - firstPassEnd
        XCTAssertGreaterThanOrEqual(gap, 60, "room below the last credit before the next pass starts")
    }
}
