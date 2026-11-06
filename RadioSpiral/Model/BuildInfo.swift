// RadioSpiral/Model/BuildInfo.swift
import Foundation

/// Identifies this build on the About screen.
enum BuildInfo {
    /// Written into the app bundle by the "Record build commit" build phase.
    private static let commitFileName = "BuildCommit"

    /// The About screen's text for this running build. Main thread only, like `InstallEnvironment.current`.
    static var aboutText: String {
        let info = Bundle.main.infoDictionary
        return text(version: info?["CFBundleShortVersionString"] as? String,
                    build: info?["CFBundleVersion"] as? String,
                    commit: bundledCommit,
                    environment: InstallEnvironment.current)
    }

    /// Only TestFlight and Xcode builds name their environment. App Store builds, and anything
    /// not yet verified, show none, so regular listeners never see wording about it.
    static func text(version: String?, build: String?, commit: String?, environment: InstallEnvironment?) -> String {
        var line = "Version \(version ?? "unknown") (\(build ?? "unknown"))"
        if let commit { line += " \(commit)" }
        switch environment {
        case .testFlight: return line + "\nEnvironment: TestFlight"
        case .xcode: return line + "\nEnvironment: Xcode"
        case .appStore, nil: return line
        }
    }

    /// The commit hash in the bundled file, or nil if the contents aren't one.
    static func commit(fromFileContents contents: String?) -> String? {
        guard let trimmed = contents?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.count >= 4, trimmed.allSatisfy(\.isHexDigit) else { return nil }
        return trimmed
    }

    static var bundledCommit: String? {
        guard let url = Bundle.main.url(forResource: commitFileName, withExtension: "txt") else { return nil }
        return commit(fromFileContents: try? String(contentsOf: url, encoding: .utf8))
    }
}
