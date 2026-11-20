//
//  AboutTestNetwork.swift
//  ConfigClientTests
//
//  Keeps the About screen's credits fetch off the real network in tests.
//

import UIKit
@testable import RadioSpiral

@MainActor
enum AboutTestNetwork {
    private static var original: URLSession?

    /// Answers the app's shared credits client from the stand-in session. (`CreditsClient.swift` is
    /// also compiled into this test target, so a bare `CreditsClient` here would be the test
    /// bundle's own copy, not the one the About screen uses; hence the module name.) With no reply set for its URL
    /// the request fails, the client hands back the built-in credits, and About shows exactly
    /// those and never rebuilds itself. Call `restore()` in `tearDown`.
    static func block() {
        guard original == nil else { return }
        original = RadioSpiral.CreditsClient.shared.session
        RadioSpiral.CreditsClient.shared.session = StubURLProtocol.makeSession()
    }

    static func restore() {
        guard let original else { return }
        RadioSpiral.CreditsClient.shared.session = original
        self.original = nil
    }
}
