//
//  StationsManager.swift
//  SwiftRadio
//
//  Created by Fethi El Hassasna on 2022-11-02.
//  Copyright © 2022 matthewfecher.com. All rights reserved.
//

import UIKit
import MediaPlayer
import Combine

protocol StationsManagerObserver: AnyObject {
    func stationsManager(_ manager: StationsManager, stationsDidUpdate stations: [RadioStation])
    func stationsManager(_ manager: StationsManager, stationDidChange station: RadioStation?)
}

extension StationsManagerObserver {
    func stationsManager(_ manager: StationsManager, stationsDidUpdate stations: [RadioStation]) {}
}

class StationsManager {
    
    static let shared = StationsManager()
    
    private(set) var stations: [RadioStation] = [] {
        didSet {
            notifiyObservers { observer in
                observer.stationsManager(self, stationsDidUpdate: stations)
            }
        }
    }
    
    private(set) var currentStation: RadioStation? {
        didSet {
            notifiyObservers { observer in
                observer.stationsManager(self, stationDidChange: currentStation)
            }
            
            resetArtwork(with: currentStation)
            
            // Connect to new station's metadata
            if let station = currentStation {
                metadataManager.connectToStation(station)
            } else {
                metadataManager.disconnectCurrentStation()
            }
        }
    }
        
    var searchedStations: [RadioStation] = []

    /// CarPlay's Now Playing screen shows only title and artist, so while it's connected
    /// CarPlaySceneDelegate flips this on a timer and the artist line alternates with the
    /// station name. Shared with the lock screen; there's no CarPlay-only Now Playing info.
    var showsStationInArtistLine = false {
        didSet {
            guard showsStationInArtistLine != oldValue else { return }
            refreshArtistLine()
        }
    }
    
    private var observations = [ObjectIdentifier : Observation]()
    private let player = RadioPlayer.shared
    private let metadataManager = StationMetadataManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupMetadataObserver()
        setupPlaybackStateObserver()
        setupConnectionStateObserver()
    }
    
    func fetch(_ completion: StationsCompletion? = nil) {
        DataManager.getStation { [weak self] result in
            guard case .success(let stations) = result, self?.stations != stations else {
                completion?(result)
                return
            }
            
            self?.stations = stations
            
            // Reset everything if the new stations list doesn't have the current station
            if let currentStation = self?.currentStation, self?.stations.firstIndex(of: currentStation) == nil {
                self?.reset()
            }
            
            completion?(result)
        }
    }
    
    func set(station: RadioStation?) {
        guard let station = station else {
            reset()
            return
        }

        // The same station again (a tap on the playing station in CarPlay) must not reconnect the
        // metadata or reset the stream URL, which restarts the audio. Equality covers the name,
        // stream URL, image and descriptions, so a changed station still goes through.
        guard station != currentStation else { return }

        currentStation = station
        player.radioURL = URL(string: station.streamURL)
    }
    
    func setNext() {
        guard let index = getIndex(of: currentStation) else { return }
        let station = (index + 1 == stations.count) ? stations[0] : stations[index + 1]
        currentStation = station
        player.radioURL = URL(string: station.streamURL)
    }
    
    func setPrevious() {
        guard let index = getIndex(of: currentStation), let station = (index == 0) ? stations.last : stations[index - 1] else { return }
        currentStation = station
        player.radioURL = URL(string: station.streamURL)
    }
    
    // Refreshes the audio stream connection for the current station.
    // Does NOT re-assign currentStation to avoid triggering the full
    // station-change cycle (observers, metadata reconnect, player.stop()).
    func reloadCurrent() {
        guard let station = currentStation else { return }
        player.radioURL = URL(string: station.streamURL)
    }
    
    func updateSearch(with filter: String) {
        searchedStations.removeAll(keepingCapacity: false)
        searchedStations = stations.filter { $0.name.range(of: filter, options: [.caseInsensitive]) != nil }
    }
    
    private func reset() {
        currentStation = nil
        player.radioURL = nil
    }
    
    private func getIndex(of station: RadioStation?) -> Int? {
        guard let station = station, let index = stations.firstIndex(of: station) else { return nil }
        return index
    }
    
    private func setupMetadataObserver() {
        // Subscribe to metadata changes from the unified metadata manager
        metadataManager.subscribeToMetadataChanges { [weak self] metadata in
            DispatchQueue.main.async {
                self?.handleMetadataUpdate(metadata)
            }
        }
    }

    /// The metadata only notifies when it changes, and an offline channel can keep the same fallback
    /// metadata, so the lock screen and CarPlay title follow the connection state directly (task-44).
    private func setupConnectionStateObserver() {
        metadataManager.$connectionState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTitle() }
            .store(in: &cancellables)
    }

    /// Rewrites only the title: the channel's notice, or the track's own once nothing is wrong.
    private func refreshTitle() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        if let notice = ChannelStatusMessages.nowPlayingTitle(connection: metadataManager.connectionState) {
            nowPlayingInfo[MPMediaItemPropertyTitle] = notice
        } else if let metadata = metadataManager.getCurrentMetadata() {
            nowPlayingInfo[MPMediaItemPropertyTitle] = metadata.trackName
        } else {
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func setupPlaybackStateObserver() {
        // Update lock screen playback rate when player state changes
        player.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateLockScreenPlaybackRate(isPlaying: state == .playing)
                if state == .playing { self?.metadataManager.reconnectForPlayback() }
            }
            .store(in: &cancellables)
    }
    
    private func handleMetadataUpdate(_ metadata: UnifiedMetadata?) {
        updateLockScreen(with: metadata)
    }
}

