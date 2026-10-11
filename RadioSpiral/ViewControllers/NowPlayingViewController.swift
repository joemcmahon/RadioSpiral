//
//  NowPlayingViewController.swift
//  Swift Radio
//
//  Created by Matthew Fecher on 7/22/15.
//  Copyright (c) 2015 MatthewFecher.com. All rights reserved.
//

import UIKit
import MediaPlayer
import AVKit
import Combine
import Spring
import Kingfisher

protocol NowPlayingViewControllerDelegate: AnyObject {
    func didTapInfoButton(_ nowPlayingViewController: NowPlayingViewController, station: RadioStation?)
    func didTapShareButton(_ nowPlayingViewController: NowPlayingViewController, station: RadioStation, artworkURL: URL?)
}

class NowPlayingViewController: UIViewController {
    
    weak var delegate: NowPlayingViewControllerDelegate?
    private let metadataManager = StationMetadataManager.shared
    
    // MARK: - IB UI
    
    @IBOutlet var albumHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var albumImageView: SpringImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var releaseLabel: SpringLabel!
    @IBOutlet weak var playingButton: UIButton!
    @IBOutlet weak var songLabel: SpringLabel!
    @IBOutlet weak var volumeParentView: UIView!
    @IBOutlet weak var previousButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var airPlayView: UIView!
    @IBOutlet weak var djName: UILabel!
    @IBOutlet weak var liveDJIndicator: UIButton!
    @IBOutlet weak var infoButton: UIButton!

    // MARK: - Landscape Layout Outlets

    @IBOutlet weak var controlsStackView: UIStackView!
    @IBOutlet weak var volumeStackView: UIStackView!
    @IBOutlet weak var labelsStackView: UIStackView!
    @IBOutlet weak var toolsView: UIView!

    // Portrait constraints (deactivated in landscape — strong refs prevent deallocation)
    @IBOutlet var portraitAlbumTop: NSLayoutConstraint!
    @IBOutlet var portraitAlbumCenterX: NSLayoutConstraint!
    @IBOutlet var portraitAlbumAspectRatio: NSLayoutConstraint!
    @IBOutlet var portraitAlbumTrailing: NSLayoutConstraint!
    @IBOutlet var portraitControlsTop: NSLayoutConstraint!
    @IBOutlet var portraitControlsCenterX: NSLayoutConstraint!
    @IBOutlet var portraitVolumeTop: NSLayoutConstraint!
    @IBOutlet var portraitVolumeLeading: NSLayoutConstraint!
    @IBOutlet var portraitVolumeTrailing: NSLayoutConstraint!
    @IBOutlet var portraitLabelsTop: NSLayoutConstraint!
    @IBOutlet var portraitLabelsLeading: NSLayoutConstraint!
    @IBOutlet var portraitLabelsTrailing: NSLayoutConstraint!
    @IBOutlet var portraitInfoCenterY: NSLayoutConstraint!
    @IBOutlet var portraitInfoLeading: NSLayoutConstraint!

    // Landscape layout
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private var allPortraitConstraints: [NSLayoutConstraint] = []
    private var landscapeRightPanel: UIView?

    /// Which arrangement the Now Playing screen is in.
    private enum NowPlayingLayout {
        case portrait
        case landscape
        /// iPhone Duo inner display, wider than tall (fully open or book): art and controls
        /// sit in equal halves on either side of the vertical fold.
        case foldWide
    }
    private var currentLayout: NowPlayingLayout?

    // Constraints placing labels/volume/controls inside landscapeRightPanel (landscape and foldWide).
    private var panelContentConstraints: [NSLayoutConstraint] = []
    private var foldWideConstraints: [NSLayoutConstraint] = []
    /// Outer-edge constraints for foldWide; constants track the safe-area insets.
    private var foldWideEdgeConstraints: [NSLayoutConstraint] = []
    /// Storyboard constraint centering AirPlay in the full-width toolbar (swapped out in foldWide).
    private var airPlayToolbarCenterX: NSLayoutConstraint?
    /// Label fonts as loaded (after iPad scaling), so per-layout scaling never compounds.
    private var baseLabelFonts: [(UILabel, UIFont)] = []

    // MARK: - Properties
    
    private let player = RadioPlayer.shared
    private let manager = StationsManager.shared
    
    var isNewStation = true
    var nowPlayingImageView: UIImageView!
    
    var mpVolumeSlider: UISlider?
    private var metadataCallback: MetadataChangeCallback?
    private var lastStatusMessage: String?
    private var wasPlaying = false
    private var cancellables = Set<AnyCancellable>()
    private var connectionBanner: UILabel!
    private var timeBubble: UILabel!
    private var modeButton: UIButton!
    private var timeUpdateTimer: Timer?
    private var metadataReceivedAt: Date?
    private var metadataElapsed: TimeInterval = 0
    private var metadataDuration: TimeInterval = 0
    private var broadcastStart: Date?

