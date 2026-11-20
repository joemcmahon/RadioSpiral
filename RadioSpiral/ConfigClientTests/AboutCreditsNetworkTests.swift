//
//  AboutCreditsNetworkTests.swift
//  ConfigClientTests
//
//  The About screen asks the shared credits client for the live credits when it loads, and
//  rebuilds itself if they differ from the built-in ones. The live list is not the built-in list,
//  so on a real connection that rebuild landed at an unpredictable moment in the middle of a
//  layout test (and restarted the credits' start delay). The About tests block the network, so
//  the screen always shows the built-in credits and never rebuilds. Run on an iPhone simulator.
//

import XCTest
@testable import RadioSpiral

@MainActor
final class AboutCreditsNetworkTests: XCTestCase {

    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
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

    func testOpeningAboutAsksTheBlockedClientAndNeverRebuildsItself() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Run on an iPhone simulator")
        let about = AboutViewController()
        window = try TestWindow.make(size: CGSize(width: 402, height: 874))
        window.rootViewController = about
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()

        // The credits request went to the stand-in session, not the network.
        XCTAssertTrue(StubURLProtocol.requestedURLs.contains { $0.hasSuffix("credits.json") },
                      "the credits request was answered by the stand-in, not the network")

        // Nothing rebuilt the screen: it shows exactly the built-in credits.
        let scroll = try XCTUnwrap(allSubviews(of: about.view).compactMap { $0 as? UIScrollView }.first { scroll in
            allSubviews(of: scroll).contains { ($0 as? UILabel)?.text?.hasPrefix("Based on Swift Radio Pro") == true }
        })
        let shownCredits = allSubviews(of: scroll).compactMap { $0 as? UILabel }
            .compactMap { $0.text }.filter { $0.contains(": ") }
        let expected = fallbackCredits.map { "\($0.role): \($0.name)" }
        XCTAssertEqual(Array(shownCredits.prefix(expected.count)), expected, "the built-in credits")
    }
}
