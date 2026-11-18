//
//  ViewControllerIdiomTests.swift
//  ConfigClientTests
//
//  Now Playing builds its layout constraints in viewDidLoad, before the screen is in a window,
//  and reads the idiom (iPad or phone) from its own trait collection there. That is only correct
//  if a view controller already reports the device's idiom at that point: an `.unspecified`
//  idiom would give an iPad the phone layout. Run these on an iPhone and an iPad simulator.
//

import XCTest
@testable import RadioSpiral

final class ViewControllerIdiomTests: XCTestCase {

    func testAViewControllerKnowsTheDevicesIdiomBeforeItIsInAWindow() {
        let controller = UIViewController()
        controller.loadViewIfNeeded()
        XCTAssertEqual(controller.traitCollection.userInterfaceIdiom, UIDevice.current.userInterfaceIdiom)
    }

    /// Now Playing is pushed on a navigation controller that may not be in a window yet either.
    func testAViewControllerInANavigationControllerKnowsTheDevicesIdiomInViewDidLoad() {
        let controller = UIViewController()
        let navigation = UINavigationController(rootViewController: controller)
        controller.loadViewIfNeeded()
        XCTAssertNil(navigation.view.window)
        XCTAssertEqual(controller.traitCollection.userInterfaceIdiom, UIDevice.current.userInterfaceIdiom)
        XCTAssertNotEqual(controller.traitCollection.userInterfaceIdiom, .unspecified)
    }
}
