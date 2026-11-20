//
//  TestWindow.swift
//  ConfigClientTests
//
//  A window of a chosen size for tests that lay out a screen. `UIWindow(frame:)` is deprecated
//  in iOS 26, so the window is created in the test host's window scene and then sized.
//

import XCTest
import UIKit

enum TestWindow {
    private struct NoWindowScene: Error {}

    /// A window of the given size in the test host's window scene. Fails the test, loudly, if the
    /// host has no scene, so that a layout test never quietly stops running.
    @MainActor
    static func make(size: CGSize) throws -> UIWindow {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            XCTFail("harness: the test host has no window scene to create a window in")
            throw NoWindowScene()
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        return window
    }
}
