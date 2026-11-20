//
//  AboutCreditsRoomTests.swift
//  ConfigClientTests
//
//  In portrait the credits share a stack with the website and email buttons, the test-server
//  selector and the build label. At the largest accessibility text sizes those grew until the
//  credits got no room at all in a narrow window. The credits keep room for at least four lines
//  of their own text, and the other controls stop growing past a point so they leave it.
//  Run on an iPhone simulator.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class AboutCreditsRoomTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        AboutTestNetwork.block()
    }

    override func tearDown() {
        AboutTestNetwork.restore()
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    /// About in a portrait window at the given text size.
    private func makeAbout(size: CGSize, category: UIContentSizeCategory) throws -> AboutViewController {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let controller = AboutViewController()
        controller.traitOverrides.preferredContentSizeCategory = category
        window = try TestWindow.make(size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        window.layoutIfNeeded()
        return controller
    }

    /// The credits scroll view: the one that holds the attribution.
    private func creditsScroll(in about: AboutViewController) throws -> UIScrollView {
        let scrolls = allSubviews(of: about.view).compactMap { $0 as? UIScrollView }
        return try XCTUnwrap(scrolls.first { scroll in
            allSubviews(of: scroll).contains { ($0 as? UILabel)?.text?.hasPrefix("Based on Swift Radio Pro") == true }
        })
    }

    /// Narrow windows, short and tall: a narrow iPad window, a small phone, a large phone.
    func testTheCreditsKeepRoomForFourLinesAtTheLargestTextSize() throws {
        let windows: [(String, CGSize)] = [("320x700", CGSize(width: 320, height: 700)),
                                           ("375x667", CGSize(width: 375, height: 667)),
                                           ("402x874", CGSize(width: 402, height: 874))]
        for (name, size) in windows {
            window?.isHidden = true
            let about = try makeAbout(size: size, category: .accessibilityExtraExtraExtraLarge)
            let scroll = try creditsScroll(in: about)
            let credit = try XCTUnwrap(allSubviews(of: scroll).compactMap { $0 as? UILabel }
                .first { $0.text?.contains(": ") == true })

            // Harness check: the text really is at the largest size (a line is much taller than at 13 pt).
            XCTAssertGreaterThan(credit.font.lineHeight, 40, "\(name): harness: largest text size")
            XCTAssertGreaterThanOrEqual(scroll.bounds.height, 4 * credit.font.lineHeight,
                                        "\(name): room for four lines of credits")
        }
    }

    /// Making room must not crush the other controls: the credits get their minimum by the other
    /// controls growing less, not by being squeezed below their natural height or under the OK button.
    func testTheOtherControlsAreNotCrushedToMakeRoom() throws {
        let windows: [(String, CGSize)] = [("320x700", CGSize(width: 320, height: 700)),
                                           ("375x667", CGSize(width: 375, height: 667)),
                                           ("402x874", CGSize(width: 402, height: 874))]
        for (name, size) in windows {
            window?.isHidden = true
            let about = try makeAbout(size: size, category: .accessibilityExtraExtraExtraLarge)
            let all = allSubviews(of: about.view)
            let ok = try XCTUnwrap(all.first { $0.accessibilityIdentifier == "okButton" })
            let buildLabel = try XCTUnwrap(all.first { $0.accessibilityIdentifier == "buildInfoLabel" })
            let buttons = all.compactMap { $0 as? UIButton }
                .filter { ["Visit our website", "Email us"].contains($0.configuration?.title) }
            XCTAssertEqual(buttons.count, 2, "\(name): harness: both buttons found")

            for button in buttons {
                let natural = button.sizeThatFits(CGSize(width: button.bounds.width,
                                                         height: .greatestFiniteMagnitude)).height
                XCTAssertGreaterThanOrEqual(button.bounds.height + 0.5, natural,
                                            "\(name): \(button.configuration?.title ?? "") keeps its natural height")
            }
            let buildBottom = buildLabel.convert(buildLabel.bounds, to: about.view).maxY
            let okTop = ok.convert(ok.bounds, to: about.view).minY
            XCTAssertLessThanOrEqual(buildBottom, okTop + 0.5, "\(name): the build label ends above the OK button")
        }
    }
}
