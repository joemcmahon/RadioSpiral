//
//  MetadataManagerIntegrationTests.swift
//  ConfigClientTests
//
//  Pins how StationMetadataManager turns the socket client's status into the
//  metadata the app displays, and when subscribers hear about it.
//
//  These use the real shared singletons inside the running app, because the
//  manager can't be given a client of its own. So every scenario sets the status,
//  triggers the update, reads the result and restores the real status in one
//  synchronous block on the main thread (see `underFakeStatus`). The socket client
//  publishes its updates through the main queue, so none can land in the middle.
//  Don't wait or spin the run loop inside that block.
//
//  The app's real subscribers (lock screen, Now Playing) also receive these fake
//  updates, then the real values again when the status is restored.
//
//  Whether an unusable status gives nil or the station's own info depends on
//  whether the launched app has chosen a station. Reaching the station-info branch
//  on purpose opens a real socket, so these tests don't pin its contents. They pin
//  that nothing from the unusable status gets through.
//
//  These capture what the code does today. Some of it looks wrong, and those tests
//  say so: see F5 and F6 in the findings log. A fix should turn them red, and the
//  test then changes to assert the new behaviour.
//

import XCTest
@testable import RadioSpiral

final class MetadataManagerIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private final class Recorder {
        var isRecording = false
        var calls: [UnifiedMetadata?] = []

