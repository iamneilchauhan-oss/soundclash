import Foundation
import AVFoundation

/// Stand-in music backend for testing the full battle flow while the Apple
/// Music catalog is unavailable (e.g. before the MusicKit App Service is
/// enabled for the bundle ID).
///
/// Generates short original synthesized tracks on-device (cached as WAVs in
/// the caches directory) and plays them with AVAudioPlayer, honoring the
/// same wall-clock scheduled starts as the real provider — so the sync
/// engine, heartbeat, and drift repair all exercise for real. Toggle it in
/// Settings > Testing. Delete this file once real catalog testing begins.
@MainActor
final class DemoMusicProvider: MusicProvider {
    static let shared = DemoMusicProvider()

    private init() {}

    var onPlaybackStateChange: ((PlaybackState) -> Void)?

    private var player: AVAudioPlayer?
    private var scheduledTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var currentTrackId: String?

    var isAuthorized: Bool { true }
    var isPlaying: Bool { player?.isPlaying == true }

    static let demoTracks: [SCTrack] = [
        SCTrack(appleMusicId: "demo-1", isrc: "", title: "Sunset Drive (Demo)", artist: "SoundClash Demo", artworkURL: nil),
        SCTrack(appleMusicId: "demo-2", isrc: "", title: "Neon Skyline (Demo)", artist: "SoundClash Demo", artworkURL: nil),
        SCTrack(appleMusicId: "demo-3", isrc: "", title: "Midnight Circuit (Demo)", artist: "SoundClash Demo", artworkURL: nil),
        SCTrack(appleMusicId: "demo-4", isrc: "", title: "Golden Hour (Demo)", artist: "SoundClash Demo", artworkURL: nil),
        SCTrack(appleMusicId: "demo-5", isrc: "", title: "Electric Palm (Demo)", artist: "SoundClash Demo", artworkURL: nil),
        SCTrack(appleMusicId: "demo-6", isrc: "", title: "Afterglow (Demo)", artist: "SoundClash Demo", artworkURL: nil),
    ]

    // MARK: - MusicProvider

    /// Nothing to authorize — always "granted".
    func requestAuthorization() async throws {}