    // MARK: - ViewDidLoad
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupFoldDiagnostics()  // TEMP (task-19): remove once Duo layouts are tuned

        navigationItem.largeTitleDisplayMode = .never
        if manager.stations.count < 2 {
            navigationItem.hidesBackButton = true
        }
        manager.addObserver(self)
        
        setupLandscapeConstraints()
        // currentLayout starts nil, so the first pass always applies a layout.
        optimizeForDeviceSize(size: view.bounds.size)
        
        // Create Now Playing BarItem
        createNowPlayingAnimation()
        
        // Set View Title
        self.title = manager.currentStation?.name
        
        // Accessibility identifiers for UI testing
        playingButton.accessibilityIdentifier = "playPauseButton"
        infoButton.accessibilityIdentifier = "infoButton"

        // Scale UI elements for iPad
        if traitCollection.userInterfaceIdiom == .pad {
            let scale: CGFloat = 1.4
            songLabel.font = songLabel.font.withSize(songLabel.font.pointSize * scale)
            artistLabel.font = artistLabel.font.withSize(artistLabel.font.pointSize * scale)
            releaseLabel.font = releaseLabel.font.withSize(releaseLabel.font.pointSize * scale)

            // Scale play/prev/next buttons
            for button in [playingButton, previousButton, nextButton] {
                guard let button = button else { continue }
                for constraint in button.constraints {
                    if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                        constraint.constant *= scale
                    }
                }
            }

