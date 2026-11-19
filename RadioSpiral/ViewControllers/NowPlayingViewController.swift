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
    /// Every landscape constraint (all variants below), for deactivating them in one call.
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private var landscapeCommonConstraints: [NSLayoutConstraint] = []
    private var landscapeCenteredBoxConstraints: [NSLayoutConstraint] = []
    private var landscapePinnedBoxConstraints: [NSLayoutConstraint] = []
    private var landscapeArtWidthConstraints: [(fraction: CGFloat, constraint: NSLayoutConstraint)] = []
    private var allPortraitConstraints: [NSLayoutConstraint] = []
    private var landscapeRightPanel: UIView?

    private var currentLayout: NowPlayingLayout?
    /// What the layout was last applied for. A change in any part, including the metrics alone
    /// (a trait change at the same size), applies it again.
    private var appliedKey: LayoutApplyKey?
    /// Size the current layout was applied for. Font scale and art height depend on size, so
    /// e.g. Duo fully-open upright -> closed upright (both .portrait) must still re-apply.
    private var currentLayoutSize: CGSize?
    /// True while UIHinge reports the device partly open (iOS 27.1+, foldable devices only).
    private var hingePartiallyOpen = false
    private var foldLaptopConstraints: [NSLayoutConstraint] = []
    /// Landscape art-leading and panel-trailing edges; constants track the safe-area insets.
    private var landscapeEdgeConstraints: [NSLayoutConstraint] = []
    /// Portrait art never exceeds its preferred height (albumHeightConstraint is only a preference).
    private var albumMaxHeight: NSLayoutConstraint?

    // Constraints placing labels/volume/controls inside landscapeRightPanel (landscape and foldWide).
    private var panelContentConstraints: [NSLayoutConstraint] = []
    private var foldWideConstraints: [NSLayoutConstraint] = []
    /// Outer-edge constraints for foldWide, pinned to the safe-area guide with fixed gaps.
    private var foldWideEdgeConstraints: [NSLayoutConstraint] = []
    /// Storyboard constraint centering AirPlay in the full-width toolbar (swapped out in foldWide).
    private var airPlayToolbarCenterX: NSLayoutConstraint?
    /// The play, previous, next, info, AirPlay and share sizes and the toolbar height, as the
    /// storyboard has them. First used in `viewDidLoad` before any scale is applied, so the
    /// captured bases are the unscaled values and `applyMetrics` never compounds.
    private lazy var scaledConstraints: ScaledConstraints = {
        var constraints: [NSLayoutConstraint] = []
        func sizes(of view: UIView?) -> [NSLayoutConstraint] {
            (view?.constraints ?? []).filter { $0.firstAttribute == .width || $0.firstAttribute == .height }
        }
        for view in [playingButton, previousButton, nextButton, infoButton, airPlayView] as [UIView?] {
            constraints += sizes(of: view)
        }
        constraints += sizes(of: toolsView.subviews.first { $0.accessibilityIdentifier == "shareButton" })
        constraints += toolsView.constraints.filter { $0.firstAttribute == .height }
        return ScaledConstraints(constraints)
    }()
    /// The song, artist and release labels with the fonts they have when first used (the display
    /// fonts, set in `viewDidLoad` first), so per-layout scaling never compounds.
    private lazy var scaledFonts = ScaledFonts([songLabel, artistLabel, releaseLabel])
    /// What the last phone-landscape fit was computed for; nil forces a new fit.
    private var lastFitKey: String?

    // MARK: - Properties
    
    private let player = RadioPlayer.shared
    private let manager = StationsManager.shared
    
    var isNewStation = true
    var nowPlayingImageView: UIImageView!
    
    var mpVolumeSlider: UISlider?
    private var metadataSubscription: MetadataSubscription?
    private var lastStatusMessage: String?
    /// With one station there's nowhere for next and previous to go.
    static func showsStationButtons(stationCount: Int) -> Bool { stationCount > 1 }

    private func updateStationButtons() {
        let hidden = !Self.showsStationButtons(stationCount: manager.stations.count)
        previousButton.isHidden = hidden
        nextButton.isHidden = hidden
    }

    private var cancellables = Set<AnyCancellable>()
    private var connectionBanner: UILabel!
    private var timeBubble: UILabel!
    private var timeUpdateTimer: Timer?
    private var metadataReceivedAt: Date?
    private var metadataElapsed: TimeInterval = 0
    private var metadataDuration: TimeInterval = 0
    private var broadcastStart: Date?

    // MARK: - ViewDidLoad
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupHingeTracking()

        navigationItem.largeTitleDisplayMode = .never
        if manager.stations.count < 2 {
            navigationItem.hidesBackButton = true
        }
        manager.addObserver(self)

        // Display font for the song title, artist line and release (album) line (the banner and
        // time bubble stay in the system font). Set before the base fonts are captured below.
        songLabel.font = AppFont.display(.title1)
        artistLabel.font = AppFont.display(.title3)
        releaseLabel.font = AppFont.display(.subheadline)   // 15 pt, the size it had
        djName.font = AppFont.display(.caption1)   // 12 pt

        // Capture the unscaled constraint sizes and label fonts now, before the first
        // `applyMetrics` (inside `optimizeForDeviceSize` below) scales anything.
        _ = scaledConstraints
        _ = scaledFonts

        setupLandscapeConstraints()
        // appliedKey starts nil, so the first pass always applies a layout.
        optimizeForDeviceSize(size: view.bounds.size)
        // A size class can change with the size staying the same (an iPad window crossing a
        // class boundary at a size the layout already saw): apply the layout again, keyed on
        // the metrics as well as the size.
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) {
            (self: Self, _) in
            self.optimizeForDeviceSize(size: self.view.bounds.size)
        }
        // The artwork is downsampled for the display's scale: moving the window to a display
        // with a different scale (an external screen) loads it again at the right one.
        registerForTraitChanges([UITraitDisplayScale.self]) { (self: Self, _) in
            self.updateTrackArtwork()
        }

        // Create Now Playing BarItem
        createNowPlayingAnimation()
        
        // Set View Title
        // The title view carries the display font; `title` stays for the back button's label.
        self.title = manager.currentStation?.name
        navigationItem.titleView = AppFont.titleLabel(title)

        // Accessibility identifiers for UI testing
        playingButton.accessibilityIdentifier = "playPauseButton"
        infoButton.accessibilityIdentifier = "infoButton"
        albumImageView.accessibilityIdentifier = "albumArt"

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
        
        updateStationButtons()
        
        // Subscribe to unified metadata changes
        metadataSubscription = metadataManager.subscribeToMetadataChanges { [weak self] metadata in
            self?.handleMetadataUpdate(metadata)
        }

        // The banner follows the audio first: if only the metadata socket drops, the music is still
        // playing, so there's nothing to report. An offline channel, or one whose information can't
        // be loaded, says so (task-44); ChannelStatusMessages decides which message wins.
        Publishers.CombineLatest(player.$isStalled.removeDuplicates(),
                                 metadataManager.$connectionState.removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isStalled, connection in
                if let message = ChannelStatusMessages.phoneBanner(connection: connection, isStalled: isStalled) {
                    self?.showConnectionBanner(message)
                } else {
                    self?.hideConnectionBanner()
                }
                self?.updateTimeBubbleText()
            }
            .store(in: &cancellables)

        // Observe playback state changes (dropFirst skips the initial
        // .stopped emission — viewDidLoad already sets initial UI state)
        RadioPlayer.shared.$playbackState
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playbackState in
                guard let self = self else { return }
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

        isPlayingDidChange(player.isPlaying)
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
            #if DEBUG
            // UI layout tests: `-nowPlayingDemoTitle "<title>"` replaces the labels with known
            // text, so layouts can be checked with a very long title whatever is playing.
            if let title = UserDefaults.standard.string(forKey: "nowPlayingDemoTitle") {
                self.songLabel.text = title
                self.artistLabel.text = "Demo Artist"
                self.releaseLabel.text = "Demo Album (2006-2023)"
                self.djName.text = "Demo DJ"
            }
            #endif

            // Update live DJ indicator
            self.liveDJIndicator.isHidden = DemoLiveShow.indicatorHidden(isLiveDJ: metadata.isLiveDJ)

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
                                                         .scaleFactor(max(self.traitCollection.displayScale, 1)),
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

        updateTimeBubbleText()

        startTimeUpdates()
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
        guard metadataReceivedAt != nil,
              !ChannelStatusMessages.showsNoTime(connection: metadataManager.connectionState) else {
            timeBubble.text = leftPadding + "--:--" + rightPadding
            return
        }
        if let broadcastStart = broadcastStart {
            // Live DJ: show time into the show
            let showElapsed = Date().timeIntervalSince(broadcastStart)
            timeBubble.text = leftPadding + "LIVE  \(formatTime(showElapsed))" + rightPadding
        } else if metadataDuration > 0 {
            // Pre-recorded track: show track elapsed / duration
            let currentElapsed = elapsedShown(base: metadataElapsed,
                                              since: Date().timeIntervalSince(metadataReceivedAt!),
                                              duration: metadataDuration)
            timeBubble.text = leftPadding + "\(formatTime(currentElapsed)) / \(formatTime(metadataDuration))" + rightPadding
        } else {
            // No broadcast start, no duration — fallback
            let currentElapsed = metadataElapsed + Date().timeIntervalSince(metadataReceivedAt!)
            timeBubble.text = leftPadding + "\(formatTime(currentElapsed))" + rightPadding
        }
    }

    /// The elapsed time to show: counted on from when the metadata arrived, but never past the track's
    /// length, which the bubble showed as 5:05 / 4:50 when the next update was late. No duration, no cap.
    func elapsedShown(base: TimeInterval, since: TimeInterval, duration: TimeInterval) -> TimeInterval {
        let elapsed = base + since
        return duration > 0 ? min(elapsed, duration) : elapsed
    }

    /// Server times arrive unchecked, and converting one that doesn't fit in an Int would crash.
    /// Anything finite up to just under 100 hours is shown; anything else gets the placeholder.
    func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, abs(seconds) <= 359_999 else { return "--:--" }
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
        if let subscription = metadataSubscription {
            metadataManager.unsubscribeFromMetadataChanges(subscription)
        }
        metadataSubscription = metadataManager.subscribeToMetadataChanges { [weak self] metadata in
            self?.handleMetadataUpdate(metadata)
        }
    }
    
    // MARK: - Player Controls (Play/Pause/Volume)
        
    @IBAction func playingPressed(_ sender: Any) {
        if player.isPlaying {
            player.stop()
        } else {
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
                                                     .scaleFactor(max(self.traitCollection.displayScale, 1)),
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
            message = "Channel Paused..."
        case .playing:
            message = nil
        case .stopped:
            message = "Channel Stopped..."
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
                message = "Channel loading..."
            }
        case .idle:
            message = "Channel URL not valid"
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

        // Container for right-side controls: the layouts that use it (landscape, centered, foldWide)
        // each constrain its vertical position below
        let rightPanel = UIView()
        rightPanel.translatesAutoresizingMaskIntoConstraints = false
        landscapeRightPanel = rightPanel

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

        // The edges sit on the safe-area guide, so each side clears only its own inset (a
        // one-sided inset, like the Duo outer screen's side strip, gives asymmetric margins).
        // `applyMetrics` sets the constants from `landscapeSideMarginBase`.
        landscapeEdgeConstraints = [
            albumImageView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            rightPanel.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
        ]

        // Both art-box variants and both art widths are built once; `activateLandscapeConstraints`
        // turns on the set the metrics pick, so a window that changes size class swaps sets and
        // no layout guide or constraint is ever created again.
        //
        // Centered (a tall window): the art box is a square centered in the space above the
        // toolbar, so the time bubble (anchored to the box's bottom) sits right under the drawn
        // art, not down at the toolbar, and the right panel is centered on it.
        let artArea = UILayoutGuide()
        view.addLayoutGuide(artArea)
        landscapeCenteredBoxConstraints = [
            artArea.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            artArea.bottomAnchor.constraint(equalTo: toolsView.topAnchor, constant: -8),
            albumImageView.heightAnchor.constraint(equalTo: albumImageView.widthAnchor),
            albumImageView.centerYAnchor.constraint(equalTo: artArea.centerYAnchor),
            albumImageView.topAnchor.constraint(greaterThanOrEqualTo: artArea.topAnchor),
            albumImageView.bottomAnchor.constraint(lessThanOrEqualTo: artArea.bottomAnchor),
            rightPanel.centerYAnchor.constraint(equalTo: albumImageView.centerYAnchor),
        ]
        // Pinned (a short window, every phone): the box fills the height (the art is aspect-fit
        // inside it) and the right panel is pinned to the top.
        landscapePinnedBoxConstraints = [
            albumImageView.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            albumImageView.bottomAnchor.constraint(equalTo: toolsView.topAnchor, constant: -8),
            rightPanel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
        ]
        // The art's width follows the window's width, not its height. The multipliers match
        // `NowPlayingMetrics.landscapeArtWidthFraction`.
        landscapeArtWidthConstraints = [0.35, 0.40].map {
            (fraction: $0, constraint: albumImageView.widthAnchor.constraint(equalTo: view.widthAnchor,
                                                                           multiplier: $0))
        }

        landscapeCommonConstraints = landscapeEdgeConstraints + [
            // Right panel: positioned between art and trailing edge
            rightPanel.leadingAnchor.constraint(equalTo: albumImageView.trailingAnchor, constant: 24),
            rightPanel.bottomAnchor.constraint(lessThanOrEqualTo: toolsView.topAnchor, constant: -4),

            // Info button: left side of toolbar area in landscape
            infoButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 20),
            infoButton.centerYAnchor.constraint(equalTo: toolsView.centerYAnchor),
        ]
        // Everything landscape can activate, so one deactivate call clears every variant.
        landscapeConstraints = landscapeCommonConstraints + landscapeCenteredBoxConstraints
            + landscapePinnedBoxConstraints + landscapeArtWidthConstraints.map(\.constraint)

        setupFoldWideConstraints(rightPanel: rightPanel)
        setupFoldLaptopConstraints()

        // Portrait must never run into the toolbar (labels sitting over it swallow taps on
        // Info/Share). The art's height becomes a preference so it gives way first: e.g. the
        // Duo's short outer screen during a live show, when the DJ line adds a fourth row.
        albumHeightConstraint.isActive = false
        albumHeightConstraint.priority = .defaultHigh
        let maxHeight = albumImageView.heightAnchor.constraint(lessThanOrEqualToConstant: 0)
        albumMaxHeight = maxHeight
        let labelsAboveToolbar = labelsStackView.bottomAnchor.constraint(
            lessThanOrEqualTo: toolsView.topAnchor, constant: -4)
        // Text keeps its full height; the art is what shrinks.
        for case let label as UILabel in labelsStackView.arrangedSubviews
            + labelsStackView.arrangedSubviews.flatMap(\.subviews) {
            label.setContentCompressionResistancePriority(.required - 1, for: .vertical)
        }

        allPortraitConstraints = [
            labelsAboveToolbar,
            maxHeight,
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

        // Each edge clears only its own side's safe-area inset, plus a fixed gap.
        let safeArea = view.safeAreaLayoutGuide
        let leftEdge = leftHalf.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 10)
        let rightEdge = rightHalf.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -16)
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

    /// Duo inner display, tall and partly open: the fold is the view's horizontal center line.
    /// Top half holds what you look at (art, labels); bottom half, lying on the table, holds
    /// what you press (volume, play/pause, toolbar).
    private func setupFoldLaptopConstraints() {
        let safeArea = view.safeAreaLayoutGuide
        let bubbleSpace: CGFloat = 34  // time bubble hangs below the art; keep it above the fold
        let upper = UILayoutGuide()
        let lower = UILayoutGuide()
        [upper, lower].forEach(view.addLayoutGuide)

        let artFillsHeight = albumImageView.heightAnchor.constraint(equalTo: upper.heightAnchor,
                                                                    constant: -bubbleSpace)
        artFillsHeight.priority = .defaultHigh

        foldLaptopConstraints = [
            upper.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            upper.bottomAnchor.constraint(equalTo: view.centerYAnchor, constant: -12),
            lower.topAnchor.constraint(equalTo: view.centerYAnchor, constant: 28),
            lower.bottomAnchor.constraint(equalTo: toolsView.topAnchor, constant: -8),

            // Upper half: square art on the left, labels beside it
            albumImageView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16),
            albumImageView.topAnchor.constraint(greaterThanOrEqualTo: upper.topAnchor),
            albumImageView.bottomAnchor.constraint(lessThanOrEqualTo: upper.bottomAnchor, constant: -bubbleSpace),
            albumImageView.centerYAnchor.constraint(equalTo: upper.centerYAnchor, constant: -bubbleSpace / 2),
            albumImageView.widthAnchor.constraint(equalTo: albumImageView.heightAnchor),
            albumImageView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.5),
            artFillsHeight,

            labelsStackView.leadingAnchor.constraint(equalTo: albumImageView.trailingAnchor, constant: 20),
            labelsStackView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -16),
            labelsStackView.centerYAnchor.constraint(equalTo: albumImageView.centerYAnchor),

            // Lower half: volume and controls, centered in the flat half above the toolbar
            volumeStackView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 32),
            volumeStackView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -32),
            controlsStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controlsStackView.topAnchor.constraint(equalTo: volumeStackView.bottomAnchor, constant: 20),
            { let c = volumeStackView.topAnchor.constraint(equalTo: lower.topAnchor, constant: 24)
              c.priority = .defaultHigh
              return c }(),
            volumeStackView.topAnchor.constraint(greaterThanOrEqualTo: lower.topAnchor),
            controlsStackView.bottomAnchor.constraint(lessThanOrEqualTo: lower.bottomAnchor),

            infoButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 20),
            infoButton.centerYAnchor.constraint(equalTo: toolsView.centerYAnchor),
        ]
    }

    /// Tracks partly-open vs open/closed so the laptop layout can switch in and out.
    private func setupHingeTracking() {
        guard #available(iOS 27.1, *) else { return }
        let interaction = UIHingeInteraction { [weak self] _, update in
            guard let self else { return }
            let partial = update.hinge?.status == .partiallyOpen
            guard partial != self.hingePartiallyOpen else { return }
            self.hingePartiallyOpen = partial
            self.optimizeForDeviceSize(size: self.view.bounds.size)
        }
        view.addInteraction(interaction)
    }

    /// iPhone Duo inner display: a phone-idiom screen at least 850 pt long and under 1.7:1.
    /// (UIHinge reports open/closed but not the fold's position, so the screen size identifies it.)
    /// A long side alone isn't enough: the iPhone 17 (874 pt), Air (912) and 17 Pro Max (956)
    /// are as long as the Duo's inner display (669 x 951 pt), but they are about 2.2:1 and the
    /// Duo's inner display is about 1.4:1. The Duo's outer display (466 x 678 pt) is too short.
    static func isFoldInnerDisplay(_ size: CGSize, isPhone: Bool) -> Bool {
        let long = max(size.width, size.height)
        let short = min(size.width, size.height)
        return isPhone && long >= 850 && short > 0 && long / short < 1.7
    }

    private func isFoldInnerDisplay(_ size: CGSize) -> Bool {
        Self.isFoldInnerDisplay(size, isPhone: traitCollection.userInterfaceIdiom == .phone)
    }

    /// The layout numbers for a view of this size, chosen from the size classes (not the idiom);
    /// the Duo's inner display keeps the phone values.
    private func currentMetrics(for size: CGSize) -> NowPlayingMetrics {
        NowPlayingMetrics(horizontal: traitCollection.horizontalSizeClass,
                          vertical: traitCollection.verticalSizeClass,
                          isFoldInner: isFoldInnerDisplay(size))
    }

    private func layout(for size: CGSize) -> NowPlayingLayout {
        let fold = isFoldInnerDisplay(size)
        if size.width > size.height { return fold ? .foldWide : .landscape }
        return fold && hingePartiallyOpen ? .foldLaptop : .portrait
    }

    /// Scales label fonts up to suit the space each layout gives them.
    private func applyLabelScale(for layout: NowPlayingLayout, size: CGSize, uiScale: CGFloat) {
        let scale: CGFloat
        switch layout {
        case .foldWide:
            // Text column is half the screen; ~330pt is the width the base fonts were tuned for.
            let column = size.width / 2 - 60
            scale = min(max(column / 330, 1.0), 1.5)
        case .foldLaptop:
            scale = 1.2
        case .portrait:
            // Duo inner display fully open and upright: same layout, much more room for text.
            scale = isFoldInnerDisplay(size) ? 1.35 : 1.0
        case .landscape:
            scale = 1.0   // phones: fitLabelsToPanel() shrinks per title, only when needed
        }
        scaledFonts.apply(scale: scale * uiScale)
    }

    /// Applies the metrics' scale to the controls and labels. Idempotent: every call sets
    /// base * scale, so repeating it, or going back to scale 1.0, never compounds.
    private func applyMetrics(_ metrics: NowPlayingMetrics) {
        scaledConstraints.apply(scale: metrics.uiScale)
        if landscapeEdgeConstraints.count == 2 {
            landscapeEdgeConstraints[0].constant = metrics.landscapeSideMarginBase
            landscapeEdgeConstraints[1].constant = -metrics.landscapeSideMarginBase
        }
        applyLabelScale(for: currentLayout ?? .portrait, size: currentLayoutSize ?? view.bounds.size,
                        uiScale: metrics.uiScale)
        lastFitKey = nil   // fonts were reset: fit again at the next layout
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fitLabelsToPanel()
    }

    /// Phone landscape only. Shrinks the labels just enough that the title fits in two lines
    /// without an ellipsis and the labels fit above the volume slider, never below 11 pt (the
    /// iOS minimum in the Human Interface Guidelines). Runs from layout, but only when the text,
    /// the column width or the toolbar position changed since the last fit.
    private func fitLabelsToPanel() {
        guard currentLayout == .landscape, currentMetrics(for: view.bounds.size).fitsLabelsToPanel,
              landscapeRightPanel?.superview != nil else { return }
        let width = labelsStackView.bounds.width
        guard width > 0 else { return }
        let key = [songLabel.text, artistLabel.text, releaseLabel.text].map { $0 ?? "" }
            .joined(separator: "|") + "|\(width)|\(toolsView.frame.minY)"
        guard key != lastFitKey else { return }
        lastFitKey = key

        // Space for the labels: from the top of the panel down to the toolbar, less the
        // volume slider and the controls and their minimum gaps (see panelContentConstraints).
        let room = toolsView.frame.minY - 4 - (view.safeAreaInsets.top + 8)
            - volumeStackView.bounds.height - controlsStackView.bounds.height - 6

        let labels: [UILabel] = [songLabel, artistLabel, releaseLabel]
        let baseFonts = scaledFonts.baseFonts
        func apply(title: CGFloat, others: CGFloat) {
            for (index, label) in labels.enumerated() {
                let scale = index == 0 ? title : others
                label.font = baseFonts[index].withSize(max(11, baseFonts[index].pointSize * scale))
            }
        }
        func needed() -> CGFloat {
            labelsStackView.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel).height
        }

        // The title first, to its two lines; then, if the column is still too tall, everything
        // together by one factor so the sizes keep their order (no label goes under 11 pt).
        let title = TitleFit.scale(for: songLabel.text ?? "", font: baseFonts[0],
                                   width: width, maxLines: 2)
        var factor: CGFloat = 1
        apply(title: title, others: 1)
        while needed() > room, factor > 0.4 {
            factor -= 0.05
            apply(title: title * factor, others: factor)
        }
    }

    /// Turns on the landscape constraints the metrics select: the centered or the pinned art
    /// box, and the art width for this window's width. The caller has deactivated all of them.
    private func activateLandscapeConstraints(for metrics: NowPlayingMetrics) {
        let widthChoice = landscapeArtWidthConstraints.first { $0.fraction == metrics.landscapeArtWidthFraction }
            ?? landscapeArtWidthConstraints.last
        NSLayoutConstraint.activate(landscapeCommonConstraints
            + (metrics.landscapeArtBoxCentered ? landscapeCenteredBoxConstraints : landscapePinnedBoxConstraints)
            + [widthChoice?.constraint].compactMap { $0 })
    }

    func optimizeForDeviceSize(size: CGSize) {
        let newLayout = layout(for: size)
        let key = LayoutApplyKey(layout: newLayout, size: size, metrics: currentMetrics(for: size))
        guard key != appliedKey else { return }
        appliedKey = key
        currentLayout = newLayout
        currentLayoutSize = size

        NSLayoutConstraint.deactivate(landscapeConstraints + foldWideConstraints + panelContentConstraints
                                      + foldLaptopConstraints)
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
                NSLayoutConstraint.activate(foldWideConstraints)
            } else {
                activateLandscapeConstraints(for: currentMetrics(for: size))
            }
            if Config.debugLog { print("[NowPlaying] Switched to \(newLayout) layout") }
        case .portrait, .foldLaptop:
            // Reparent controls back to main view
            if let panel = landscapeRightPanel, panel.superview != nil {
                labelsStackView.removeFromSuperview()
                volumeStackView.removeFromSuperview()
                controlsStackView.removeFromSuperview()
                view.addSubview(labelsStackView)
                view.addSubview(volumeStackView)
                view.addSubview(controlsStackView)
                panel.removeFromSuperview()
            }
            if newLayout == .foldLaptop {
                albumHeightConstraint.isActive = false
                NSLayoutConstraint.activate(foldLaptopConstraints)
                if Config.debugLog { print("[NowPlaying] Switched to foldLaptop layout") }
            } else {
                albumHeightConstraint.isActive = true
                NSLayoutConstraint.activate(allPortraitConstraints)
                let imageHeight = size.height * currentMetrics(for: size).portraitAlbumHeightFraction
                albumHeightConstraint.constant = imageHeight
                albumMaxHeight?.constant = imageHeight
                if Config.debugLog { print("[NowPlaying] Switched to portrait layout, albumHeight=\(imageHeight)") }
            }
        }
        applyMetrics(currentMetrics(for: size))
        // Long track names wrap to a second line (tail-truncated after two lines) instead of
        // truncating at one: the fold layouts and phone landscape have room for it.
        songLabel.numberOfLines = (newLayout == .foldWide || newLayout == .foldLaptop || newLayout == .landscape) ? 2 : 1
        // Reparenting stack views puts them above timeBubble in Z-order;
        // restore timeBubble to front so it stays visible.
        if let bubble = timeBubble { view.bringSubviewToFront(bubble) }

        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    func updateLabels(with statusMessage: String? = nil, animate: Bool = true) {
        guard let statusMessage = statusMessage else {
            // Radio is (hopefully) streaming properly - use unified metadata
            var titleChanged = false
            if let metadata = metadataManager.getCurrentMetadata() {
                self.liveDJIndicator.isHidden = DemoLiveShow.indicatorHidden(isLiveDJ: metadata.isLiveDJ)
                if !metadata.trackName.isEmpty {
                    // Only a different title animates: Play reaches here three
                    // times (task-55) and the text is the same each time.
                    titleChanged = songLabel.text != metadata.trackName
                    songLabel.text = metadata.trackName
                    artistLabel.text = metadata.artistName
                    releaseLabel.text = metadata.albumName ?? ""
                }
            }
            
            if titleChanged { shouldAnimateSongLabel(animate) }
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

}


extension NowPlayingViewController: StationsManagerObserver {
    func stationsManager(_ manager: StationsManager, stationDidChange station: RadioStation?) {
        stationDidChange()
    }

    func stationsManager(_ manager: StationsManager, stationsDidUpdate stations: [RadioStation]) {
        updateStationButtons()
    }
}
