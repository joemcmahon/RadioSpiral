import Foundation

/// Accepts a URL from the server or config only if it's https.
///
/// `NSAllowsArbitraryLoads` stays on because removing it also applies stricter https rules to every
/// connection, and a failure from that could only be fixed through App Review. A URL this rejects
/// can be fixed from the server or config. An https URL that redirects to http still gets through.
enum SecureURL {
    static func https(_ string: String) -> URL? {
        URL(string: string).flatMap(https)
    }

    static func https(_ url: URL) -> URL? {
        url.scheme?.lowercased() == "https" ? url : nil
    }
}
