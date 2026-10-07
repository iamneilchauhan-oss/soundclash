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
    var isExplicit: Bool = false
    var albumName: String?
    var duration: TimeInterval?

    /// "E" badge + duration line, Apple Music style.
    var detailLine: String {
        var parts: [String] = []
        if isExplicit { parts.append("E") }
        if let albumName { parts.append(albumName) }
        if let duration {
            let m = Int(duration) / 60
            let s = Int(duration) % 60
            parts.append(String(format: "%d:%02d", m, s))
        }
        return parts.joined(separator: "  ·  ")
    }
}

/// Lightweight album for the album-nav tab.
struct SCAlbum: Identifiable, Hashable, Sendable {
    var id: String { appleMusicId }
    let appleMusicId: String
    let title: String
    let artist: String
    let artworkURL: URL?
    var trackCount: Int = 0
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
    case noPreview

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access wasn't granted. Enable it in Settings to play tracks."
        case .noSubscription:
            return "An Apple Music subscription is required to play full tracks."
        case .trackNotFound:
            return "Couldn't find that track in the Apple Music catalog."
        case .noPreview:
            return "No preview clip is available for this track."
        }
    }
}

// MARK: - Protocol

/// One artist result for the matchup picker.
struct ArtistHit: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let artworkURL: URL?
}

/// Playback abstraction. Apple Music only.
protocol MusicProvider: AnyObject {
    /// Fired on play/pause/stop transitions (best-effort; the heartbeat in
    /// SyncEngine is the source of truth for drift).
    var onPlaybackStateChange: ((PlaybackState) -> Void)? { get set }

    var isPlaying: Bool { get }

    /// Whether the provider is ready to play (authorization granted, or
    /// always true for providers that need none).
    var isAuthorized: Bool { get }

    /// Requests Apple Music authorization AND verifies catalog playback rights.
    func requestAuthorization() async throws

    /// Catalog search for the track picker. When `artist` is non-nil the
    /// results are scoped to that artist's songs (the battle's artist
    /// matchup). When `broad` is true, the artist filter is lifted — results
    /// may include features, writing credits, and covers involving the artist.
    func searchCatalog(query: String, artist: String?, broad: Bool) async throws -> [SCTrack]

    /// Albums for the album-nav tab, scoped to the battle artist.
    func searchAlbums(artist: String) async throws -> [SCAlbum]

    /// Tracks on an album (for the album-nav tab drill-in).
    func albumTracks(_ album: SCAlbum) async throws -> [SCTrack]

    /// Artist-name search for the matchup picker.
    func searchArtists(query: String) async throws -> [ArtistHit]

    /// Queue the track, then begin playback at `startAt` (wall clock).
    /// This is the sync mechanism: every device is handed the same server
    /// timestamp and starts the same track at the same instant.
    func play(track: SCTrack, startAt: Date) async throws

    /// Private, unsynced 30-second preview for the track picker.
    func playPreview(track: SCTrack) async throws

    func pause()

    /// Stops a preview without touching battle playback. The pause button
    /// on a previewing track must not silence the battle.
    func pausePreview()

    /// Coarse re-sync primitive: restarts the current track from the top.
    /// (Public MusicKit exposes no seek API, so there is no fine-grained seek.)
    func restart() async throws

    /// Seconds into the current track. Used by SyncEngine for drift detection.
    func currentPlaybackTime() -> TimeInterval

    /// Adds the currently loaded battle track to the user's Apple Music
    /// library. Real catalog only — demo synth tracks have no catalog IDs.
    func addCurrentToLibrary() async throws
}
