//
//  NowPlayingSideInsetTests.swift
//  ConfigClientTests
//
//  Controls on the Now Playing screen keep their gap to a side safe-area inset (the Duo's
//  hinge side, a landscape notch). The inset is simulated with `additionalSafeAreaInsets`.
//  Run on an iPhone simulator.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class NowPlayingSideInsetTests: XCTestCase {

    private let portraitSize = CGSize(width: 402, height: 874)

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    /// Now Playing in a window of the given size, laid out once.
    private func makeNowPlaying(size: CGSize) throws -> NowPlayingViewController {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let controller = Storyboard.viewController as NowPlayingViewController
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return controller
    }

    private func letLayoutSettle() {
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
    }

    private func findInfoButton(in controller: NowPlayingViewController) throws -> UIView {
        func descendants(_ view: UIView) -> [UIView] { view.subviews + view.subviews.flatMap(descendants) }
        return try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "infoButton" })
    }

    // MARK: - Portrait info button

    func testTheInfoButtonKeepsItsGapToASideInsetInPortrait() throws {
        let controller = try makeNowPlaying(size: portraitSize)
        let button = try findInfoButton(in: controller)

        let before = button.convert(button.bounds, to: controller.view).minX
        XCTAssertEqual(before, 20, accuracy: 0.5, "no inset: the 20 pt gap from the constraint")

        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 0)
        letLayoutSettle()

        let after = button.convert(button.bounds, to: controller.view).minX
        XCTAssertEqual(after, 50, accuracy: 0.5, "a 30 pt side inset moves the button in by 30")
    }
}
