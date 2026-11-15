// RadioSpiral/Model/StationServer.swift
import Foundation
import StoreKit

/// Where this copy of the app came from. Only TestFlight and Xcode builds may use the test server.
enum InstallEnvironment: Equatable {
    case appStore, testFlight, xcode

    var allowsTestServer: Bool { self != .appStore }

    /// Nil means the transaction couldn't be verified.
    static func from(_ environment: AppStore.Environment?) -> InstallEnvironment {
        switch environment {
        case .sandbox?: return .testFlight
        case .xcode?: return .xcode
        default: return .appStore
        }
    }

    /// Nil until `resolve(_:)` finishes; treated as App Store until then. Main thread only.
    private(set) static var current: InstallEnvironment?

    /// Determines the environment once per launch. Calls back on the main thread.
    /// Anything that can't be verified counts as App Store, so it never unlocks the test server.
    static func resolve(_ completion: @escaping (InstallEnvironment) -> Void) {
        DispatchQueue.main.async {
            if let current { completion(current); return }
            #if DEBUG
            current = .xcode
            completion(.xcode)
            #else
            Task {
                var verified: AppStore.Environment?
                if case .verified(let transaction)? = try? await AppTransaction.shared {
                    verified = transaction.environment
                }
                let environment = from(verified)
                await MainActor.run {
                    current = environment
                    completion(environment)
                }
            }
            #endif
        }
    }
}

/// Which station config the app loads. Testers pick it on the About screen.
/// `preview` is production plus stations not yet public, for testers only.
enum StationServer: String, CaseIterable {
    case production, preview, test

    static let key = "stationServer"

    var configURL: String {
        switch self {
        case .production: return ConfigClient.productionConfigURL
        case .preview: return "https://raw.githubusercontent.com/joemcmahon/radiospiral-config/master/config-preview.json"
        case .test: return "https://raw.githubusercontent.com/joemcmahon/radiospiral-config/master/config-test.json"
        }
    }

    var title: String { rawValue.capitalized }

    /// Shown on the stations screen and CarPlay when a tester is off production.
    var bannerLabel: String? {
        switch self {
        case .production: return nil
        case .preview: return "PREVIEW"
        case .test: return "TEST SERVER"
        }
    }

    /// What the banner says. While the bundled stations are in use because no config could be had,
    /// it says so on any server. Only installs that allow the tester selector see that wording:
    /// a listener's app, on the fallback or not, shows no tester label.
    static func bannerLabel(for server: StationServer, usingFallback: Bool, environment: InstallEnvironment?) -> String? {
        if usingFallback && environment?.allowsTestServer == true { return "FORCED FALLBACK" }
        return server.bannerLabel
    }

    /// The banner label for the server in use right now. Main thread only.
    static var currentBannerLabel: String? {
        bannerLabel(for: current, usingFallback: ConfigClient.shared.isUsingBundledFallback,
                    environment: InstallEnvironment.current)
    }

    /// The tester's saved choice. Only honored where the install environment allows it.
    static var selected: StationServer {
        get { StationServer(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .production }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static func effective(selected: StationServer, environment: InstallEnvironment?) -> StationServer {
        environment?.allowsTestServer == true ? selected : .production
    }

    /// The server in use right now. Main thread only.
    static var current: StationServer {
        effective(selected: selected, environment: InstallEnvironment.current)
    }
}