            // Scale toolbar icons (info, share, AirPlay) and toolbar height
            for button in [infoButton] as [UIView?] {
                guard let button = button else { continue }
                for constraint in button.constraints {
                    if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                        constraint.constant *= scale
                    }
                }
            }
            for constraint in airPlayView.constraints {
                if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                    constraint.constant *= scale
                }
            }
            // Find share button by accessibility identifier and scale it
            if let shareButton = toolsView.subviews.first(where: { $0.accessibilityIdentifier == "shareButton" }) {
                for constraint in shareButton.constraints {
                    if constraint.firstAttribute == .width || constraint.firstAttribute == .height {
                        constraint.constant *= scale
                    }
                }
            }
            // Scale toolsView height
            for constraint in toolsView.constraints {
                if constraint.firstAttribute == .height {
                    constraint.constant *= scale
                }
            }
        }

        baseLabelFonts = [songLabel, artistLabel, releaseLabel].map { ($0, $0.font) }
        applyLabelScale(for: currentLayout ?? .portrait, size: view.bounds.size)

        // Set UI
        djName.text = ""
        liveDJIndicator.isHidden = true
        
        // Check for station change
        if isNewStation {
            stationDidChange()
        } else {
            updateTrackArtwork()
            playerStateDidChange(player.state, animate: false)
        }
        
        // Setup connection status banner
        setupConnectionBanner()

        // Setup time bubble overlay
        setupTimeBubble()

        // Setup volumeSlider
        setupVolumeSlider()
        
        // Setup AirPlayButton
        setupAirPlayButton()
        
        // Hide / Show Next/Previous buttons
        previousButton.isHidden = Config.hideNextPreviousButtons
        nextButton.isHidden = Config.hideNextPreviousButtons
        
        // Subscribe to unified metadata changes
        metadataCallback = { [weak self] metadata in
            self?.handleMetadataUpdate(metadata)
        }
        metadataManager.subscribeToMetadataChanges(metadataCallback!)

        // Observe connection state for audio restart after WiFi recovery.
        // Use removeDuplicates + scan to detect transitions TO .connected
        // from a non-connected state. Only restart the audio player -
        // do NOT call reloadCurrent() as that triggers connectToStation()
        // via currentStation didSet, creating a feedback loop.
        metadataManager.$connectionState
            .removeDuplicates()
            .scan((MetadataConnectionState.disconnected, MetadataConnectionState.disconnected)) { previous, current in
                (previous.1, current)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (previous, current) in
                guard let self = self else { return }
                if current == .connected && previous != .connected {
                    self.hideConnectionBanner()
                    if self.wasPlaying {
                        self.player.radioURL = URL(string: self.manager.currentStation?.streamURL ?? "")
                        self.player.play()
                    }
                } else if current == .disconnected && previous == .connected {
                    self.showConnectionBanner("Connection lost — reconnecting…")
                    if self.wasPlaying {
                        // Stop AVPlayer to prevent aggressive internal retries while offline.
                        // wasPlaying stays true so audio restarts on recovery.
                        self.player.stop()
                    }
                } else if current == .connecting {
                    self.showConnectionBanner("Reconnecting…")
                }
            }
            .store(in: &cancellables)

        // Observe playback state changes (dropFirst skips the initial
        // .stopped emission — viewDidLoad already sets initial UI state)
        RadioPlayer.shared.$playbackState
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playbackState in
                guard let self = self else { return }
                if playbackState == .playing {
                    // Mirror external play starts (e.g. CarPlay) so reconnect-on-recovery works.
                    self.wasPlaying = true
                    self.hideConnectionBanner()
                }
                self.playbackStateDidChange(playbackState, animate: true)
            }
            .store(in: &cancellables)

        // Observe player state changes (dropFirst skips initial .idle)
        RadioPlayer.shared.$state
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                self.playerStateDidChange(state, animate: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStabilityModeChange),
            name: RadioPlayer.stabilityModeDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHearingAidStateOrPreferenceChange),
            name: RadioPlayer.hearingAidStateDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleHearingAidStateOrPreferenceChange),
            name: AudioStabilityPreference.didChange, object: nil)

        isPlayingDidChange(player.isPlaying)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Hearing aids may have been detected before this screen existed.
        showStabilityBannerIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startTimeUpdates()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTimeUpdates()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
            self.optimizeForDeviceSize(size: size)
        })
    }
    
    func handleMetadataUpdate(_ metadata: UnifiedMetadata?) {
        guard let metadata = metadata else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update UI with unified metadata
            self.artistLabel.text = metadata.artistName
            self.songLabel.text = metadata.trackName
            self.releaseLabel.text = metadata.albumName ?? ""
            self.djName.text = metadata.djName ?? ""
            
            // Update live DJ indicator
            self.liveDJIndicator.isHidden = !metadata.isLiveDJ

            // Update time tracking for bubble
            self.metadataReceivedAt = Date()
            self.metadataElapsed = metadata.elapsed ?? 0
            self.metadataDuration = metadata.duration ?? 0
            self.broadcastStart = metadata.broadcastStart
            self.updateTimeBubbleText()

            // Update artwork
            if let artworkURL = metadata.artworkURL {
                let processor = DownsamplingImageProcessor(size: self.albumImageView.bounds.size)
                self.albumImageView.kf.indicatorType = .activity
                self.albumImageView.kf.setImage(with: artworkURL,
                                               options: [.processor(processor),
                                                         .scaleFactor(UIScreen.main.scale),
                                                         .transition(.fade(1))
                                               ])
            } else {
                // Fallback to station artwork
                self.manager.currentStation?.getImage { [weak self] image in
                    self?.albumImageView.image = image
                }
            }
        }
    }
              
    // MARK: - Setup
    
    func setupConnectionBanner() {
        connectionBanner = UILabel()
        connectionBanner.textAlignment = .center
        connectionBanner.textColor = .white
        connectionBanner.font = .systemFont(ofSize: 14, weight: .medium)
        connectionBanner.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        connectionBanner.layer.cornerRadius = 8
        connectionBanner.clipsToBounds = true
        connectionBanner.alpha = 0
        connectionBanner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectionBanner)
        NSLayoutConstraint.activate([
            connectionBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            connectionBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectionBanner.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
            connectionBanner.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func showConnectionBanner(_ message: String) {
        connectionBanner.text = "  \(message)  "
        UIView.animate(withDuration: 0.3) {
            self.connectionBanner.alpha = 1
        }
    }

    private func hideConnectionBanner() {
        UIView.animate(withDuration: 0.5) {
            self.connectionBanner.alpha = 0
        }
    }

    func setupTimeBubble() {
        timeBubble = UILabel()
        timeBubble.textAlignment = .left
        timeBubble.textColor = .white
        timeBubble.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        timeBubble.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        timeBubble.layer.cornerRadius = 12
        timeBubble.clipsToBounds = true
        timeBubble.text = " --:--    "
        timeBubble.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timeBubble)
        NSLayoutConstraint.activate([
            timeBubble.centerXAnchor.constraint(equalTo: albumImageView.centerXAnchor),
            timeBubble.topAnchor.constraint(equalTo: albumImageView.bottomAnchor),
            timeBubble.heightAnchor.constraint(equalToConstant: 30),
        ])

        timeBubble.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(timeBubbleTapped))
        timeBubble.addGestureRecognizer(tap)

        setupModeButton()
        updateTimeBubbleText()

        startTimeUpdates()
    }

    /// Audio-mode button beside the time bubble. Opens the compensation-mode picker.
    private func setupModeButton() {
        var config = UIButton.Configuration.filled()
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.7)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        modeButton = UIButton(configuration: config)
        modeButton.accessibilityLabel = "Audio compensation mode"
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.isHidden = true
        modeButton.addTarget(self, action: #selector(timeBubbleTapped), for: .touchUpInside)
        view.addSubview(modeButton)
        NSLayoutConstraint.activate([
            modeButton.leadingAnchor.constraint(equalTo: timeBubble.trailingAnchor, constant: 8),
            modeButton.centerYAnchor.constraint(equalTo: timeBubble.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 36),
            modeButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    /// One indicator for the single, output-independent preference:
    /// a lock (blue = pitch, orange = continuous audio) when locked, or an ear under
    /// Auto-select while hearing aids are driving the mode. Hidden otherwise.
    private func updateModeButton() {
        guard let modeButton = modeButton else { return }
        let symbol: String
        let color: UIColor
        switch AudioStabilityPreference.current {
        case .alwaysStability:
            symbol = "lock.fill"; color = .systemBlue
        case .neverStability:
            symbol = "lock.fill"; color = .systemOrange
        case .ask:
            symbol = "ear.and.waveform"; color = .white
        }
        modeButton.configuration?.image = UIImage(systemName: symbol)
        modeButton.configuration?.baseForegroundColor = color
        modeButton.isHidden = AudioStabilityPreference.current == .ask
            && !RadioPlayer.shared.isUsingHearingAids()
    }

    private func startTimeUpdates() {
        stopTimeUpdates()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateTimeBubbleText()
        }
    }

    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    private func updateTimeBubbleText() {
        let leftPadding = "  "
        let rightPadding = "  "
        updateModeButton()
        guard metadataReceivedAt != nil else {
            timeBubble.text = leftPadding + "--:--" + rightPadding
            return
        }
        if let broadcastStart = broadcastStart {
            // Live DJ: show time into the show
            let showElapsed = Date().timeIntervalSince(broadcastStart)
            timeBubble.text = leftPadding + "LIVE  \(formatTime(showElapsed))" + rightPadding
        } else if metadataDuration > 0 {
            // Pre-recorded track: show track elapsed / duration
            let currentElapsed = metadataElapsed + Date().timeIntervalSince(metadataReceivedAt!)
            timeBubble.text = leftPadding + "\(formatTime(currentElapsed)) / \(formatTime(metadataDuration))" + rightPadding
        } else {
            // No broadcast start, no duration — fallback
            let currentElapsed = metadataElapsed + Date().timeIntervalSince(metadataReceivedAt!)
            timeBubble.text = leftPadding + "\(formatTime(currentElapsed))" + rightPadding
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    func setupVolumeSlider() {
        // Note: This slider implementation uses a MPVolumeView
        // The volume slider only works in devices, not the simulator.
        for subview in MPVolumeView().subviews {
            guard let volumeSlider = subview as? UISlider else { continue }
            mpVolumeSlider = volumeSlider
        }
        
        guard let mpVolumeSlider = mpVolumeSlider else { return }
        
        volumeParentView.addSubview(mpVolumeSlider)
        
        mpVolumeSlider.translatesAutoresizingMaskIntoConstraints = false
        mpVolumeSlider.leftAnchor.constraint(equalTo: volumeParentView.leftAnchor).isActive = true
        mpVolumeSlider.rightAnchor.constraint(equalTo: volumeParentView.rightAnchor).isActive = true
        mpVolumeSlider.centerYAnchor.constraint(equalTo: volumeParentView.centerYAnchor).isActive = true
        
        mpVolumeSlider.setThumbImage(#imageLiteral(resourceName: "slider-ball"), for: .normal)
    }
    
    func setupAirPlayButton() {
        let airPlayButton = AVRoutePickerView(frame: airPlayView.bounds)
        airPlayButton.activeTintColor = .white
        airPlayButton.tintColor = .gray
        airPlayButton.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        airPlayView.backgroundColor = .clear
        airPlayView.addSubview(airPlayButton)
    }
    
    func stationDidChange() {
        albumImageView.image = nil
        manager.currentStation?.getImage { [weak self] image in
            self?.albumImageView.image = image
        }
        title = manager.currentStation?.name
        updateLabels()
        player.stop()
        // Remove only the previous UI metadata subscriber, not all subscribers
        if let callback = metadataCallback {
            metadataManager.unsubscribeFromMetadataChanges(callback)
        }
        metadataCallback = { [weak self] metadata in
            self?.handleMetadataUpdate(metadata)
        }
        metadataManager.subscribeToMetadataChanges(metadataCallback!)
    }
    
    // MARK: - Player Controls (Play/Pause/Volume)
        
    @IBAction func playingPressed(_ sender: Any) {
        if player.isPlaying {
            wasPlaying = false
            player.stop()
        } else {
            wasPlaying = true
            manager.reloadCurrent()  // Reconnect to stream
            player.play()
            updateLabels()
        }
    }
        
    @IBAction func nextPressed(_ sender: Any) {
        manager.setNext()
        updateLabels()
    }
    
    @IBAction func previousPressed(_ sender: Any) {
        manager.setPrevious()
        updateLabels()
    }
    
    // Update track with new artwork
    func updateTrackArtwork() {
        // Artwork updates are now handled by the unified metadata system
        // This method is kept for backward compatibility but delegates to metadata manager
        if let metadata = metadataManager.getCurrentMetadata(), let artworkURL = metadata.artworkURL {
            let processor = DownsamplingImageProcessor(size: albumImageView.bounds.size)
            Task {
                albumImageView.kf.indicatorType = .activity
                albumImageView.kf.setImage(with: artworkURL,
                                           options: [.processor(processor),
                                                     .scaleFactor(UIScreen.main.scale),
                                                     .transition(.fade(1))
                                           ])
            }
        } else {
            if manager.currentStation == nil { return }
            if manager.currentStation?.defaultArtwork != nil {
                self.albumImageView.image = manager.currentStation?.defaultArtwork
            } else {
                manager.currentStation?.getImage { [weak self] image in
                    self?.albumImageView.image = image
                }
            }
        }
    }
    
    private func isPlayingDidChange(_ isPlaying: Bool) {
        playingButton.isSelected = isPlaying
        startNowPlayingAnimation(isPlaying)
    }
    
    func playbackStateDidChange(_ playbackState: RadioPlayer.PlaybackState, animate: Bool) {
        let message: String?
        switch playbackState {
        case .paused:
            message = "Station Paused..."
        case .playing:
            message = nil
        case .stopped:
            message = "Station Stopped..."
        }
        updateLabels(with: message, animate: animate)
        isPlayingDidChange(player.isPlaying)
    }
    
    func playerStateDidChange(_ state: RadioPlayer.State, animate: Bool) {
        let message: String?
        switch state {
        case .loading:
            if songLabel.text != "" {
                message = songLabel.text
            } else {
                message = "Station loading..."
            }
        case .idle:
            message = "Station URL not valid"
        case .readyToPlay:
            playbackStateDidChange(player.playbackState, animate: animate)
            return
        case .error:
            message = "Error playing stream"
        }
        updateLabels(with: message, animate: animate)
    }
    
    // MARK: - UI Helper Methods
    
    func setupLandscapeConstraints() {
        let safeArea = view.safeAreaLayoutGuide
        let artWidthFraction: CGFloat = (UIDevice.current.userInterfaceIdiom == .pad) ? 0.35 : 0.40

        // Container for right-side controls — vertically centered on iPad
        let rightPanel = UIView()
        rightPanel.translatesAutoresizingMaskIntoConstraints = false
        landscapeRightPanel = rightPanel

        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        // Labels, volume and controls stacked inside the panel (shared by landscape and foldWide).
        panelContentConstraints = [
            labelsStackView.topAnchor.constraint(equalTo: rightPanel.topAnchor),
            labelsStackView.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            labelsStackView.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),

            volumeStackView.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            volumeStackView.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
            { let c = volumeStackView.topAnchor.constraint(equalTo: labelsStackView.bottomAnchor, constant: 12)
              c.priority = .defaultHigh
              return c }(),
            volumeStackView.topAnchor.constraint(greaterThanOrEqualTo: labelsStackView.bottomAnchor, constant: 4),

            controlsStackView.centerXAnchor.constraint(equalTo: rightPanel.centerXAnchor),
            { let c = controlsStackView.topAnchor.constraint(equalTo: volumeStackView.bottomAnchor, constant: 4)
              c.priority = .defaultHigh
              return c }(),
            controlsStackView.topAnchor.constraint(greaterThanOrEqualTo: volumeStackView.bottomAnchor, constant: 2),
            controlsStackView.bottomAnchor.constraint(equalTo: rightPanel.bottomAnchor),
        ]

        landscapeConstraints = [
            // Album art: left side, fills height
            albumImageView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 12),
            albumImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: artWidthFraction),
            albumImageView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            albumImageView.bottomAnchor.constraint(equalTo: toolsView.topAnchor, constant: -8),

            // Right panel: positioned between art and trailing edge
            rightPanel.leadingAnchor.constraint(equalTo: albumImageView.trailingAnchor, constant: 24),
            rightPanel.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -12),
            isPad
                ? rightPanel.centerYAnchor.constraint(equalTo: albumImageView.centerYAnchor)
                : rightPanel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            rightPanel.bottomAnchor.constraint(lessThanOrEqualTo: toolsView.topAnchor, constant: -4),

            // Info button: left side of toolbar area in landscape
            infoButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 20),
            infoButton.centerYAnchor.constraint(equalTo: toolsView.centerYAnchor),
        ]

        setupFoldWideConstraints(rightPanel: rightPanel)

        allPortraitConstraints = [
            portraitAlbumTop,
            portraitAlbumCenterX,
            portraitAlbumAspectRatio,
            portraitAlbumTrailing,
            portraitControlsTop,
            portraitControlsCenterX,
            portraitVolumeTop,
            portraitVolumeLeading,
            portraitVolumeTrailing,
            portraitLabelsTop,
            portraitLabelsLeading,
            portraitLabelsTrailing,
            portraitInfoCenterY,
            portraitInfoLeading,
        ]
    }

    /// Duo inner display, wide: art and controls in the halves either side of the fold (the view's
    /// center line). Asymmetric on purpose: the art takes as much of its half as possible.
    private func setupFoldWideConstraints(rightPanel: UIView) {
        let artFoldGap: CGFloat = 10       // art may sit close to the fold
        let controlsFoldGap: CGFloat = 28  // controls stay clear of it so they're easy to press
        let leftHalf = UILayoutGuide()
        let rightHalf = UILayoutGuide()
        let content = UILayoutGuide()  // vertical band between the top safe area and the toolbar
        [leftHalf, rightHalf, content].forEach(view.addLayoutGuide)

        let leftEdge = leftHalf.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let rightEdge = rightHalf.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        foldWideEdgeConstraints = [leftEdge, rightEdge]

        airPlayToolbarCenterX = toolsView.constraints.first {
            $0.firstItem === airPlayView && $0.firstAttribute == .centerX
        }

        // Square art fills the left half where height allows.
        let artFillsWidth = albumImageView.widthAnchor.constraint(equalTo: leftHalf.widthAnchor)
        artFillsWidth.priority = .defaultHigh

        foldWideConstraints = foldWideEdgeConstraints + [
            leftHalf.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -artFoldGap),
            rightHalf.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: controlsFoldGap),

            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: toolsView.topAnchor, constant: -8),

            albumImageView.centerXAnchor.constraint(equalTo: leftHalf.centerXAnchor),
            albumImageView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            albumImageView.widthAnchor.constraint(equalTo: albumImageView.heightAnchor),
            albumImageView.widthAnchor.constraint(lessThanOrEqualTo: leftHalf.widthAnchor),
            albumImageView.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor),
            albumImageView.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            artFillsWidth,

            rightPanel.leadingAnchor.constraint(equalTo: rightHalf.leadingAnchor),
            rightPanel.trailingAnchor.constraint(equalTo: rightHalf.trailingAnchor),
            rightPanel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            rightPanel.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor),
            rightPanel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),

            // Toolbar: AirPlay centered under the right half, info at the left half's edge.
            airPlayView.centerXAnchor.constraint(equalTo: rightHalf.centerXAnchor),
            infoButton.leadingAnchor.constraint(equalTo: leftHalf.leadingAnchor),
            infoButton.centerYAnchor.constraint(equalTo: toolsView.centerYAnchor),
        ]
    }

    /// Each foldWide outer edge clears only its own side's inset (e.g. a side system strip).
    private func updateFoldWideMargins() {
        guard foldWideEdgeConstraints.count == 2 else { return }
        let insets = view.safeAreaInsets
        foldWideEdgeConstraints[0].constant = insets.left + 10
        foldWideEdgeConstraints[1].constant = -(insets.right + 16)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateFoldWideMargins()
    }

    /// iPhone Duo inner display: a phone whose long side is far beyond any slab iPhone.
    /// (UIHinge reports open/closed but not the fold's position, so the screen size identifies it.)
    private func isFoldInnerDisplay(_ size: CGSize) -> Bool {
        traitCollection.userInterfaceIdiom == .phone && max(size.width, size.height) >= 850
    }

    private func layout(for size: CGSize) -> NowPlayingLayout {
        guard size.width > size.height else { return .portrait }
        return isFoldInnerDisplay(size) ? .foldWide : .landscape
    }

    /// Scales label fonts up to suit the space each layout gives them.
    private func applyLabelScale(for layout: NowPlayingLayout, size: CGSize) {
        let scale: CGFloat
        switch layout {
        case .foldWide:
            // Text column is half the screen; ~330pt is the width the base fonts were tuned for.
            let column = size.width / 2 - 60
            scale = min(max(column / 330, 1.0), 1.5)
        case .portrait, .landscape:
            scale = 1.0
        }
        for (label, font) in baseLabelFonts {
            label.font = font.withSize(font.pointSize * scale)
        }
    }

    func optimizeForDeviceSize(size: CGSize) {
        let newLayout = layout(for: size)
        guard newLayout != currentLayout else { return }
        currentLayout = newLayout

        NSLayoutConstraint.deactivate(landscapeConstraints + foldWideConstraints + panelContentConstraints)
        NSLayoutConstraint.deactivate(allPortraitConstraints)
        airPlayToolbarCenterX?.isActive = true

        switch newLayout {
        case .landscape, .foldWide:
            // Reparent controls into right panel
            if let panel = landscapeRightPanel, panel.superview == nil {
                view.addSubview(panel)
                panel.addSubview(labelsStackView)
                panel.addSubview(volumeStackView)
                panel.addSubview(controlsStackView)
            }
            albumHeightConstraint.isActive = false
            NSLayoutConstraint.activate(panelContentConstraints)
            if newLayout == .foldWide {
                airPlayToolbarCenterX?.isActive = false
                updateFoldWideMargins()
                NSLayoutConstraint.activate(foldWideConstraints)
            } else {
                NSLayoutConstraint.activate(landscapeConstraints)
            }
            if Config.debugLog { print("[NowPlaying] Switched to \(newLayout) layout") }
        case .portrait:
            // Reparent controls back to main view for portrait
            if let panel = landscapeRightPanel, panel.superview != nil {
                labelsStackView.removeFromSuperview()
                volumeStackView.removeFromSuperview()
                controlsStackView.removeFromSuperview()
                view.addSubview(labelsStackView)
                view.addSubview(volumeStackView)
                view.addSubview(controlsStackView)
                panel.removeFromSuperview()
            }
            albumHeightConstraint.isActive = true
            NSLayoutConstraint.activate(allPortraitConstraints)
            let heightFraction: CGFloat = (traitCollection.userInterfaceIdiom == .pad) ? 0.55 : 0.40
            let imageHeight = size.height * heightFraction
            albumHeightConstraint.constant = imageHeight
            if Config.debugLog { print("[NowPlaying] Switched to portrait layout, albumHeight=\(imageHeight)") }
        }
        applyLabelScale(for: newLayout, size: size)
        // foldWide has vertical room to spare: let long track names wrap to a second line
        // (fixed column width, tail-truncated after two lines) instead of truncating at one.
        songLabel.numberOfLines = newLayout == .foldWide ? 2 : 1
        // Reparenting stack views puts them above timeBubble in Z-order;
        // restore timeBubble (and the mode button beside it) to front so taps aren't blocked.
        if let bubble = timeBubble { view.bringSubviewToFront(bubble) }
        if let modeButton = modeButton { view.bringSubviewToFront(modeButton) }

        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    func updateLabels(with statusMessage: String? = nil, animate: Bool = true) {
        guard let statusMessage = statusMessage else {
            // Radio is (hopefully) streaming properly - use unified metadata
            if let metadata = metadataManager.getCurrentMetadata() {
                self.liveDJIndicator.isHidden = !metadata.isLiveDJ
                if !metadata.trackName.isEmpty {
                    songLabel.text = metadata.trackName
                    artistLabel.text = metadata.artistName
                    releaseLabel.text = metadata.albumName ?? ""
                }
            }
            
            shouldAnimateSongLabel(animate)
            return
        }
        
        // Debounce: Only update if the message is different
        if statusMessage == lastStatusMessage {
            // Optionally, print debug info here
            return
        }
        lastStatusMessage = statusMessage
        
        // Update UI only when it's not already updated
        guard songLabel.text != "" else { return }
            
        songLabel.text = statusMessage
        artistLabel.text = manager.currentStation?.name
            
        if animate {
            songLabel.animation = "flash"
            songLabel.repeatCount = 2
            songLabel.animate()
        }
    }
    
    // Animations
    
    func shouldAnimateSongLabel(_ animate: Bool) {
        // Animate if the Track has metadata
        guard animate, metadataManager.getCurrentMetadata() != nil else { return }
        
        // songLabel animation
        songLabel.animation = "zoomIn"
        songLabel.duration = 1.5
        songLabel.damping = 1
        songLabel.animate()
    }
    
    func createNowPlayingAnimation() {
        // Setup ImageView
        nowPlayingImageView = UIImageView(image: UIImage(named: "NowPlayingBars-3"))
        nowPlayingImageView.autoresizingMask = []
        nowPlayingImageView.contentMode = UIView.ContentMode.center
        
        // Create Animation
        nowPlayingImageView.animationImages = AnimationFrames.createFrames()
        nowPlayingImageView.animationDuration = 0.7
        
        // Create Top BarButton
        let barButton = UIButton(type: .custom)
        barButton.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        barButton.addSubview(nowPlayingImageView)
        nowPlayingImageView.center = barButton.center
        
        let barItem = UIBarButtonItem(customView: barButton)
        self.navigationItem.rightBarButtonItems = [barItem]
    }
    
    func startNowPlayingAnimation(_ animate: Bool) {
        animate ? nowPlayingImageView.startAnimating() : nowPlayingImageView.stopAnimating()
    }
    
    @IBAction func infoButtonPressed(_ sender: UIButton) {
        delegate?.didTapInfoButton(self, station: manager.currentStation)
    }
    
    @IBAction func shareButtonPressed(_ sender: UIButton) {
        guard let station = manager.currentStation else { return }
        let artworkURL = metadataManager.getCurrentMetadata()?.artworkURL
        delegate?.didTapShareButton(self, station: station, artworkURL: artworkURL)
    }

    // MARK: - Audio Mode

    @objc private func timeBubbleTapped() {
        let sheet = UIAlertController(title: "Select audio compensation mode",
                                      message: "• Auto-select: pitch lock for hearing aids, continuous audio lock for other\n• Pitch lock: no pitch shifts, possible drop-outs\n• Continuous audio lock: no drop-outs, possible pitch shifts",
                                      preferredStyle: .alert)

        let pref = AudioStabilityPreference.current
        func marked(_ title: String, _ match: AudioStabilityPreference) -> String {
            pref == match ? "✓  \(title)" : "    \(title)"
        }

        // Choosing saves to AudioStabilityPreference, whose didChange refreshes the mode button.
        sheet.addAction(UIAlertAction(title: marked("Auto-select", .ask), style: .default) { _ in
            RadioPlayer.shared.choosePreference(.ask)
        })
        sheet.addAction(UIAlertAction(title: marked("Pitch lock", .alwaysStability), style: .default) { _ in
            RadioPlayer.shared.choosePreference(.alwaysStability)
        })
        sheet.addAction(UIAlertAction(title: marked("Continuous audio lock", .neverStability), style: .default) { _ in
            RadioPlayer.shared.choosePreference(.neverStability)
        })
        // Close without changing anything.
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            let source: UIView = modeButton.isHidden ? timeBubble : modeButton
            popover.sourceView = source
            popover.sourceRect = source.bounds
        }

        present(sheet, animated: true)
    }

    @objc private func handleStabilityModeChange(notification: Notification) {
        DispatchQueue.main.async {
            self.updateTimeBubbleText()
        }
    }

    @objc private func handleHearingAidStateOrPreferenceChange() {
        DispatchQueue.main.async {
            self.updateTimeBubbleText()
            self.showStabilityBannerIfNeeded()
        }
    }

    /// First-run banner: hearing aids connected and the user has never chosen a mode.
    /// Only the on-screen NowPlaying instance shows it.
    private func showStabilityBannerIfNeeded() {
        guard let window = view.window,
              RadioPlayer.shared.isUsingHearingAids(),
              !AudioStabilityPreference.hasChoice else { return }
        StabilityModeBanner().show(in: window)
    }

}


