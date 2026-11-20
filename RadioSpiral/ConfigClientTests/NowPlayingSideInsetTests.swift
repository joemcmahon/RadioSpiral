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

    // MARK: - Tools View, every layout

    /// The Tools View's edges in the controller's view: the gap on each side.
    private func toolsGaps(_ controller: NowPlayingViewController) -> (leading: CGFloat, trailing: CGFloat) {
        let frame = controller.toolsView.convert(controller.toolsView.bounds, to: controller.view)
        return (frame.minX, controller.view.bounds.width - frame.maxX)
    }

    /// Its trailing edge is pinned to the root view's trailing margin, and the Tools View is active
    /// in every layout (it has no outlet and is not in the portrait set that gets deactivated). The
    /// margins already include the safe-area inset, so the toolbar keeps its gap to a side inset on
    /// both sides today; this records that, per layout, with measured values. The no-inset gaps
    /// differ by layout (16 in portrait, 20 in landscape and on the Duo) because the root view's
    /// margins do.
    func testTheToolsViewKeepsItsGapToSideInsetsInEveryLayout() throws {
        // (name, window size, inset each side, gaps with no inset, gaps with the inset)
        let cases: [(String, CGSize, CGFloat, (CGFloat, CGFloat), (CGFloat, CGFloat))] = [
            ("portrait", CGSize(width: 402, height: 874), 30, (20, 16), (50, 46)),
            ("landscape", CGSize(width: 874, height: 402), 62, (20, 20), (82, 82)),
            ("foldWide", CGSize(width: 951, height: 669), 62, (20, 20), (82, 82)),
        ]
        for (name, size, inset, plain, inset2) in cases {
            window?.isHidden = true
            let controller = try makeNowPlaying(size: size)
            letLayoutSettle()

            // Harness check: the layout asked for is the layout applied. Portrait has a one-line
            // song title; landscape and foldWide two lines; foldWide puts the info button 10 pt
            // left of the Tools View's edge (the left half's edge), landscape flush with it.
            let button = try findInfoButton(in: controller)
            let buttonX = button.convert(button.bounds, to: controller.view).minX
            let toolsX = toolsGaps(controller).leading
            switch name {
            case "portrait":
                XCTAssertEqual(controller.songLabel.numberOfLines, 1, "harness: portrait layout")
            case "landscape":
                XCTAssertEqual(controller.songLabel.numberOfLines, 2, "harness: landscape layout")
                XCTAssertEqual(buttonX, toolsX, accuracy: 0.5, "harness: landscape layout")
            default:
                XCTAssertEqual(controller.songLabel.numberOfLines, 2, "harness: foldWide layout")
                XCTAssertEqual(buttonX, toolsX - 10, accuracy: 0.5, "harness: foldWide layout")
            }

            let none = toolsGaps(controller)
            XCTAssertEqual(none.leading, plain.0, accuracy: 0.5, "\(name): leading gap, no inset")
            XCTAssertEqual(none.trailing, plain.1, accuracy: 0.5, "\(name): trailing gap, no inset")

            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            letLayoutSettle()

            let with = toolsGaps(controller)
            XCTAssertEqual(with.leading, inset2.0, accuracy: 0.5, "\(name): leading gap, \(inset) pt inset")
            XCTAssertEqual(with.trailing, inset2.1, accuracy: 0.5, "\(name): trailing gap, \(inset) pt inset")
            XCTAssertEqual(with.trailing - none.trailing, inset, accuracy: 0.5,
                           "\(name): the trailing gap grows by exactly the inset")
        }
    }
}
