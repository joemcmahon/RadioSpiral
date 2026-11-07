//
//  ConfigClient.swift
//  RadioSpiral
//
//  Created on 2025-11-12.
//  Provides dynamic station configuration from Azuracast API with fallback support
//

import UIKit

/// The session the config and credits clients use in production: no local cache, 10 second timeout.
func makeConfigSession() -> URLSession {
    let configuration = URLSessionConfiguration.default
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 10
    return URLSession(configuration: configuration)
}

/// Client for fetching server configuration and stations
/// Supports multiple config sources: primary Azuracast, fallback Azuracast, static JSON
/// Returns portable StationConfig objects
public class ConfigClient {
    public static let shared = ConfigClient()

    /// Changing it (e.g. switching station servers) drops stations cached from the old config.
    public var configURL: String {
        didSet { if configURL != oldValue { cachedStations = [] } }
    }
    private var cachedStations: [StationConfig] = []

    /// Every request goes through this session. Tests replace it to supply canned responses.
    var session = makeConfigSession()

    public init(configURL: String = "https://raw.githubusercontent.com/joemcmahon/radiospiral-config/master/config.json") {
        self.configURL = configURL
    }

    /// Fetch stations from configured sources in order
    /// Tries each config in sequence until one succeeds
    /// Returns portable StationConfig objects
    public func fetchStations(completion: @escaping (Result<[StationConfig], Error>) -> Void) {
        fetchServerConfig { [weak self] configResult in
            switch configResult {
            case .success(let configs):
                self?.tryConfigsInOrder(configs, index: 0, completion: completion)
            case .failure:
                // If we can't fetch config, try cached stations
                if let cached = self?.cachedStations, !cached.isEmpty {
                    completion(.success(cached))
                } else {
                    completion(.failure(ConfigClientError.dataNotFound))
                }
            }
        }
    }

    /// Get station info by short code (for metadata fallback)
    /// Returns station data when metadata server is unavailable
    public func getStationInfo(byShortCode shortCode: String) -> StationConfig? {
        return cachedStations.first { $0.shortCode == shortCode }
    }

    // MARK: - Private Methods

    private func fetchServerConfig(completion: @escaping (Result<[ConfigSource], Error>) -> Void) {
        guard let url = URL(string: configURL) else {
            completion(.failure(ConfigClientError.urlNotValid))
            return
        }

        // Handle file:// URLs directly (for tests and bundled configs)
        if url.scheme == "file" {
            do {
                let data = try Data(contentsOf: url)
                let configWrapper = try JSONDecoder().decode(ConfigWrapper.self, from: data)
                if ConfigClientDebug.debugLog { print("ConfigClient: Server config loaded from file with \(configWrapper.configs.count) sources") }
                completion(.success(configWrapper.configs))
            } catch {
                if ConfigClientDebug.debugLog { print("ConfigClient: Failed to load file config: \(error)") }
                completion(.failure(error))
            }
            return
        }

        // Handle HTTP/HTTPS URLs with URLSession
        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                if ConfigClientDebug.debugLog { print("ConfigClient: Failed to fetch server config: \(error)") }
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
                if ConfigClientDebug.debugLog { print("ConfigClient: Invalid HTTP response") }
                completion(.failure(ConfigClientError.httpResponseNotValid))
                return
            }

            guard let data = data else {
                completion(.failure(ConfigClientError.dataNotFound))
                return
            }