extension NowPlayingViewController: StationsManagerObserver {
    func stationsManager(_ manager: StationsManager, stationDidChange station: RadioStation?) {
        stationDidChange()
    }
}

// MARK: - TEMP (task-19) fold diagnostics — remove once Duo layouts are tuned

private var lastFoldDiagnostic = ""

extension NowPlayingViewController {
    func setupFoldDiagnostics() {
        guard Config.debugLog else { return }
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                if let hinge = update.hinge {
                    let degrees = Int((hinge.angle * 180 / .pi).rounded())
                    print("[Fold] hinge status=\(hinge.status.rawValue) (0=unknown 1=closed 2=partial 3=full) angle=\(degrees)°")
                } else {
                    print("[Fold] hinge unavailable")
                }
                self.logFoldGeometry()
            }
            view.addInteraction(interaction)
        } else {
            print("[Fold] UIHingeInteraction needs iOS 27.1")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        logFoldGeometry()
    }

    func logFoldGeometry() {
        guard Config.debugLog else { return }
        let b = view.bounds.size, i = view.safeAreaInsets
        let screen = view.window?.windowScene?.screen.bounds.size ?? .zero
        let line = "[Fold] view=\(Int(b.width))x\(Int(b.height)) screen=\(Int(screen.width))x\(Int(screen.height)) safeInsets top=\(Int(i.top)) left=\(Int(i.left)) bottom=\(Int(i.bottom)) right=\(Int(i.right))"
        guard line != lastFoldDiagnostic else { return }
        lastFoldDiagnostic = line
        print(line)
    }
}
