//
//  CreditsClient.swift
//  RadioSpiral
//
//  Fetches staff credits from the radiospiral-config GitHub repo.
//  Falls back to hardcoded credits if the fetch fails.
//

import Foundation

/// Client for fetching staff credits from remote JSON
public class CreditsClient {
    public static let shared = CreditsClient()

    private let creditsURL: String
    private var cachedCredits: [CreditPair] = []

    public init(creditsURL: String = "https://raw.githubusercontent.com/joemcmahon/radiospiral-config/master/credits.json") {
        self.creditsURL = creditsURL
    }

    /// Returns cached credits immediately (empty array before first fetch)
    public var credits: [CreditPair] {
        return cachedCredits
    }

    /// Fetch credits from remote. On any error, completion receives fallbackCredits.
    public func fetchCredits(completion: @escaping ([CreditPair]) -> Void) {
        // Return cache immediately if already populated
        if !cachedCredits.isEmpty {
            completion(cachedCredits)
            return
        }

        guard let url = URL(string: creditsURL) else {
            if CreditsClientDebug.debugLog { print("CreditsClient: Invalid URL") }
            completion(fallbackCredits)
            return
        }

        // Support file:// URLs for tests
        if url.scheme == "file" {
            do {
                let data = try Data(contentsOf: url)
                let wrapper = try JSONDecoder().decode(CreditsWrapper.self, from: data)
                cachedCredits = wrapper.credits
                if CreditsClientDebug.debugLog { print("CreditsClient: Loaded \(wrapper.credits.count) credits from file") }
                completion(cachedCredits)
            } catch {
                if CreditsClientDebug.debugLog { print("CreditsClient: File load failed: \(error)") }
                completion(fallbackCredits)
            }
            return
        }

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10

        let session = URLSession(configuration: config)
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                if CreditsClientDebug.debugLog { print("CreditsClient: Network error: \(error)") }
                completion(fallbackCredits)
                return
            }

            guard
                let httpResponse = response as? HTTPURLResponse,
                200...299 ~= httpResponse.statusCode
            else {
                if CreditsClientDebug.debugLog { print("CreditsClient: HTTP error") }
                completion(fallbackCredits)
                return
            }

            guard let data = data else {
                completion(fallbackCredits)
                return
            }

            do {
                let wrapper = try JSONDecoder().decode(CreditsWrapper.self, from: data)
                self.cachedCredits = wrapper.credits
                if CreditsClientDebug.debugLog { print("CreditsClient: Fetched \(wrapper.credits.count) credits") }
                completion(self.cachedCredits)
            } catch {
                if CreditsClientDebug.debugLog { print("CreditsClient: Decode failed: \(error)") }
                completion(fallbackCredits)
            }
        }

        task.resume()
    }
}

/// Debug configuration (matches ConfigClientDebug pattern)
struct CreditsClientDebug {
    static let debugLog = true
}
