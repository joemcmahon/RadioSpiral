//
//  AboutScreenHeaderTests.swift
//  ConfigClientTests
//
//  The About screen's header and scrolling credits. These tests capture how the screen behaves
//  today: portrait keeps the attribution fixed below the credits, landscape rolls the generic
//  blurb, the credits and the attribution together, and the header shows the current station.
//  Run on an iPhone simulator.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class AboutScreenHeaderTests: XCTestCase {

    private let portraitSize = CGSize(width: 402, height: 874)
    private let landscapeSize = CGSize(width: 874, height: 402)

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private struct WrongLayout: Error {}

    private var pulse: RadioStation {
        RadioStation(name: "Pulse Test", streamURL: "https://example.invalid/s.mp3", imageURL: "",
                     desc: "d", longDesc: "A long blurb for Pulse.", serverName: "s",
                     shortCode: "p", defaultDJ: "dj")
    }

    /// The About screen in a window of the given size. The vertical size class is overridden
    /// before the view loads, because the screen builds its body in `viewDidLoad` and picks the
    /// layout from that class. The helper then checks which layout it actually got, and fails
    /// itself (not a test expectation) if that is not the one asked for.
    private func makeAbout(size: CGSize, compact: Bool, station: RadioStation? = nil) throws -> AboutViewController {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let controller = AboutViewController()
        controller.currentStation = station
        if compact { controller.traitOverrides.verticalSizeClass = .compact }
        window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()

        let expectedClass: UIUserInterfaceSizeClass = compact ? .compact : .regular
        guard controller.traitCollection.verticalSizeClass == expectedClass else {
            XCTFail("harness: wanted vertical size class \(expectedClass.rawValue), got \(controller.traitCollection.verticalSizeClass.rawValue)")
            throw WrongLayout()
        }
        // Portrait puts the credits in the stack beside the website button; landscape puts them
        // in a separate container.
        guard let website = allSubviews(of: controller.view).compactMap({ $0 as? UIButton })
                .first(where: { $0.configuration?.title == "Visit our website" }),
              let buttonStack = website.superview as? UIStackView else {
            XCTFail("harness: could not find the website button inside a stack")
            throw WrongLayout()
        }
        let stackHoldsCredits = buttonStack.arrangedSubviews.contains { $0 is UIScrollView }
        guard stackHoldsCredits == !compact else {
            XCTFail("harness: layout marker says \(stackHoldsCredits ? "portrait" : "landscape") but \(compact ? "landscape" : "portrait") was asked for")
            throw WrongLayout()
        }
        return controller
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        allSubviews(of: view).compactMap { $0 as? UIScrollView }
    }

    private func labels(in view: UIView) -> [UILabel] {
        allSubviews(of: view).compactMap { $0 as? UILabel }
    }

    private func isInsideAScrollView(_ view: UIView, in root: UIView) -> Bool {
        scrollViews(in: root).contains { view.isDescendant(of: $0) }
    }

    private func attributionLabel(in root: UIView) -> UILabel? {
        labels(in: root).first { $0.text?.hasPrefix("Based on Swift Radio Pro") == true }
    }

    // MARK: - Today's behavior

    func testPortraitAttributionIsFixedOutsideTheCreditsScroll() throws {
        let about = try makeAbout(size: portraitSize, compact: false)

        let attribution = try XCTUnwrap(attributionLabel(in: about.view))
        XCTAssertFalse(isInsideAScrollView(attribution, in: about.view),
                       "in portrait the attribution is a fixed row below the credits")
        // A credit reads "role: name". Other labels (the blurb, the build label's
        // "Environment: Xcode") contain ": " too but sit outside the scroll view.
        XCTAssertTrue(labels(in: about.view).contains {
            $0.text?.contains(": ") == true && isInsideAScrollView($0, in: about.view)
        }, "the credits scroll")
    }

    func testLandscapeAttributionAndDescriptionRollWithTheCredits() throws {
        let about = try makeAbout(size: landscapeSize, compact: true)

        let attribution = try XCTUnwrap(attributionLabel(in: about.view))
        XCTAssertTrue(isInsideAScrollView(attribution, in: about.view))
        let description = try XCTUnwrap(labels(in: about.view).first { $0.text?.hasPrefix("RadioSpiral: 24/7") == true })
        XCTAssertTrue(isInsideAScrollView(description, in: about.view),
                      "in landscape the generic blurb scrolls with the credits")
    }

    /// The bug being fixed: the header shows whichever station is current.
    func testTheHeaderShowsTheCurrentStationsName() throws {
        let about = try makeAbout(size: portraitSize, compact: false, station: pulse)

        XCTAssertTrue(labels(in: about.view).contains { $0.text == "Pulse Test" })
    }
}
