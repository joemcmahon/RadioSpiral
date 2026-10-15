// RadioSpiral/Model/StationServer.swift
import Foundation
import StoreKit

/// Where this copy of the app came from. Only TestFlight and Xcode builds may use the test server.
enum InstallEnvironment: Equatable {
    case appStore, testFlight, xcode

    var allowsTestServer: Bool { self != .appStore }

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
                var environment = InstallEnvironment.appStore
                if case .verified(let transaction)? = try? await AppTransaction.shared {
                    switch transaction.environment {
                    case .sandbox: environment = .testFlight
                    case .xcode: environment = .xcode
                    default: environment = .appStore
                    }
                }
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
enum StationServer: String {
    case production, test

    static let key = "stationServer"

    var configURL: String {
        switch self {
        case .production: return "https://raw.githubusercontent.com/joemcmahon/radiospiral-config/master/config.json"
        case .test: return "https://raw.githubusercontent.com/joemcmahon/radiospiral-config/master/config-test.json"
        }
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
