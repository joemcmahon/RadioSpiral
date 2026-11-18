//
//  LaunchWordmarkTests.swift
//  ConfigClientTests
//
//  How the RadioSpiral wordmark is sized on the startup (loader) screen: a share of the screen's
//  width, never wider than a cap, so it isn't tiny on an iPad or huge on a small phone. The
//  launch storyboard uses the same numbers (`LaunchScreen.storyboard`), so the loader doesn't
//  jump when it takes over.
//

import XCTest
@testable import RadioSpiral

final class LaunchWordmarkTests: XCTestCase {

    /// Lays the wordmark out in a container of the given size and returns the image view.
    private func laidOut(width: CGFloat, height: CGFloat) -> UIImageView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let imageView = LaunchWordmark.makeImageView()
        container.addSubview(imageView)
        NSLayoutConstraint.activate(LaunchWordmark.constraints(for: imageView, in: container))
        container.layoutIfNeeded()
        return imageView
    }

    func testTheWordmarkImageIsInTheApp() {
        XCTAssertNotNil(UIImage(named: LaunchWordmark.imageName))
    }

    func testAPhoneGetsAShareOfItsWidth() {
        let wordmark = laidOut(width: 393, height: 852)
        XCTAssertEqual(wordmark.frame.width, 393 * LaunchWordmark.widthFraction, accuracy: 0.5)
    }

    func testASmallPhoneGetsASmallerWordmark() {
        let small = laidOut(width: 320, height: 568).frame.width
        let big = laidOut(width: 430, height: 932).frame.width
        XCTAssertLessThan(small, big)
        XCTAssertEqual(small, 320 * LaunchWordmark.widthFraction, accuracy: 0.5)
    }

    func testAnIPadIsCappedAtTheMaximumWidth() {
        XCTAssertEqual(laidOut(width: 1024, height: 1366).frame.width, LaunchWordmark.maximumWidth, accuracy: 0.5)
        XCTAssertEqual(laidOut(width: 1366, height: 1024).frame.width, LaunchWordmark.maximumWidth, accuracy: 0.5)
    }

    func testTheArtworkKeepsItsShapeAndIsCentered() {
        let wordmark = laidOut(width: 393, height: 852)
        let image = UIImage(named: LaunchWordmark.imageName)!
        // A frame snaps to device pixels, so a 38.4 pt height can come out as 38.6 pt: allow 0.1
        // (1.5%) on a ratio of about 6.66.
        XCTAssertEqual(wordmark.frame.width / wordmark.frame.height,
                       image.size.width / image.size.height, accuracy: 0.1)
        XCTAssertEqual(wordmark.frame.midX, 393 / 2, accuracy: 0.5)
        XCTAssertEqual(wordmark.frame.midY, 852 / 2, accuracy: 0.5)
    }
}
