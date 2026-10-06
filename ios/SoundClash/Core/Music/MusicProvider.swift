import Foundation

// MARK: - SCTrack

/// Lightweight, UI-friendly track. Apple Music only (per product decision).
struct SCTrack: Identifiable, Hashable, Sendable {
    var id: String { appleMusicId }
    let appleMusicId: String
    let isrc: String
    let title: String
    let artist: String
    let artworkURL: URL?
}

// MARK: - Playback state / errors

enum PlaybackState: Sendable {
    case playing
    case paused
    case stopped
}

enum MusicError: Error, LocalizedError {
    case notAuthorized
    case noSubscription
    case trackNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access wasn't granted. Enable it in Settings to play tracks."
        case .noSubscription:
            return "An Apple Music subscription is required to play full tracks."
        case .trackNotFound:
            return "Couldn't find that track in the Apple Music catalog."
        }
    }
}

// MARK: - Protocol

/// Playback abstraction. Apple Music only.
protocol MusicProvider: AnyObject {
    /// Fired on play/pause/stop transitions (best-effort; the heartbeat in
    /// SyncEngine is the source of truth for drift).
    var onPlaybackStateChange: ((PlaybackState) -> Void)? { get set }

    var isPlaying: Bool { get }

    /// Requests Apple Music authorization AND verifies catalog playback rights.
    func requestAuthorization() async throws

    /// Catalog search for the track picker.
    func searchCatalog(query: String) async throws -> [SCTrack]

    /// Queue the track, then begin playback at `startAt` (wall clock).
    /// This is the sync mechanism: every device is handed the same server
    /// timestamp and starts the same track at the same instant.
    func play(track: SCTrack, startAt: Date) async throws

    /// Private, unsynced 30-second preview for the track picker.
    func playPreview(track: SCTrack) async throws

    func pause()

    /// Coarse re-sync primitive: restarts the current track from the top.
    /// (Public MusicKit exposes no seek API, so there is no fine-grained seek.)
    func restart() async throws

    /// Seconds into the current track. Used by SyncEngine for drift detection.
    func currentPlaybackTime() -> TimeInterval
}
