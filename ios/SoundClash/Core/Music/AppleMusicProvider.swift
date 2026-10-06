import Foundation
import MusicKit

/// MusicKit implementation of MusicProvider. Apple Music only.
///
/// No developer token is fetched or set anywhere here — deliberately. On native
/// iOS there is no developer-token API: MusicKit attaches it automatically once
/// the MusicKit capability is enabled for the bundle ID and the user grants
/// authorization. (The token service's /v1/musickit-token endpoint is for
/// server-side Apple Music API use only.)
@MainActor
final class AppleMusicProvider: MusicProvider {
    static let shared = AppleMusicProvider()

    private init() {}

    var onPlaybackStateChange: ((PlaybackState) -> Void)?

    private let player = ApplicationMusicPlayer.shared
    private var scheduledTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    /// Last successfully queued song — the restart() target (no seek API exists).
    private var lastSong: Song?

    var isAuthorized: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    var isPlaying: Bool {
        player.state.playbackStatus == .playing
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        let status = await MusicAuthorization.request()
        guard status == .authorized else { throw MusicError.notAuthorized }
        // Catalog playback requires an active Apple Music subscription.
        let subscription = try await MusicSubscription.current
        guard subscription.canPlayCatalogContent else { throw MusicError.noSubscription }
    }

    // MARK: - Catalog

    func searchCatalog(query: String, artist: String?) async throws -> [SCTrack] {
        let trimmedArtist = artist?.trimmingCharacters(in: .whitespaces)
        let scopedArtist = (trimmedArtist?.isEmpty == false) ? trimmedArtist! : nil
        // Bias the catalog ranking toward the artist, then filter strictly —
        // the battle picker shows this artist's songs only.
        let term: String
        if let scopedArtist {
            let q = query.trimmingCharacters(in: .whitespaces)
            term = q.isEmpty ? scopedArtist : "\(scopedArtist) \(q)"
        } else {
            term = query
        }
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = 25
        let response = try await request.response()
        var songs = response.songs
        if let scopedArtist {
            let hits = songs.filter { $0.artistName.localizedCaseInsensitiveContains(scopedArtist) }
            // If the strict filter empties the list (name mismatch), fall back
            // to the ranked results rather than showing a dead picker.
            if !hits.isEmpty { songs = hits }
        }
        return songs.map { song in
            SCTrack(
                appleMusicId: song.id.rawValue,
                isrc: song.isrc ?? "",
                title: song.title,
                artist: song.artistName,
                artworkURL: song.artwork?.url(width: 300, height: 300)
            )
        }
    }

    /// Resolves a lightweight SCTrack back to a full catalog Song for playback.
    private func resolveSong(for track: SCTrack) async throws -> Song {
        let request = MusicCatalogResourceRequest<Song>(
            matching: \.id,
            equalTo: MusicItemID(rawValue: track.appleMusicId)
        )
        let response = try await request.response()
        guard let song = response.items.first else { throw MusicError.trackNotFound }
        return song
    }

    // MARK: - Playback

    /// Sync mechanism: queue the song now, then sleep until the server-agreed
    /// wall-clock time before calling play(). Every device in the room does the
    /// same against the same Play.startedAt, so tracks start within a few
    /// hundred ms of each other. Drift after start is corrected by SyncEngine.
    func play(track: SCTrack, startAt: Date) async throws {
        let song = try await resolveSong(for: track)
        lastSong = song
        player.queue = [song]
        scheduledTask?.cancel()
        // A stale preview auto-stop must never fire during a synced play —
        // 30s after any preview it would otherwise pause the battle track.
        previewTask?.cancel()
        scheduledTask = Task {
            let delay = startAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            do {
                try await self.player.play()
                self.onPlaybackStateChange?(.playing)
            } catch {
                self.onPlaybackStateChange?(.stopped)
            }
        }
    }

    func playPreview(track: SCTrack) async throws {
        let song = try await resolveSong(for: track)
        lastSong = song
        previewTask?.cancel()
        scheduledTask?.cancel()
        player.queue = [song]
        try await player.play()
        onPlaybackStateChange?(.playing)
        // Previews are private and unsynced: auto-stop after 30 seconds.
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            self.player.pause()
            self.onPlaybackStateChange?(.paused)
        }
    }

    func pause() {
        scheduledTask?.cancel()
        previewTask?.cancel()
        player.pause()
        onPlaybackStateChange?(.paused)
    }

    /// Coarse re-sync: restart the current track. Public MusicKit has no seek
    /// API, so SyncEngine uses this when drift exceeds tolerance. Short battle
    /// clips make the restart cheap; precise scheduled starts (play(track:startAt:))
    /// are the primary sync mechanism, not this.
    func restart() async throws {
        guard let song = lastSong else { return }
        previewTask?.cancel()
        scheduledTask?.cancel()
        player.queue = [song]
        try await player.play()
        onPlaybackStateChange?(.playing)
    }

    func currentPlaybackTime() -> TimeInterval {
        player.playbackTime
    }
}