    func searchCatalog(query: String, artist: String?) async throws -> [SCTrack] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var hits = Self.demoTracks
        if let a = artist?.trimmingCharacters(in: .whitespaces).lowercased(), !a.isEmpty {
            let artistHits = hits.filter { $0.artist.lowercased().contains(a) }
            if !artistHits.isEmpty { hits = artistHits }
        }
        guard !q.isEmpty else { return hits }
        let qHits = hits.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
        return qHits.isEmpty ? hits : qHits
    }

    /// Same wall-clock scheduled-start contract as AppleMusicProvider: render
    /// (or reuse) the track's audio now, then sleep until `startAt`.
    func play(track: SCTrack, startAt: Date) async throws {
        try ensurePlayer(for: track)
        scheduledTask?.cancel()
        // A stale preview auto-stop must never fire during a synced play.
        previewTask?.cancel()
        scheduledTask = Task {
            let delay = startAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self.player?.play()
            self.onPlaybackStateChange?(.playing)
        }
    }

    func playPreview(track: SCTrack) async throws {
        try ensurePlayer(for: track)
        previewTask?.cancel()
        scheduledTask?.cancel()
        player?.currentTime = 0
        player?.play()
        onPlaybackStateChange?(.playing)
        // Previews are private and unsynced: auto-stop after 30 seconds.
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            self.player?.pause()
            self.onPlaybackStateChange?(.paused)
        }
    }

    func pause() {
        scheduledTask?.cancel()
        previewTask?.cancel()
        player?.pause()
        onPlaybackStateChange?(.paused)
    }

    func restart() async throws {
        previewTask?.cancel()
        scheduledTask?.cancel()
        player?.currentTime = 0
        player?.play()
        onPlaybackStateChange?(.playing)
    }

    func currentPlaybackTime() -> TimeInterval {
        player?.currentTime ?? 0
    }

    // MARK: - Player

    private func ensurePlayer(for track: SCTrack) throws {
        if currentTrackId == track.appleMusicId, player != nil { return }
        pause()
        let url = Self.renderedURL(for: track)
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        self.player = player
        self.currentTrackId = track.appleMusicId
    }

    // MARK: - On-device track synthesis

    private static func renderedURL(for track: SCTrack) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("soundclash-\(track.appleMusicId).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let index = demoTracks.firstIndex(where: { $0.appleMusicId == track.appleMusicId }) ?? 0
            if let data = renderWAV(trackIndex: index) {
                try? data.write(to: url)
            }
        }
        return url
    }

    /// Renders a ~30s original loop (matches MusicMode.clipSeconds): an
    /// arpeggiated I–vi–IV–V progression with a soft bass, each demo track
    /// in a different key and tempo.
    private static func renderWAV(trackIndex i: Int) -> Data? {
        let sampleRate = 44100.0
        let duration = 30.0
        let total = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: total)

        let keys = [220.0, 246.94, 261.63, 293.66, 329.63, 349.23] // A3..F4
        let root = keys[i % keys.count]
        let bpm = 96.0 + Double(i) * 8.0
        let eighth = 60.0 / bpm / 2.0
        let barLen = eighth * 8
        let barRoots = [0, -4, 5, 7] // I, vi, IV, V in semitones
        let pattern = [0, 4, 7, 12, 7, 4] // arpeggio, semitones

        var t = 0.0
        var step = 0
        while t < duration {
            let bar = Int(t / barLen) % barRoots.count
            let chordRoot = root * pow(2.0, Double(barRoots[bar]) / 12.0)
            let st = pattern[step % pattern.count]
            let freq = chordRoot * pow(2.0, Double(st) / 12.0)
            addNote(to: &samples, freq: freq, start: t, len: eighth * 1.9,
                    sampleRate: sampleRate, gain: 0.5)
            if step % 8 == 0 { // bass on each bar
                addNote(to: &samples, freq: chordRoot / 2, start: t, len: barLen * 0.9,
                        sampleRate: sampleRate, gain: 0.35)
            }
            t += eighth
            step += 1
        }
        return wavData(from: samples, sampleRate: UInt32(sampleRate))
    }

    private static func addNote(to samples: inout [Float], freq: Double, start: Double,
                               len: Double, sampleRate: Double, gain: Float) {
        let startIdx = Int(start * sampleRate)
        let count = Int(len * sampleRate)
        for n in 0..<count {
            let idx = startIdx + n
            guard idx < samples.count else { break }
            let tt = Double(n) / sampleRate
            let env = exp(-3.0 * tt / len) * min(1.0, tt / 0.008)
            let s = sin(2 * .pi * freq * tt)
                + 0.3 * sin(2 * .pi * 2 * freq * tt)
                + 0.15 * sin(2 * .pi * 3 * freq * tt)
            samples[idx] += Float(s * env) * gain * 0.6
        }
    }

    private static func wavData(from samples: [Float], sampleRate: UInt32) -> Data {
        var peak: Float = 0.0001
        for s in samples { peak = max(peak, abs(s)) }
        let scale = 0.85 / peak

        var data = Data()
        let numSamples = samples.count
        data.append(contentsOf: "RIFF".utf8)
        data.appendLE(UInt32(36 + numSamples * 2))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1)) // PCM
        data.appendLE(UInt16(1)) // mono
        data.appendLE(sampleRate)
        data.appendLE(sampleRate * 2) // byte rate
        data.appendLE(UInt16(2)) // block align
        data.appendLE(UInt16(16)) // bits per sample
        data.append(contentsOf: "data".utf8)
        data.appendLE(UInt32(numSamples * 2))
        for s in samples {
            let v = Int16(max(-1.0, min(1.0, s * scale)) * 32767)
            data.appendLE(UInt16(bitPattern: v))
        }
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
