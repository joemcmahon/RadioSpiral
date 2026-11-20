//
//  AboutScreenHeaderTests.swift
//  ConfigClientTests
//
//  The About screen's header and scrolling credits: the header is the wordmark alone, fixed in
//  both orientations, and the credits and the attribution scroll together beneath it. Run on an
//  iPhone simulator.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class AboutScreenHeaderTests: XCTestCase {

    private let portraitSize = CGSize(width: 402, height: 874)
    private let landscapeSize = CGSize(width: 874, height: 402)

    private var window: UIWindow!

    override class func setUp() {
        super.setUp()
        // The host app's launch fetch can land mid-test, and the stations manager then clears a
        // current station that is not in the fetched list. No signal says the fetch is done: a
        // list means it succeeded; offline there is never one, so stop after its 10 second
        // request timeout. The extra second lets the app open a single station.
        let deadline = Date().addingTimeInterval(12)
        while StationsManager.shared.stations.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        StationsManager.shared.set(station: nil)
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
    private func makeAbout(size: CGSize, compact: Bool,
                           category: UIContentSizeCategory? = nil) throws -> AboutViewController {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let controller = AboutViewController()
        if compact { controller.traitOverrides.verticalSizeClass = .compact }
        if let category { controller.traitOverrides.preferredContentSizeCategory = category }
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

    private func wordmarks(in root: UIView) -> [UIView] {
        allSubviews(of: root).filter { $0.accessibilityIdentifier == "aboutWordmark" }
    }

    private func attributions(in root: UIView) -> [UILabel] {
        labels(in: root).filter { $0.text?.hasPrefix("Based on Swift Radio Pro") == true }
    }

    private func frameInWindow(_ view: UIView) -> CGRect {
        view.convert(view.bounds, to: window)
    }

    /// Both layouts, with a string for failure messages.
    private var layouts: [(name: String, size: CGSize, compact: Bool)] {
        [("portrait", portraitSize, false), ("landscape", landscapeSize, true)]
    }

    // MARK: - The header

    func testPortraitAndLandscapeShowOneWordmarkAndNoStationText() throws {
        for layout in layouts {
            let about = try makeAbout(size: layout.size, compact: layout.compact)

            let marks = wordmarks(in: about.view)
            XCTAssertEqual(marks.count, 1, "\(layout.name): one wordmark")
            XCTAssertTrue(marks.first?.superview.map { labels(in: $0).isEmpty } ?? false,
                          "\(layout.name): the header is the image alone")
            XCTAssertFalse(labels(in: about.view).contains { $0.text?.hasPrefix("RadioSpiral: 24/7") == true },
                           "\(layout.name): no generic blurb")
        }
    }

    /// The original bug. About no longer receives a station, so this goes through the shared
    /// stations manager: even if About read the current station itself, none of its content
    /// may appear. The station is asserted current before and after, so a lost race with the
    /// launch fetch fails loudly instead of passing vacuously.
    func testNoStationContentAppearsWhileAnotherStationIsCurrent() throws {
        let pulse = self.pulse
        StationsManager.shared.set(station: pulse)

        for layout in layouts {
            XCTAssertEqual(StationsManager.shared.currentStation?.name, "Pulse Test",
                           "\(layout.name): the station is current before About is built")
            let about = try makeAbout(size: layout.size, compact: layout.compact)
            XCTAssertEqual(StationsManager.shared.currentStation?.name, "Pulse Test",
                           "\(layout.name): the station is still current after About is built")

            XCTAssertFalse(labels(in: about.view).contains { $0.text?.contains("Pulse Test") == true },
                           "\(layout.name): no station name")
            XCTAssertFalse(labels(in: about.view).contains { $0.text?.contains(pulse.longDesc) == true },
                           "\(layout.name): no station blurb")
            XCTAssertEqual(wordmarks(in: about.view).count, 1, "\(layout.name): the wordmark is the header")
        }
    }

    func testTheWordmarkStaysPutWhileTheCreditsScroll() throws {
        for layout in layouts {
            let about = try makeAbout(size: layout.size, compact: layout.compact)

            let mark = try XCTUnwrap(wordmarks(in: about.view).first, layout.name)
            XCTAssertFalse(isInsideAScrollView(mark, in: about.view), "\(layout.name): the header is fixed")
            let before = frameInWindow(mark)
            let attribution = try XCTUnwrap(attributionLabel(in: about.view))
            let scroll = try XCTUnwrap(scrollViews(in: about.view).first { attribution.isDescendant(of: $0) })
            scroll.contentOffset.y = 60
            window.layoutIfNeeded()
            XCTAssertEqual(frameInWindow(mark), before, "\(layout.name): the wordmark does not move")
        }
    }

    func testTheAttributionScrollsWithTheCreditsInBothOrientations() throws {
        for layout in layouts {
            let about = try makeAbout(size: layout.size, compact: layout.compact)

            let attribution = try XCTUnwrap(attributionLabel(in: about.view), layout.name)
            let scroll = try XCTUnwrap(scrollViews(in: about.view).first { attribution.isDescendant(of: $0) },
                                       "\(layout.name): the attribution scrolls")
            XCTAssertTrue(labels(in: scroll).contains { $0.text?.contains(": ") == true },
                          "\(layout.name): the credits are in the same scroll view")
        }
    }

    // MARK: - Review focus

    /// Rotation and late-arriving credits both rebuild the body. The body is rebuilt for real
    /// (the wordmark is a new view each time) and there is still one wordmark afterward, and the
    /// same two attributions as a fresh build (one per copy of the looping sequence), never more.
    func testRebuildingLeavesOneWordmarkAndNoExtraAttributions() throws {
        let about = try makeAbout(size: portraitSize, compact: false)
        var previous = try XCTUnwrap(wordmarks(in: about.view).first)
        XCTAssertEqual(attributions(in: about.view).count, 2, "fresh build: one attribution per loop copy")

        for round in 1...2 {
            about.rebuildBody()
            window.layoutIfNeeded()

            let marks = wordmarks(in: about.view)
            XCTAssertEqual(marks.count, 1, "round \(round): one wordmark")
            XCTAssertEqual(attributions(in: about.view).count, 2, "round \(round): no extra attributions")
            XCTAssertFalse(marks.first === previous, "round \(round): the body was rebuilt")
            previous = try XCTUnwrap(marks.first)
        }
    }

    func testTheWordmarkIsNoWiderThanTheCapOnAnIPadSizedWindow() throws {
        let about = try makeAbout(size: CGSize(width: 1024, height: 768), compact: false)

        let mark = try XCTUnwrap(wordmarks(in: about.view).first)
        let width = frameInWindow(mark).width
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThanOrEqual(width, LaunchWordmark.maximumWidth + 0.5)
    }

    /// A credit line: a label inside a scroll view that reads "role: name".
    private func creditLabel(in root: UIView) -> UILabel? {
        labels(in: root).first { $0.text?.contains(": ") == true && isInsideAScrollView($0, in: root) }
    }

    func testCreditsStillHaveRoomAtTheLargestTextSizeInLandscape() throws {
        let normal = try makeAbout(size: landscapeSize, compact: true)
        let normalSize = try XCTUnwrap(creditLabel(in: normal.view)).font.pointSize

        let about = try makeAbout(size: landscapeSize, compact: true,
                                  category: .accessibilityExtraExtraExtraLarge)

        // Harness check: the text really is larger, or the rest proves nothing.
        let credit = try XCTUnwrap(creditLabel(in: about.view))
        XCTAssertGreaterThan(credit.font.pointSize, normalSize, "harness: the largest text size reaches the credits")
        let attribution = try XCTUnwrap(attributionLabel(in: about.view))
        let scroll = try XCTUnwrap(scrollViews(in: about.view).first { attribution.isDescendant(of: $0) })
        XCTAssertGreaterThan(frameInWindow(scroll).height, 0)
        let ok = try XCTUnwrap(allSubviews(of: about.view).first { $0.accessibilityIdentifier == "okButton" })
        XCTAssertTrue(window.safeAreaLayoutGuide.layoutFrame.contains(frameInWindow(ok)),
                      "the OK button stays inside the safe area")
    }

    func testTheCreditsScrollViewKeepsItsTapToPauseRecognizer() throws {
        for layout in layouts {
            let about = try makeAbout(size: layout.size, compact: layout.compact)

            let attribution = try XCTUnwrap(attributionLabel(in: about.view), layout.name)
            let scroll = try XCTUnwrap(scrollViews(in: about.view).first { attribution.isDescendant(of: $0) })
            XCTAssertTrue(scroll.gestureRecognizers?.contains { $0 is UITapGestureRecognizer } == true,
                          "\(layout.name): tapping the credits pauses them")
        }
    }

    /// The credits are shown twice for a seamless loop, and the loop jumps back by `creditsLoopLength`
    /// when it wraps. That is only invisible if the jump equals the distance between the two copies;
    /// the attribution ends each copy, so the distance between the two attributions is that distance.
    /// Only layouts where the credits overflow loop; a tall portrait window shows them once, still
    /// (see AboutCreditsFitTests), so this uses a short portrait window.
    func testTheLoopWrapsByExactlyTheDistanceBetweenTheTwoCopies() throws {
        let looping: [(name: String, size: CGSize, compact: Bool)] =
            [("short portrait", CGSize(width: 402, height: 560), false), ("landscape", landscapeSize, true)]
        for layout in looping {
            let about = try makeAbout(size: layout.size, compact: layout.compact)

            let both = attributions(in: about.view)
            XCTAssertEqual(both.count, 2, "\(layout.name): one attribution per copy")
            let scroll = try XCTUnwrap(scrollViews(in: about.view).first { both.first?.isDescendant(of: $0) == true })
            let tops = both.map { $0.convert($0.bounds, to: scroll).minY }.sorted()
            XCTAssertEqual(about.creditsLoopLength, tops[1] - tops[0], accuracy: 0.5,
                           "\(layout.name): wrapping must not jump the credits")
        }
    }
}
