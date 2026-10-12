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

    // MARK: - Interruption Mode

    /// Cached hearing-aid state, refreshed only at init and on route changes.
    /// Reading `currentRoute` on a hearing-aid route logs an AVAudioSession
    /// "Endpoint Value Converter ... HearingAid" warning, so the UI's 1s timer must not poll it.
    /// Starts false; the first real read happens on `sessionQueue` in init (route reads block on main).
    private var hearingAidsConnected = false  // main thread only

    func isUsingHearingAids() -> Bool {
        hearingAidsConnected
    }

    private static func routeHasHearingAids() -> Bool {
        // MFi hearing aids route audio via Bluetooth LE (.bluetoothLE port type).
        // There is no dedicated "hearingAppliance" port constant in AVAudioSession.
        AVAudioSession.sharedInstance().currentRoute.outputs
            .contains(where: { $0.portType == .bluetoothLE })
    }

    /// Serial queue for AVAudioSession reconfiguration. setCategory/setActive can block,
    /// and calling them on main while the session is active triggers UI-unresponsiveness warnings.
    private let sessionQueue = DispatchQueue(label: "RadioPlayer.audioSession", qos: .userInitiated)

    /// Forward buffer for every mode. A short (2s) buffer let the stream go audibly
    /// slow and out of tune on poor connections; 30s absorbs the jitter. Playback still
    /// starts immediately (playImmediately(atRate:)), so the larger target doesn't delay it.
    static let forwardBufferDuration: TimeInterval = 30.0

    /// Mode last applied, so a UserDefaults change only reconfigures the session when it matters.
    private var appliedMode: InterruptionMode?

    func applyInterruptionMode(_ mode: InterruptionMode) {
        appliedMode = mode
        // No category options: .playback already routes to A2DP/AirPlay, and HFP/AirPlay
        // options are only valid with .playAndRecord (passing them fails with paramErr -50).
        // .spokenAudio makes spoken interruptions pause the stream; .default lowers its volume.
        let sessionMode: AVAudioSession.Mode = mode == .pause ? .spokenAudio : .default
        playerItem?.audioTimePitchAlgorithm = .timeDomain
        playerItem?.preferredForwardBufferDuration = RadioPlayer.forwardBufferDuration
        sessionQueue.async {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: sessionMode, options: [])
            } catch {
                // Session update failed; continue with existing settings
            }
            self.activateSessionOnQueue { _ in }
        }
    }

    func activateSession() {
        sessionQueue.async {
            self.activateSessionOnQueue { error in
                if let error, Config.debugLog {
                    print("audioSession could not be activated: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Must be called on `sessionQueue`. Uses the non-blocking activate API where available;
    /// falls back to the blocking setActive on older OS versions, which is why this stays off main.
    private func activateSessionOnQueue(completion: @escaping (Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            session.activate(options: []) { success, error in
                completion(success ? nil : error)
            }
        } else {
            do {
                try session.setActive(true)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    /// Applies whatever mode the saved preference and current route call for.
    func applyPreferredMode() {
        applyInterruptionMode(currentModeForRoute())
    }

    private func currentModeForRoute() -> InterruptionMode {
        InterruptionPreference.current.mode(hearingAidsConnected: isUsingHearingAids())
    }

    /// The Settings app changed the preference (delivered when RadioSpiral becomes active).
    @objc private func handleDefaultsChange() {
        DispatchQueue.main.async {
            let mode = self.currentModeForRoute()
            if mode != self.appliedMode { self.applyInterruptionMode(mode) }
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
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            let hasHearingAids = RadioPlayer.routeHasHearingAids()
            DispatchQueue.main.async {
                // Hearing aids already connected at launch fire no route change,
                // so apply the preferred mode here once the initial route is known.
                // Set the cache first: Automatic reads it to pick the mode.
                self.hearingAidsConnected = hasHearingAids
                self.applyPreferredMode()
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDefaultsChange),
            name: UserDefaults.didChangeNotification, object: nil)
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
        playerItem?.preferredForwardBufferDuration = RadioPlayer.forwardBufferDuration

        player = AVPlayer(playerItem: playerItem!)
        player?.allowsExternalPlayback = false
        // Do NOT set automaticallyWaitsToMinimizeStalling — playImmediately(atRate:) disables it,
        // which keeps the rate locked at 1.0 and prevents pitch wobble on live streams.

        setupObservations()
        applyInterruptionMode(currentModeForRoute())
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

        // Refresh the cache first; the main-queue blocks below run after this one, in order.
        let hasHearingAids = RadioPlayer.routeHasHearingAids()
        DispatchQueue.main.async { self.hearingAidsConnected = hasHearingAids }

        switch reason {
        case .newDeviceAvailable:
            DispatchQueue.main.async {
                guard self.isUsingHearingAids() else { return }
                self.applyPreferredMode()
            }

        case .oldDeviceUnavailable:
            DispatchQueue.main.async {
                self.applyPreferredMode()
                // Pause on any device removal (preserves existing behaviour for wired headphones)
                self.pause()
            }

        default:
            break
        }
    }
}