        func record(_ metadata: UnifiedMetadata?) {
            if isRecording {
                calls.append(metadata)
            }
        }
    }

    /// Subscribed once for the whole run, so most tests add no subscriber of their
    /// own to the shared manager. It ignores everything outside `applying`.
    private static let recorder: Recorder = {
        let recorder = Recorder()
        StationMetadataManager.shared.subscribeToMetadataChanges { metadata in
            recorder.record(metadata)
        }
        return recorder
    }()

    private struct Step {
        let metadata: UnifiedMetadata?
        let notifications: [UnifiedMetadata?]
    }

    private var client: ACWebSocketClient { ACWebSocketClient.shared }
    private var manager: StationMetadataManager { StationMetadataManager.shared }

    /// Runs `body`, then puts the real status back and lets the manager re-read it.
    /// The body and the restore must stay in one synchronous block on the main thread.
    private func underFakeStatus<T>(_ body: () -> T) -> T {
        dispatchPrecondition(condition: .onQueue(.main))
        let realStatus = client.status
        let result = body()
        // The socket's background thread can change the connection at any time, so
        // carry that over rather than undoing it.
        realStatus.connection = client.status.connection
        client.status = realStatus
        manager.triggerMetadataUpdate()
        return result
    }

    /// Feeds each status to the manager in turn, recording what each one did.
    private func applying(_ statuses: ACStreamStatus...) -> [Step] {
        let recorder = Self.recorder
        return underFakeStatus {
            statuses.map { status in
                status.connection = client.status.connection
                client.status = status
                recorder.calls.removeAll()
                recorder.isRecording = true
                manager.triggerMetadataUpdate()
                recorder.isRecording = false
                return Step(metadata: manager.getCurrentMetadata(), notifications: recorder.calls)
            }
        }
    }

    /// A usable song. The track is unique by default, so the first update of a
    /// scenario always differs from whatever the running app had before.
    private func makeStatus(track: String = "Track \(UUID().uuidString)",
                            artist: String = "Artist",
                            album: String = "Album",
                            duration: TimeInterval = 300,
                            elapsed: TimeInterval = 10,
                            dj: String = "DJ",
                            isLiveDJ: Bool = false,
                            artwork: URL? = nil,
                            broadcastStart: Date? = nil,
                            changed: Bool = true) -> ACStreamStatus {
        let status = ACStreamStatus(connection: .connected,
                                    isLiveDJ: isLiveDJ,
                                    track: track,
                                    artist: artist,
                                    album: album,
                                    duration: duration,
                                    elapsed: elapsed,
                                    dj: dj,
                                    artwork: artwork)
        status.broadcastStart = broadcastStart
        status.changed = changed
        return status
    }

    /// Nothing from `status` may appear, whether the manager gave nil or station info.
    private func assertNothingUsed(from status: ACStreamStatus,
                                   in metadata: UnifiedMetadata?,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) {
        if !status.track.isEmpty {
            XCTAssertNotEqual(metadata?.trackName, status.track, file: file, line: line)
        }
        if !status.artist.isEmpty {
            XCTAssertNotEqual(metadata?.artistName, status.artist, file: file, line: line)
        }
        XCTAssertNotEqual(metadata?.djName, status.dj, file: file, line: line)
        XCTAssertNil(metadata?.albumName, file: file, line: line)
        XCTAssertNil(metadata?.artworkURL, file: file, line: line)
        XCTAssertNil(metadata?.duration, file: file, line: line)
        XCTAssertNil(metadata?.elapsed, file: file, line: line)
        XCTAssertNil(metadata?.broadcastStart, file: file, line: line)
        XCTAssertEqual(metadata?.isLiveDJ ?? false, false, file: file, line: line)
    }

    private func onlyStep(_ status: ACStreamStatus,
                          file: StaticString = #filePath,
                          line: UInt = #line) throws -> Step {
        let steps = applying(status)
        return try XCTUnwrap(steps.first, file: file, line: line)
    }

    // MARK: - Choosing socket metadata

    func testUsableStatusIsCopiedFieldForField() throws {
        // A real station's info has none of these values, so this also shows that
        // station info doesn't replace a usable status.
        let artwork = try XCTUnwrap(URL(string: "https://example.test/art.png"))
        let start = Date(timeIntervalSince1970: 1_000)
        let status = makeStatus(track: "The Track \(UUID().uuidString)",
                                artist: "The Artist",
                                album: "The Album",
                                duration: 300,
                                elapsed: 10,
                                dj: "The DJ",
                                isLiveDJ: true,
                                artwork: artwork,
                                broadcastStart: start)

        let metadata = try XCTUnwrap(onlyStep(status).metadata)

        XCTAssertEqual(metadata.trackName, status.track)
        XCTAssertEqual(metadata.artistName, "The Artist")
        XCTAssertEqual(metadata.albumName, "The Album")
        XCTAssertEqual(metadata.artworkURL, artwork)
        XCTAssertEqual(metadata.duration, 300)
        XCTAssertEqual(metadata.elapsed, 10)
        XCTAssertEqual(metadata.broadcastStart, start)
        XCTAssertEqual(metadata.djName, "The DJ")
        XCTAssertEqual(metadata.isLiveDJ, true)
    }

    func testLiveDJOffIsCopied() throws {
        let metadata = try XCTUnwrap(onlyStep(makeStatus(isLiveDJ: false)).metadata)

        XCTAssertEqual(metadata.isLiveDJ, false)
    }

    func testMissingArtworkAndBroadcastStartStayNil() throws {
        let metadata = try XCTUnwrap(onlyStep(makeStatus()).metadata)

        XCTAssertNil(metadata.artworkURL)
        XCTAssertNil(metadata.broadcastStart)
    }

    // MARK: - Unusable statuses

    func testStatusWithNoTrackIsNotUsed() throws {
        let status = makeStatus(track: "",
                                artist: "Artist \(UUID().uuidString)",
                                album: "Album \(UUID().uuidString)",
                                dj: "DJ \(UUID().uuidString)",
                                isLiveDJ: true,
                                broadcastStart: Date())

        assertNothingUsed(from: status, in: try onlyStep(status).metadata)
    }

    func testStatusWithNoArtistIsNotUsed() throws {
        let status = makeStatus(artist: "",
                                album: "Album \(UUID().uuidString)",
                                dj: "DJ \(UUID().uuidString)",
                                isLiveDJ: true,
                                broadcastStart: Date())

        assertNothingUsed(from: status, in: try onlyStep(status).metadata)
    }

    func testStatusNotMarkedChangedIsNotUsed() throws {
        let status = makeStatus(artist: "Artist \(UUID().uuidString)",
                                album: "Album \(UUID().uuidString)",
                                dj: "DJ \(UUID().uuidString)",
                                isLiveDJ: true,
                                broadcastStart: Date(),
                                changed: false)

        assertNothingUsed(from: status, in: try onlyStep(status).metadata)
    }

    func testUnusableStatusDoesNotKeepTheEarlierSong() {
        let song = makeStatus(album: "Album \(UUID().uuidString)")
        let unusable = makeStatus(changed: false)

        let steps = applying(song, unusable)

        XCTAssertEqual(steps[0].metadata?.trackName, song.track)
        XCTAssertNotEqual(steps[1].metadata?.trackName, song.track)
        XCTAssertNil(steps[1].metadata?.albumName)
    }

    // MARK: - Blank values become nil

    func testEmptyAlbumBecomesNil() throws {
        XCTAssertNil(try XCTUnwrap(onlyStep(makeStatus(album: "")).metadata).albumName)
    }

    func testEmptyDJBecomesNil() throws {
        XCTAssertNil(try XCTUnwrap(onlyStep(makeStatus(dj: "")).metadata).djName)
    }

    func testZeroDurationBecomesNil() throws {
        XCTAssertNil(try XCTUnwrap(onlyStep(makeStatus(duration: 0)).metadata).duration)
    }

    func testZeroElapsedBecomesNil() throws {
        XCTAssertNil(try XCTUnwrap(onlyStep(makeStatus(elapsed: 0)).metadata).elapsed)
    }

    func testNegativeDurationAndElapsedBecomeNil() throws {
        let metadata = try XCTUnwrap(onlyStep(makeStatus(duration: -1, elapsed: -1)).metadata)

        XCTAssertNil(metadata.duration)
        XCTAssertNil(metadata.elapsed)
    }

    func testSmallPositiveDurationAndElapsedAreKept() throws {
        let metadata = try XCTUnwrap(onlyStep(makeStatus(duration: 0.5, elapsed: 0.5)).metadata)

        XCTAssertEqual(metadata.duration, 0.5)
        XCTAssertEqual(metadata.elapsed, 0.5)
    }

    func testAlbumOfOnlySpacesIsKept() throws {
        let metadata = try XCTUnwrap(onlyStep(makeStatus(album: "  ")).metadata)

        XCTAssertEqual(metadata.albumName, "  ")
    }

    // MARK: - Notifying subscribers

    func testNewSongNotifiesOnceWithTheNewMetadata() throws {
        let status = makeStatus()

        let step = try onlyStep(status)

        XCTAssertEqual(step.notifications.count, 1)
        XCTAssertEqual(step.notifications.first??.trackName, status.track)
    }

    func testIdenticalUpdateNotifiesNobody() {
        let track = "Track \(UUID().uuidString)"

        let steps = applying(makeStatus(track: track), makeStatus(track: track))

        XCTAssertEqual(steps[0].notifications.count, 1)
        XCTAssertEqual(steps[1].notifications.count, 0)
        XCTAssertEqual(steps[1].metadata?.trackName, track)
    }

    func testSameStatusTriggeredAgainNotifiesNobody() {
        let status = makeStatus()

        let steps = applying(status, status)

        XCTAssertEqual(steps[1].notifications.count, 0)
    }

    func testNewTrackOnSameAlbumNotifies() {
        let steps = applying(makeStatus(album: "Same"), makeStatus(album: "Same"))

        XCTAssertEqual(steps[1].notifications.count, 1)
        XCTAssertEqual(steps[1].metadata?.trackName, steps[1].notifications.first??.trackName)
    }

    func testNewAlbumOnSameTrackNotifies() {
        let track = "Track \(UUID().uuidString)"

        let steps = applying(makeStatus(track: track, album: "First"),
                             makeStatus(track: track, album: "Second"))

        XCTAssertEqual(steps[1].notifications.count, 1)
        XCTAssertEqual(steps[1].metadata?.albumName, "Second")
    }

    func testLosingUsableMetadataNotifiesOnceAndThenStaysQuiet() {
        let steps = applying(makeStatus(),
                             makeStatus(changed: false),
                             makeStatus(changed: false))

        XCTAssertEqual(steps[1].notifications.count, 1)
        XCTAssertEqual(steps[2].notifications.count, 0)
    }

    func testDifferenceOnlyInCaseOrSpacesKeepsTheEarlierSpelling() {
        let track = "Track \(UUID().uuidString)"

        let steps = applying(makeStatus(track: track, album: "Album"),
                             makeStatus(track: "  \(track.uppercased())\n", album: " ALBUM "))

        XCTAssertEqual(steps[1].notifications.count, 0)
        XCTAssertEqual(steps[1].metadata?.trackName, track)
        XCTAssertEqual(steps[1].metadata?.albumName, "Album")
    }

    // MARK: - F5: other fields changing on the same song

    // F5 in the findings log: `UnifiedMetadata ==` compares only track and album, so
    // these updates are dropped, though the comment at StationMetadataManager.swift:186
    // says the update happens when metadata changed. These pin that today. A fix turns
    // them red, and they then change to assert the update arrives.

    /// Applies one song, then the same song differing as `edit` says.
    private func applyingChangeOnSameSong(_ edit: (ACStreamStatus) -> Void) -> [Step] {
        let track = "Track \(UUID().uuidString)"
        let first = makeStatus(track: track,
                               artist: "Old",
                               duration: 300,
                               elapsed: 10,
                               dj: "Old",
                               isLiveDJ: false)
        let second = makeStatus(track: track,
                                artist: "Old",
                                duration: 300,
                                elapsed: 10,
                                dj: "Old",
                                isLiveDJ: false)
        edit(second)
        return applying(first, second)
    }

    func testNewArtistOnSameSongIsDropped() {
        let steps = applyingChangeOnSameSong { $0.artist = "New" }

        XCTAssertEqual(steps[1].notifications.count, 0)
        XCTAssertEqual(steps[1].metadata?.artistName, "Old")
    }

    func testNewArtworkOnSameSongIsDropped() {
        let steps = applyingChangeOnSameSong { $0.artwork = URL(string: "https://example.test/new.png") }

        XCTAssertEqual(steps[1].notifications.count, 0)
        XCTAssertNil(steps[1].metadata?.artworkURL)
    }

    func testNewDJOnSameSongIsDropped() {
        let steps = applyingChangeOnSameSong { $0.dj = "New" }

        XCTAssertEqual(steps[1].notifications.count, 0)
        XCTAssertEqual(steps[1].metadata?.djName, "Old")
    }

    func testLiveDJFlagOnSameSongIsDropped() {
        let steps = applyingChangeOnSameSong { $0.isLiveDJ = true }

        XCTAssertEqual(steps[1].notifications.count, 0)
        XCTAssertEqual(steps[1].metadata?.isLiveDJ, false)
    }

    func testNewDurationOnSameSongIsDropped() {
        let steps = applyingChangeOnSameSong { $0.duration = 999 }

        XCTAssertEqual(steps[1].notifications.count, 0)
        XCTAssertEqual(steps[1].metadata?.duration, 300)
    }

    func testNewElapsedOnSameSongIsDropped() {
        let steps = applyingChangeOnSameSong { $0.elapsed = 99 }

        XCTAssertEqual(steps[1].notifications.count, 0)
        XCTAssertEqual(steps[1].metadata?.elapsed, 10)
    }

    func testNewBroadcastStartOnSameSongIsDropped() {
        let steps = applyingChangeOnSameSong { $0.broadcastStart = Date(timeIntervalSince1970: 1_000) }

        XCTAssertEqual(steps[1].notifications.count, 0)
        XCTAssertNil(steps[1].metadata?.broadcastStart)
    }

    // MARK: - Subscribing

    func testSubscribingDeliversTheCurrentMetadataImmediately() {
        let recorder = Recorder()
        recorder.isRecording = true
        let status = makeStatus()

        let currentTrack: String? = underFakeStatus {
            client.status = status
            manager.triggerMetadataUpdate()
            manager.subscribeToMetadataChanges { recorder.record($0) }
            let track = recorder.calls.first??.trackName
            recorder.isRecording = false
            return track
        }

        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(currentTrack, status.track)
    }

    // F6 in the findings log: this pins what unsubscribing does today, a removal that
    // finds nothing to remove. A fix turns it red, and it then changes to assert the
    // callback stops. The recorder is left switched off, because the callback stays
    // in the shared manager for the rest of the run.
    func testUnsubscribingLeavesTheCallbackSubscribed() {
        let recorder = Recorder()
        let callback: MetadataChangeCallback = { recorder.record($0) }
        let status = makeStatus()

        underFakeStatus {
            manager.subscribeToMetadataChanges(callback)
            manager.unsubscribeFromMetadataChanges(callback)
            recorder.isRecording = true
            client.status = status
            manager.triggerMetadataUpdate()
            recorder.isRecording = false
        }

        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls.first??.trackName, status.track)
    }
}
