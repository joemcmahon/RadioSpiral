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

    // MARK: - CPTemplateApplicationSceneDelegate

    @objc public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        print("[CarPlay] didConnect — stations at connect time: \(StationsManager.shared.stations.count)")
        self.interfaceController = interfaceController

        let stationsTemplate = createStationsListTemplate()
        self.stationsListTemplate = stationsTemplate
        interfaceController.setRootTemplate(stationsTemplate, animated: false, completion: nil)

        StationsManager.shared.addObserver(self)

        let existing = StationsManager.shared.stations
        if !existing.isEmpty {
            print("[CarPlay] stations already loaded (\(existing.count)), refreshing template immediately")
            refreshTemplate(with: existing)
        } else {
            print("[CarPlay] stations empty at connect, fetching…")
            StationsManager.shared.fetch { [weak self] result in
                switch result {
                case .success(let stations):
                    print("[CarPlay] fetch completion: \(stations.count) stations, self=\(self != nil ? "alive" : "nil")")
                    guard !stations.isEmpty else { return }
                    DispatchQueue.main.async { self?.refreshTemplate(with: stations) }
                case .failure(let error):
                    print("[CarPlay] fetch failed: \(error)")
                }
            }
        }
    }

    // MARK: - Template Creation

    /// Updates the displayed sections in the existing stations template.
    private func refreshTemplate(with stations: [RadioStation]) {
        print("[CarPlay] refreshTemplate: \(stations.count) stations, template=\(stationsListTemplate != nil ? "exists" : "nil")")
        guard let template = stationsListTemplate else { return }
        let items = stations.map { createStationListItem(for: $0) }
        template.updateSections([CPListSection(items: items)])
        print("[CarPlay] updateSections called with \(items.count) items")
    }

    /// Creates the stations list template
    private func createStationsListTemplate() -> CPListTemplate {
        let title = "Stations"
        var listItems: [CPListItem] = []

        // Create list items for each station
        for station in StationsManager.shared.stations {
            let listItem = createStationListItem(for: station)
            listItems.append(listItem)
        }

        let section = CPListSection(items: listItems)
        let template = CPListTemplate(title: title, sections: [section])

        return template
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

        if let station = station {
            nowPlayingInfo[MPMediaItemPropertyTitle] = station.name
        }

        let client = ACWebSocketClient.shared
        nowPlayingInfo[MPMediaItemPropertyArtist] = client.status.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = client.status.track
        let duration = client.status.duration
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration > 0 ? duration : 0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = client.status.elapsed > 0 ? client.status.elapsed : 0.0
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
    }
}

// MARK: - StationsManagerObserver

extension CarPlaySceneDelegate: StationsManagerObserver {
    func stationsManager(_ manager: StationsManager, stationsDidUpdate stations: [RadioStation]) {
        print("[CarPlay] stationsDidUpdate: \(stations.count) stations")
        guard !stations.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in self?.refreshTemplate(with: stations) }
    }

    func stationsManager(_ manager: StationsManager, stationDidChange station: RadioStation?) {}
}
