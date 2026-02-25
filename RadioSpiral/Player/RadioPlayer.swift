import AVFoundation
import Combine

/// Direct AVPlayer wrapper for internet radio streaming.
/// No internal reachability — network-aware restart is the caller's responsibility.
/// No metadata parsing — Azuracast WebSocket provides all metadata.
class RadioPlayer: ObservableObject {

    static let shared = RadioPlayer()

    // MARK: - Published State

    @Published private(set) var state: State = .idle
    @Published private(set) var playbackState: PlaybackState = .stopped

    var isPlaying: Bool { playbackState == .playing }

    var radioURL: URL? {
        didSet { radioURLDidChange(radioURL) }
    }

    // MARK: - State Enums

    enum State {
        case idle          // No URL set
        case loading       // Buffering
        case readyToPlay   // Buffer sufficient
        case error         // AVPlayerItem failed
    }

    enum PlaybackState {
        case playing, stopped, paused
    }

    // MARK: - Stability Mode

    static let stabilityModeDidChange = Notification.Name("RadioPlayerStabilityModeDidChange")

    func isUsingHearingAids() -> Bool {
        // MFi hearing aids route audio via Bluetooth LE (.bluetoothLE port type).
        // There is no dedicated "hearingAppliance" port constant in AVAudioSession.
        AVAudioSession.sharedInstance().currentRoute.outputs
            .contains(where: { $0.portType == .bluetoothLE })
    }

    func applyStabilitySettings(mode: AudioStabilityMode) {
        let session = AVAudioSession.sharedInstance()
        do {
            switch mode {
            case .stability:
                try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth])
                playerItem?.audioTimePitchAlgorithm = .timeDomain
                playerItem?.preferredForwardBufferDuration = 30.0
            case .fidelity:
                try session.setCategory(.playback, mode: .default,
                                        options: [.allowAirPlay, .allowBluetoothA2DP])
                playerItem?.audioTimePitchAlgorithm = .spectral
                playerItem?.preferredForwardBufferDuration = 2.0
            }
            try session.setActive(true)
        } catch {
            // Session update failed; continue with existing settings
        }
        NotificationCenter.default.post(
            name: RadioPlayer.stabilityModeDidChange,
            object: nil,
            userInfo: ["mode": mode]
        )
    }

    private func currentModeForRoute() -> AudioStabilityMode {
        switch AudioStabilityPreference.current {
        case .neverStability: return .fidelity
        case .alwaysStability: return .stability
        case .ask: return isUsingHearingAids() ? .stability : .fidelity
        }
    }

    // MARK: - Private

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    private var bufferObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    // MARK: - Init

    private init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default,
                                 options: [.allowAirPlay, .allowBluetoothA2DP])

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        tearDownObservations()
    }

    // MARK: - Playback Control

    func play() {
        guard let player = player else { return }
        if player.currentItem == nil, let item = playerItem {
            player.replaceCurrentItem(with: item)
        }
        player.playImmediately(atRate: 1.0)
        playbackState = .playing
    }

    func pause() {
        player?.pause()
        playbackState = .paused
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playbackState = .stopped
    }

    // MARK: - URL Change

    private func radioURLDidChange(_ url: URL?) {
        tearDownObservations()
        stop()
        playerItem = nil
        player = nil

        guard let url = url else {
            state = .idle
            return
        }

        state = .loading
        let asset = AVURLAsset(url: url)
        let requiredAssetKeys = [
            "playable",
            "hasProtectedContent"
        ]
        playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: requiredAssetKeys)
        playerItem?.preferredForwardBufferDuration = 2.0

        player = AVPlayer(playerItem: playerItem!)
        player?.allowsExternalPlayback = false
        // Do NOT set automaticallyWaitsToMinimizeStalling — playImmediately(atRate:) disables it,
        // which keeps the rate locked at 1.0 and prevents pitch wobble on live streams.

        setupObservations()
        applyStabilitySettings(mode: currentModeForRoute())
    }

    // MARK: - KVO

    private func setupObservations() {
        guard let item = playerItem else { return }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self?.state = .readyToPlay
                case .failed:
                    self?.state = .error
                default:
                    break
                }
            }
        }

        bufferObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.isPlaybackBufferEmpty {
                    self?.state = .loading
                }
            }
        }

        timeControlObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                if item.isPlaybackLikelyToKeepUp {
                    self?.state = .readyToPlay
                }
            }
        }
    }

    private func tearDownObservations() {
        statusObservation?.invalidate()
        statusObservation = nil
        bufferObservation?.invalidate()
        bufferObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
    }

    // MARK: - System Events

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            DispatchQueue.main.async { self.pause() }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { break }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            DispatchQueue.main.async { options.contains(.shouldResume) ? self.play() : self.pause() }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .newDeviceAvailable:
            DispatchQueue.main.async {
                guard self.isUsingHearingAids() else { return }
                let pref = AudioStabilityPreference.current
                guard pref != .neverStability else { return }
                self.applyStabilitySettings(mode: .stability)
                // Banner shown by NowPlayingVC: it observes stabilityModeDidChange and checks
                // AudioStabilityPreference.current == .ask to decide whether to show the banner
            }

        case .oldDeviceUnavailable:
            DispatchQueue.main.async {
                if !self.isUsingHearingAids() {
                    self.applyStabilitySettings(mode: .fidelity)
                }
                // Pause on any device removal (preserves existing behaviour for wired headphones)
                self.pause()
            }

        default:
            break
        }
    }
}