// MARK: - StationsManager Observation

extension StationsManager {
    
    private struct Observation {
        weak var observer: StationsManagerObserver?
    }
    
    func addObserver(_ observer: StationsManagerObserver) {
        let id = ObjectIdentifier(observer)
        observations[id] = Observation(observer: observer)
    }

    private func notifiyObservers(with action: (_ observer: StationsManagerObserver) -> Void) {
        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }
            
            action(observer)
        }
    }
}

// MARK: - MPNowPlayingInfoCenter (Lock screen)

extension StationsManager {
    
    private func resetArtwork(with station: RadioStation?) {
        
        guard let station = station else {
            updateLockScreen(with: nil)
            return
        }
        
        station.getImage { [weak self] image in
            self?.updateLockScreen(with: nil)
        }
    }
    
    private func updateLockScreenPlaybackRate(isPlaying: Bool) {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func artistLine(for artist: String) -> String {
        guard showsStationInArtistLine, let station = currentStation else { return artist }
        return station.name
    }

    /// Rewrites only the artist line, keeping the artwork and everything else.
    private func refreshArtistLine() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo,
              let metadata = metadataManager.getCurrentMetadata() else { return }
        nowPlayingInfo[MPMediaItemPropertyArtist] = artistLine(for: metadata.artistName)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateLockScreen(with metadata: UnifiedMetadata?) {
        let nowPLayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = nowPLayingInfoCenter.nowPlayingInfo ?? [String : Any]()
        if let metadata = metadata {
            nowPlayingInfo = Self.trackInfo(from: nowPlayingInfo, metadata: metadata,
                                            artistLine: artistLine(for: metadata.artistName),
                                            notice: ChannelStatusMessages.nowPlayingTitle(connection: metadataManager.connectionState))
            if let artworkURL = metadata.artworkURL {
                URLSession.shared.dataTask(with: artworkURL) { [weak self] data, response, error in
                    if let data = data, let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ in
                                return image
                            })
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                        }
                    } else {
                        self?.publishWithStationArtwork(nowPlayingInfo)
                    }
                }.resume()
                return // Only set nowPlayingInfo after artwork is ready
            }
            // No artwork for this track: show the station's.
            publishWithStationArtwork(nowPlayingInfo)
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    /// Publishes `info` with the current station's art, or without any art if there is no station.
    private func publishWithStationArtwork(_ info: [String: Any]) {
        guard let station = currentStation else {
            DispatchQueue.main.async { MPNowPlayingInfoCenter.default().nowPlayingInfo = info }
            return
        }
        station.getImage { image in
            DispatchQueue.main.async {
                var info = info
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ in image })
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
}

extension StationsManager {

    /// The lock screen's info for a new track, built on top of what's there now.
    /// - Parameter notice: What to show as the title instead of the track's, when the channel is offline or
    ///   can't be described (task-44). Nil keeps the track's title.
    static func trackInfo(from existing: [String: Any], metadata: UnifiedMetadata, artistLine: String,
                          notice: String? = nil) -> [String: Any] {
        var info = existing
        // The previous track's art never carries over; the caller sets this track's art
        // (or the station's) when it has it.
        info[MPMediaItemPropertyArtwork] = nil
        info[MPMediaItemPropertyArtist] = artistLine
        info[MPMediaItemPropertyTitle] = notice ?? metadata.trackName
        info[MPMediaItemPropertyAlbumTitle] = metadata.albumName
        if metadata.isLiveDJ {
            // A live show's duration and elapsed time are the silent placeholder track's: about
            // 12 minutes that mean nothing and keep resetting. Publish it as a live stream, with
            // no time, and drop any time left over from the previous track.
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
            info[MPMediaItemPropertyPlaybackDuration] = nil
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = nil
        } else {
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
            if let duration = metadata.duration {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = metadata.elapsed ?? 0.0
        }
        // Always set rate to 1.0 when receiving metadata — we're actively streaming.
        // Play/pause state changes update the rate separately via setupPlaybackStateObserver.
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        return info
    }
}
