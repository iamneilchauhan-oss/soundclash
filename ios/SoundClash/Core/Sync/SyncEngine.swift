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
///      against actual `player.playbackTime`; drift > 0.75s triggers a coarse
///      re-sync (track restart — MusicKit has no seek API).
@Observable
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    private init() {}

    /// Max tolerated drift before a coarse re-sync.
    private let driftTolerance: TimeInterval = 0.75
    /// Heartbeat interval. Re-syncs can never happen more often than this.
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
        if drift > driftTolerance {
            // Coarse correction only: restart the track, then re-baseline the
            // clock to the restart moment. Without the re-baseline, `expected`
            // keeps growing from the original startedAt while `actual` resets
            // to 0 — so every heartbeat sees huge drift and restarts again,
            // which is audible as a ~5s loop that never plays through.
            try? await provider.restart()
            activePlay?.startedAt = Date()
        }
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