            do {
                let configWrapper = try JSONDecoder().decode(ConfigWrapper.self, from: data)
                if ConfigClientDebug.debugLog { print("ConfigClient: Server config fetched with \(configWrapper.configs.count) sources") }
                completion(.success(configWrapper.configs))
            } catch {
                if ConfigClientDebug.debugLog { print("ConfigClient: Failed to decode config: \(error)") }
                completion(.failure(error))
            }
        }

        task.resume()
    }

    private func tryConfigsInOrder(_ configs: [ConfigSource], index: Int, completion: @escaping (Result<[StationConfig], Error>) -> Void) {
        guard index < configs.count else {
            // Tried all configs, fall back to cached if available
            if !cachedStations.isEmpty {
                completion(.success(cachedStations))
            } else {
                completion(.failure(ConfigClientError.dataNotFound))
            }
            return
        }

        let config = configs[index]

        switch config.format {
        case .azuracast:
            tryAzuracastConfig(config, completion: { [weak self] result in
                switch result {
                case .success(let stations):
                    self?.cachedStations = stations
                    completion(.success(stations))
                case .failure:
                    if ConfigClientDebug.debugLog { print("ConfigClient: Azuracast config \(index) failed, trying next...") }
                    self?.tryConfigsInOrder(configs, index: index + 1, completion: completion)
                }
            })

        case .static:
            tryStaticConfig(config, completion: { [weak self] result in
                switch result {
                case .success(let stations):
                    self?.cachedStations = stations
                    completion(.success(stations))
                case .failure:
                    if ConfigClientDebug.debugLog { print("ConfigClient: Static config \(index) failed, trying next...") }
                    self?.tryConfigsInOrder(configs, index: index + 1, completion: completion)
                }
            })
        }
    }

    private func tryAzuracastConfig(
        _ config: ConfigSource,
        completion: @escaping (Result<[StationConfig], Error>) -> Void
    ) {
        guard let server = config.server else {
            completion(.failure(ConfigClientError.dataNotValid))
            return
        }

        tryPublicAzuracastAPI(server: server, exclude: config.exclude ?? []) { result in
            if case .success(let stations) = result {
                if ConfigClientDebug.debugLog { print("ConfigClient: Fetched \(stations.count) stations from public Azuracast API") }
            }
            completion(result)
        }
    }

    private func tryPublicAzuracastAPI(
        server: String,
        exclude: [String],
        completion: @escaping (Result<[StationConfig], Error>) -> Void
    ) {
        let urlString = "https://\(server)/api/stations"

        guard let url = URL(string: urlString) else {
            completion(.failure(ConfigClientError.urlNotValid))
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                if ConfigClientDebug.debugLog { print("ConfigClient: Public API request failed: \(error)") }
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, 200...299 ~= httpResponse.statusCode else {
                if ConfigClientDebug.debugLog {
                    if let httpResponse = response as? HTTPURLResponse {
                        print("ConfigClient: HTTP \(httpResponse.statusCode) from public API")
                    }
                }
                completion(.failure(ConfigClientError.httpResponseNotValid))
                return
            }

            guard let data = data else {
                completion(.failure(ConfigClientError.dataNotFound))
                return
            }

            do {
                let publicStations = try JSONDecoder().decode([PublicAzuracastStation].self, from: data)
                let filtered = publicStations.filter { !exclude.contains($0.shortcode) }

                // If all stations are excluded, treat as failure to try next config
                guard !filtered.isEmpty else {
                    if ConfigClientDebug.debugLog { print("ConfigClient: All stations excluded from public API") }
                    completion(.failure(ConfigClientError.dataNotFound))
                    return
                }

                let stationConfigs = filtered.map { self.convertFromPublicAzuracastStation($0, serverDomain: server) }
                completion(.success(stationConfigs))
            } catch {
                if ConfigClientDebug.debugLog { print("ConfigClient: Failed to decode public API response: \(error)") }
                completion(.failure(error))
            }
        }

        task.resume()
    }

    private func tryStaticConfig(
        _ config: ConfigSource,
        completion: @escaping (Result<[StationConfig], Error>) -> Void
    ) {
        let stations = config.safeStations
        guard !stations.isEmpty else {
            completion(.failure(ConfigClientError.dataNotValid))
            return
        }

        if ConfigClientDebug.debugLog { print("ConfigClient: Loaded \(stations.count) stations from static config") }
        completion(.success(stations))
    }

    private func convertFromPublicAzuracastStation(_ station: PublicAzuracastStation, serverDomain: String) -> StationConfig {
        return StationConfig(
            name: station.name,
            streamURL: station.listen_url,
            imageURL: "https://\(serverDomain)/static/uploads/\(station.shortcode)/album_art.png",
            desc: station.description,
            longDesc: station.description,
            serverName: serverDomain,
            shortCode: station.shortcode,
            defaultDJ: ""
        )
    }
}

// MARK: - Supporting Types

/// Wrapper for config array from GitHub
struct ConfigWrapper: Codable {
    let configs: [ConfigSource]
}

/// Configuration source type
enum ConfigFormat: String, Codable {
    case azuracast
    case `static`
}

/// A single configuration source (Azuracast or static)
/// All fields except format are optional; validation happens when the config is used
struct ConfigSource: Codable {
    let format: ConfigFormat
    let server: String?
    let exclude: [String]?
    let stations: [[String: String]]?

    /// Safe accessor for server (default: empty string)
    var safeServer: String {
        server ?? ""
    }

    /// Safe accessor for exclude list (default: empty array)
    var safeExclude: [String] {
        exclude ?? []
    }

    /// Safe accessor for stations - converts raw data to StationConfig objects
    var safeStations: [StationConfig] {
        guard let stationDicts = stations else { return [] }
        return stationDicts.compactMap { dict -> StationConfig? in
            guard
                let name = dict["name"],
                let streamURL = dict["streamURL"],
                let imageURL = dict["imageURL"],
                let desc = dict["desc"],
                let longDesc = dict["longDesc"],
                let serverName = dict["serverName"],
                let shortCode = dict["shortCode"],
                let defaultDJ = dict["defaultDJ"]
            else { return nil }

            return StationConfig(
                name: name,
                streamURL: streamURL,
                imageURL: imageURL,
                desc: desc,
                longDesc: longDesc,
                serverName: serverName,
                shortCode: shortCode,
                defaultDJ: defaultDJ
            )
        }
    }

    /// Check if this is a valid Azuracast config
    var isValidAzuracast: Bool {
        format == .azuracast && !safeServer.isEmpty
    }

    /// Check if this is a valid static config
    var isValidStatic: Bool {
        format == .static && !safeStations.isEmpty
    }
}

/// Station data from public Azuracast API (/api/stations)
struct PublicAzuracastStation: Codable {
    let id: Int
    let name: String
    let shortcode: String
    let description: String
    let listen_url: String
    let url: String?
}

// MARK: - Internal Helpers

/// Error types for configuration loading
enum ConfigClientError: Error {
    case urlNotValid
    case dataNotValid
    case dataNotFound
    case fileNotFound
    case httpResponseNotValid
}

/// Debug configuration
struct ConfigClientDebug {
    #if DEBUG
    static let debugLog = true
    #else
    static let debugLog = false
    #endif
}
