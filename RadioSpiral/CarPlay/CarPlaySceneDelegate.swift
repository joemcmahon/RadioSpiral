//
//  CarPlaySceneDelegate.swift
//  RadioSpiral
//
//  Created on 2025-11-11.
//

import CarPlay
import MediaPlayer

/// CarPlay scene delegate for modern CarPlay framework (iOS 14+)
/// Handles CarPlay interface setup, station browsing, and playback
@objc public class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    var interfaceController: CPInterfaceController?
    private var stationsListTemplate: CPListTemplate?
    /// Alternates the Now Playing artist line between artist and station name.
    private var stationNameTimer: Timer?
    private static let stationNameInterval: TimeInterval = 10

    // MARK: - CPTemplateApplicationSceneDelegate

    @objc public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let stationsTemplate = createStationsListTemplate()
        self.stationsListTemplate = stationsTemplate
        interfaceController.setRootTemplate(stationsTemplate, animated: false, completion: nil)

        StationsManager.shared.addObserver(self)
        restartStationNameTimer()

        let existing = StationsManager.shared.stations
        if !existing.isEmpty {
            refreshTemplate(with: existing)
        } else {
            StationsManager.shared.fetch { [weak self] result in
                switch result {
                case .success(let stations):
                    guard !stations.isEmpty else { return }
                    DispatchQueue.main.async { self?.refreshTemplate(with: stations) }
                case .failure:
                    break
                }
            }
        }
    }

    // MARK: - Template Creation

    /// Updates the displayed sections in the existing stations template.
    private func refreshTemplate(with stations: [RadioStation]) {
        guard let template = stationsListTemplate else { return }
        template.updateSections([stationsSection(for: stations)])
    }

    /// Until a station is loaded, Play on the Now Playing screen has nothing to play,
    /// so the header prompts the user to pick one.
    private func stationsSection(for stations: [RadioStation]) -> CPListSection {
        let items = stations.map { createStationListItem(for: $0) }
        let prompt = StationsManager.shared.currentStation == nil ? "Select a station to start" : nil
        // CPListTemplate's title can't change after creation, so the test-server label goes here.
        let testLabel = StationServer.current == .test ? "TEST server" : nil
        let header = [testLabel, prompt].compactMap { $0 }.joined(separator: " · ")
        return CPListSection(items: items, header: header.isEmpty ? nil : header, sectionIndexTitle: nil)
    }

    /// Creates the stations list template
    private func createStationsListTemplate() -> CPListTemplate {
        let section = stationsSection(for: StationsManager.shared.stations)
        return CPListTemplate(title: "Stations", sections: [section])
    }

    /// Creates a list item for a single station
    private func createStationListItem(for station: RadioStation) -> CPListItem {
        let listItem = CPListItem(
            text: station.name,
            detailText: station.desc
        )

        // Set station artwork if available
        station.getImage { image in
            listItem.setImage(image)
        }

        // Handle station selection
        listItem.handler = { [weak self] item, completionHandler in
            self?.selectStation(station, completionHandler: completionHandler)
        }

        return listItem
    }

    /// Called when user selects a station
    private func selectStation(
        _ station: RadioStation,
        completionHandler: @escaping () -> Void
    ) {
        StationsManager.shared.set(station: station)
        RadioPlayer.shared.play()
        updateMPNowPlayingInfo(station: station)
        completionHandler()
    }

    /// Updates the MPNowPlayingInfoCenter for system integration
    private func updateMPNowPlayingInfo(station: RadioStation?) {
        var nowPlayingInfo = [String: Any]()

        // Until the new station's metadata arrives, show only its name: the socket
        // client's status still describes the previous station's track.
        if let station = station {
            nowPlayingInfo[MPMediaItemPropertyTitle] = station.name
        }

        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

        if let station = station {
            station.getImage { image in
                let artworkItem = MPMediaItemArtwork(boundsSize: image.size) { _ in
                    return image
                }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artworkItem
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
}

// MARK: - CPTemplateApplicationScene Disconnect

extension CarPlaySceneDelegate {
    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        self.stationsListTemplate = nil
        stationNameTimer?.invalidate()
        stationNameTimer = nil
        StationsManager.shared.showsStationInArtistLine = false
    }

    /// Shows the station name now, then swaps it with the artist every 10 s.
    /// With a single station there's nothing to tell apart, so the artist stays.
    private func restartStationNameTimer() {
        stationNameTimer?.invalidate()
        stationNameTimer = nil
        let manager = StationsManager.shared
        guard interfaceController != nil, manager.stations.count > 1 else {
            manager.showsStationInArtistLine = false
            return
        }
        manager.showsStationInArtistLine = true
        stationNameTimer = Timer.scheduledTimer(withTimeInterval: Self.stationNameInterval, repeats: true) { _ in
            manager.showsStationInArtistLine.toggle()
        }
    }
}

// MARK: - StationsManagerObserver

extension CarPlaySceneDelegate: StationsManagerObserver {
    func stationsManager(_ manager: StationsManager, stationsDidUpdate stations: [RadioStation]) {
        guard !stations.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.refreshTemplate(with: stations)
            self?.restartStationNameTimer()
        }
    }

    func stationsManager(_ manager: StationsManager, stationDidChange station: RadioStation?) {
        // Show or hide the "Select a station to start" header.
        DispatchQueue.main.async { [weak self] in
            self?.refreshTemplate(with: manager.stations)
            self?.restartStationNameTimer()
        }
    }
}
