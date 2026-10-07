import Foundation

/// Keeps every device playing the same track at the same position.
///
/// Server-authoritative: `Play.startedAt` is stamped by Postgres when the play
/// row is inserted (migration 002), so host clock skew shifts everyone equally
/// and nobody needs NTP. Flow:
///   1. A play row appears (realtime) with an authoritative startedAt.
///   2. `startSyncedPlay` schedules playback to begin at startedAt (or now, if
///      the timestamp is already past — the normal case for recordPlay).
///   3. A 5s heartbeat compares expected position (wall clock − startedAt)
///      against actual `player.playbackTime` and records the drift
///      (monitor-only — MusicKit has no seek API, so there is no safe
///      automatic correction; restarting was observed to kill playback).
@Observable
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    private init() {}

    /// Drift under this counts as "in sync" (informational only).
    private let driftTolerance: TimeInterval = 0.75
    /// Heartbeat interval for drift monitoring.
    private let heartbeatInterval: TimeInterval = 5.0

    private var heartbeatTask: Task<Void, Never>?
    private var activePlay: Play?
    private var provider: (any MusicProvider)?

    /// Last measured drift, for debugging / future UI.
    var lastDrift: TimeInterval = 0
    var isSynced = false

    /// Starts synced playback of a play row via the provider. Safe to call with
    /// a startedAt in the past (immediate start) or future (countdown wait).
    func startSyncedPlay(play: Play, via provider: any MusicProvider) async throws {
        stop()
        self.provider = provider
        self.activePlay = play
        let track = SCTrack(
            appleMusicId: play.appleMusicId,
            isrc: play.isrc,
            title: play.title,
            artist: play.artist,
            artworkURL: play.artworkUrl.flatMap(URL.init(string:))
        )
        try await provider.play(track: track, startAt: play.startedAt ?? Date())
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.heartbeatInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.checkDrift()
            }
        }
    }

    private func checkDrift() async {
        guard let play = activePlay,
              let startAt = play.startedAt,
              let provider else { return }
        let expected = Date().timeIntervalSince(startAt)
        guard expected >= 0 else { return } // countdown hasn't elapsed yet
        guard provider.isPlaying else { return } // paused/stopped — nothing to correct
        let actual = provider.currentPlaybackTime()
        let drift = abs(expected - actual)
        lastDrift = drift
        isSynced = drift <= driftTolerance
        // Monitor-only: no automatic restart. MusicKit exposes no seek API,
        // so restarting can't correct drift — it only re-introduces startup
        // latency, and repeated restarts were observed stuttering then
        // killing playback outright. The scheduled wall-clock start in
        // play(track:startAt:) is the sync mechanism; this heartbeat just
        // records how far off we are.
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        activePlay = nil
        provider = nil
        isSynced = false
        lastDrift = 0
    }
}
