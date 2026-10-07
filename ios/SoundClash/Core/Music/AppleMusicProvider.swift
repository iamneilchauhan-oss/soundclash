import Foundation
import MusicKit
import AVFoundation
import UIKit

/// MusicKit implementation of MusicProvider. Apple Music only.
///
/// Audio architecture (see build-channel feedback):
/// - Battle playback runs on SystemMusicPlayer (separate audio session, via
///   the Music app process). This frees the app's session for previews.
/// - Previews play the real ~30s catalog preview clip (Song.previewAssets)
///   via AVPlayer in the app's session with `.duckOthers` — iOS auto-ducks
///   the battle track Maps-style while the clip plays, then restores it.
///   Only the previewing device is affected; everyone else stays in sync.
///
/// No developer token is fetched or set anywhere here — deliberately. On native
/// iOS there is no developer-token API: MusicKit attaches it automatically once
/// the MusicKit capability is enabled for the bundle ID and the user grants
/// authorization. (The token service's /v1/musickit-token endpoint is for
/// server-side Apple Music API use only.)
@MainActor
final class AppleMusicProvider: MusicProvider {
    static let shared = AppleMusicProvider()

    private init() {
        // Battle music must not keep playing when the app backgrounds.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
    }

    var onPlaybackStateChange: ((PlaybackState) -> Void)?

    /// Battle playback: system-wide, via the Music app process.
    private let player = SystemMusicPlayer.shared
    /// Private preview clips: app-local AVPlayer, ducked over the battle.
    private var previewPlayer: AVPlayer?
    private var previewEndObserver: NSObjectProtocol?
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
        // (Preview clips do NOT — they play without one.)
        let subscription = try await MusicSubscription.current
        guard subscription.canPlayCatalogContent else { throw MusicError.noSubscription }
    }

    // MARK: - Catalog

    func searchCatalog(query: String, artist: String?, broad: Bool) async throws -> [SCTrack] {
        let trimmedArtist = artist?.trimmingCharacters(in: .whitespaces)
        let scopedArtist = (trimmedArtist?.isEmpty == false) ? trimmedArtist! : nil
        // Bias the catalog ranking toward the artist, then filter strictly —
        // unless `broad` lifts the filter (features, writing credits, covers).
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
        var songs = Array(response.songs)
        if let scopedArtist, !broad {
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
                artworkURL: song.artwork?.url(width: 300, height: 300),
                isExplicit: song.contentRating == .explicit,
                albumName: song.albumTitle,
                duration: song.duration
            )
        }
    }

    func searchAlbums(artist: String) async throws -> [SCAlbum] {
        let q = artist.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var request = MusicCatalogSearchRequest(term: q, types: [Album.self])
        request.limit = 25
        let response = try await request.response()
        var seen = Set<String>()
        return Array(response.albums)
            .map { album in
                SCAlbum(
                    appleMusicId: album.id.rawValue,
                    title: album.title,
                    artist: album.artistName,
                    artworkURL: album.artwork?.url(width: 300, height: 300),
                    trackCount: album.trackCount ?? 0
                )
            }
            .filter { seen.insert($0.appleMusicId).inserted }
    }

    func albumTracks(_ album: SCAlbum) async throws -> [SCTrack] {
        let request = MusicCatalogResourceRequest<Album>(
            matching: \.id,
            equalTo: MusicItemID(rawValue: album.appleMusicId)
        )
        let response = try await request.response()
        guard let full = response.items.first else { return [] }
        let tracks = try await full.with(.songs).songs ?? []
        return tracks.map { song in
            SCTrack(
                appleMusicId: song.id.rawValue,
                isrc: song.isrc ?? "",
                title: song.title,
                artist: song.artistName,
                artworkURL: song.artwork?.url(width: 300, height: 300),
                isExplicit: song.contentRating == .explicit,
                albumName: album.title,
                duration: song.duration
            )
        }
    }

    func searchArtists(query: String) async throws -> [ArtistHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var request = MusicCatalogSearchRequest(term: q, types: [Artist.self])
        request.limit = 25
        let response = try await request.response()
        // De-dupe while preserving catalog ranking.
        var seen = Set<String>()
        return Array(response.artists)
            .map { ArtistHit(name: $0.name, artworkURL: $0.artwork?.url(width: 300, height: 300)) }
            .filter { seen.insert($0.name).inserted }
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

    // MARK: - Battle playback (SystemMusicPlayer)

    /// Sync mechanism: queue the song now, then sleep until the server-agreed
    /// wall-clock time before calling play(). Every device in the room does the
    /// same against the same Play.startedAt, so tracks start within a few
    /// hundred ms of each other. Drift after start is corrected by SyncEngine.
    func play(track: SCTrack, startAt: Date) async throws {
        let song = try await resolveSong(for: track)
        lastSong = song
        player.queue = [song]
        scheduledTask?.cancel()
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

    func pause() {
        scheduledTask?.cancel()
        stopPreview()
        player.pause()
        onPlaybackStateChange?(.paused)
    }

    /// Coarse re-sync: restart the current track. Public MusicKit has no seek
    /// API, so SyncEngine uses this when drift exceeds tolerance. Short battle
    /// clips make the restart cheap; precise scheduled starts (play(track:startAt:))
    /// are the primary sync mechanism, not this.
    func restart() async throws {
        guard let song = lastSong else { return }
        scheduledTask?.cancel()
        player.queue = [song]
        try await player.play()
        onPlaybackStateChange?(.playing)
    }

    func currentPlaybackTime() -> TimeInterval {
        player.playbackTime
    }

    func pausePreview() { stopPreview() }

    // MARK: - Previews (AVPlayer + ducking)

    /// Plays the real catalog preview clip (~30s, usually the hook) via
    /// AVPlayer. The app's audio session ducks the SystemMusicPlayer battle
    /// track while the clip plays, then restores it. Private and unsynced —
    /// battle state callbacks are untouched.
    func playPreview(track: SCTrack) async throws {
        let song = try await resolveSong(for: track)
        guard let previewURL = song.previewAssets?.first?.url else {
            throw MusicError.noPreview
        }
        stopPreview()

        try activateDucking()
        let item = AVPlayerItem(url: previewURL)
        let avPlayer = AVPlayer(playerItem: item)
        previewPlayer = avPlayer

        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopPreview() }
        }

        avPlayer.play()

        // Backup timeout: previews run ~30s; never leave the session ducked.
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 40_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.stopPreview() }
        }
    }

    /// Stops the preview and restores the audio session (unducks battle).
    private func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        if let observer = previewEndObserver {
            NotificationCenter.default.removeObserver(observer)
            previewEndObserver = nil
        }
        previewPlayer?.pause()
        previewPlayer = nil
        deactivateDucking()
    }

    private func activateDucking() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: .duckOthers)
        try session.setActive(true)
    }

    private func deactivateDucking() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Library

    /// Adds the current battle track to the user's Apple Music library.
    /// Requires a subscription (same as catalog playback).
    func addCurrentToLibrary() async throws {
        guard let song = lastSong else { throw MusicError.trackNotFound }
        try await MusicLibrary.shared.add(song)
    }
}
