import SwiftUI

// MARK: - Router

struct BattleView: View {
    let round: Int
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.myRole {
        case .judge:
            JudgeBattleView(round: round)
        case .competitor:
            PlayerBattleView(round: round)
        case .host, .audience:
            SpectatorView(round: round)
        }
    }
}

// MARK: - Shared components

struct SCProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: 6)
    }
}

struct NowPlayingCard: View {
    let song: MockSong
    let side: Side
    let progress: Double
    let phaseLabel: String

    @State private var libraryState: LibraryAddState = .idle

    enum LibraryAddState {
        case idle, adding, added, failed
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(phaseLabel)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(VerzuzTheme.clashColor(for: side))
                Spacer()
                // Add to Apple Music library (real catalog only).
                if !MusicMode.useDemoTracks {
                    Button { addToLibrary() } label: {
                        Image(systemName: libraryState == .added ? "checkmark" : "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(
                                Circle().fill(
                                    libraryState == .added
                                        ? .green
                                        : VerzuzTheme.clashColor(for: side).opacity(0.9)
                                )
                            )
                    }
                    .disabled(libraryState == .adding || libraryState == .added)
                    .accessibilityLabel("Add to Apple Music library")
                }
                Text(side.label.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(VerzuzTheme.clashColor(for: side).opacity(0.9))
                    .clipShape(Capsule())
            }
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(VerzuzTheme.clashGradient(for: side))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white)
                            .font(.system(size: 24))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(song.artist)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(SCTheme.secondaryText)
                }
                Spacer()
            }
            SCProgressBar(progress: progress, color: VerzuzTheme.clashColor(for: side))
        }
        .scCard()
    }

    private func addToLibrary() {
        guard libraryState == .idle else { return }
        libraryState = .adding
        Task { @MainActor in
            do {
                try await MusicMode.provider.addCurrentToLibrary()
                libraryState = .added
            } catch {
                libraryState = .failed
                // Reset so they can retry.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if libraryState == .failed { libraryState = .idle }
            }
        }
    }
}

/// Large now-playing for judges and non-turn players: the song dominates
/// the screen with real artwork.
struct BigNowPlayingCard: View {
    let song: MockSong
    let side: Side
    let progress: Double
    let phaseLabel: String

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(phaseLabel)
                    .font(VerzuzTheme.display(15))
                    .foregroundStyle(.white)
                Spacer()
                Text(side.label.uppercased())
                    .font(VerzuzTheme.display(12))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(VerzuzTheme.clashColor(for: side))
                    .clipShape(Capsule())
            }

            // Artwork — large, the hero of the card.
            ZStack {
                if let url = song.artworkURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: artworkFallback
                        }
                    }
                } else {
                    artworkFallback
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.5), radius: 16)

            VStack(spacing: 4) {
                Text(song.title)
                    .font(VerzuzTheme.display(26))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(song.artist)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }

            SCProgressBar(progress: progress, color: VerzuzTheme.clashColor(for: side))
        }
        .padding(20)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var artworkFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(VerzuzTheme.clashGradient(for: side))
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 220, height: 220)
    }
}

struct ScoreStrip: View {
    let results: [RoundResult]
    let totalRounds: Int
    let liveRound: Int
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...totalRounds, id: \.self) { n in
                VStack(spacing: 4) {
                    if let r = results.first(where: { $0.roundNumber == n }) {
                        Circle().fill(r.winner.color).frame(width: 18, height: 18)
                    } else if n == liveRound {
                        Circle()
                            .fill(Color.white.opacity(pulse ? 0.15 : 0.45))
                            .frame(width: 18, height: 18)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.9).repeatForever()) {
                                    pulse = true
                                }
                            }
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 2)
                            .frame(width: 18, height: 18)
                    }
                    Text("R\(n)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(SCTheme.secondaryText)
                }
            }
        }
    }
}

// MARK: - Judge view

@Observable
@MainActor
final class JudgeBattleViewModel {
    var appState: AppState!
    let round: Int
    var currentSide: Side = .red
    var nowPlaying: MockSong = MockData.round5Red
    var progress = 0.0
    var reacts: [String: Int] = ["🔥": 0, "👏": 0, "💯": 0, "🙌": 0, "❤️": 0]
    var bothPlayed = false
    /// Real mode: true once the first play row has arrived via realtime.
    var hasLivePlay = false

    private var playedSides: Set<Side> = []
    private var syncedPlayId: UUID?
    private var clipTask: Task<Void, Never>?
    private var didConfigure = false

    init(round: Int) { self.round = round }

    func configure(_ state: AppState) {
        guard !didConfigure else { return }
        didConfigure = true
        appState = state
        guard !SCPreview.isActive, state.roomId != nil else {
            // Preview: simulated 14s clips.
            currentSide = state.firstTurn
            nowPlaying = song(for: currentSide)
            hasLivePlay = true
            startClip()
            return
        }
        // Real mode: voice on, and plays drive synced playback (AppState owns
        // the single room subscription and fans plays events out here).
        Task {
            do {
                try await VoiceService.shared.connect(
                    room: state.roomCode, identity: state.username, role: state.myRole
                )
            } catch {
                state.backendError = error.localizedDescription
            }
        }
        state.onPlaysChanged = { [weak self] in
            Task { @MainActor [weak self] in await self?.playsChanged() }
        }
        Task { await playsChanged() } // in case a play landed before we subscribed
    }

    private func song(for side: Side) -> MockSong {
        side == .red ? MockData.round5Red : MockData.round5Blue
    }

    func react(_ emoji: String) {
        reacts[emoji, default: 0] += 1
        // v1: reacts are local-only. A future pass can fan these out over a
        // Supabase "reacts" table or LiveKit data messages.
    }

    private func startClip(duration: TimeInterval = 14) {
        clipTask?.cancel()
        progress = 0
        clipTask = Task { @MainActor in
            let steps = 100
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000 / Double(steps)))
                if Task.isCancelled { return }
                progress = Double(i) / Double(steps)
            }
            finishClip()
        }
    }

    /// Real mode: a new play row drives synced playback + server-clock progress.
    private func playsChanged() async {
        guard !SCPreview.isActive,
              let roundId = appState.currentRoundId else { return }
        do {
            guard let play = try await PlaySync.nextPlay(roundId: roundId, excluding: syncedPlayId),
                  let startedAt = play.startedAt else { return }
            syncedPlayId = play.id
            hasLivePlay = true
            currentSide = PlaySync.side(for: play.playerId, in: appState)
            nowPlaying = MockSong(title: play.title, artist: play.artist,
                                  isrc: play.isrc, appleMusicId: play.appleMusicId)
            startProgressPolling(startedAt: startedAt)
        } catch {
            appState.backendError = error.localizedDescription
        }
    }

    /// Progress from the server timestamp (replaces the mock timer).
    /// clipLength defaults to MusicMode.clipSeconds (90s real, 30s demo).
    private func startProgressPolling(startedAt: Date, clipLength: TimeInterval = MusicMode.clipSeconds) {
        clipTask?.cancel()
        progress = 0
        clipTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                progress = min(1, max(0, elapsed / clipLength))
                if progress >= 1 { finishClip(); return }
            }
        }
    }

    private func finishClip() {
        if !SCPreview.isActive {
            // Real mode: the clip is over — kill the heartbeat and the audio
            // so the finished track can't keep playing into voting.
            SyncEngine.shared.stop()
            MusicMode.provider.pause()
        }
        playedSides.insert(currentSide)
        if playedSides.count >= 2 {
            bothPlayed = true
        } else if SCPreview.isActive {
            currentSide = currentSide.opponent
            nowPlaying = song(for: currentSide)
            startClip()
        }
        // Real mode: the opponent's play arrives via realtime → playsChanged().
    }

    func goVoting() {
        guard !SCPreview.isActive, let roundId = appState.currentRoundId else {
            appState.go(.voting(round: round))
            return
        }
        Task {
            do {
                try await SupabaseService.shared.setRoundStatus(roundId: roundId, status: .voting)
                appState.go(.voting(round: round))
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    func stop() {
        clipTask?.cancel()
        if !SCPreview.isActive {
            SyncEngine.shared.stop()
            MusicMode.provider.pause()
            appState?.onPlaysChanged = nil
        }
    }
}

struct JudgeBattleView: View {
    let round: Int
    @Environment(AppState.self) private var appState
    @State private var viewModel: JudgeBattleViewModel

    init(round: Int) {
        self.round = round
        _viewModel = State(initialValue: JudgeBattleViewModel(round: round))
    }

    var body: some View {
        ZStack {
            VerzuzSplit(left: VerzuzTheme.clashA.color, right: VerzuzTheme.clashB.color)
            VMark(left: .black.opacity(0.85), right: .white.opacity(0.9))
                .frame(width: 260, height: 260)
                .opacity(0.25)
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VerzuzPill(text: "ROUND \(round)", fontSize: 24)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(SCTheme.red).frame(width: 8, height: 8)
                            Text("LIVE").font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(SCTheme.card).clipShape(Capsule())
                    }

                    ScoreStrip(results: appState.scoreboard, totalRounds: 5, liveRound: round)

                    if viewModel.hasLivePlay {
                        BigNowPlayingCard(
                            song: viewModel.nowPlaying,
                            side: viewModel.currentSide,
                            progress: viewModel.progress,
                            phaseLabel: "\(appState.name(for: viewModel.currentSide).uppercased()) PLAYS"
                        )
                    } else {
                        Text("Waiting for the first pick…")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(28)
                            .scCard()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill").foregroundStyle(SCTheme.gold)
                        Text("Live talk open — judges can discuss")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                    }

                    VStack(spacing: 10) {
                        Text("SEND SOME LOVE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                        HStack(spacing: 8) {
                            ForEach(Array(viewModel.reacts.keys.sorted()), id: \.self) { emoji in
                                Button { viewModel.react(emoji) } label: {
                                    VStack(spacing: 4) {
                                        Text(emoji).font(.system(size: 28))
                                        Text("\(viewModel.reacts[emoji, default: 0])")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(SCTheme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }

                    if viewModel.bothPlayed {
                        Button("Go to Voting") { viewModel.goVoting() }
                            .buttonStyle(SCPrimaryButton())
                    }
                }
                .padding(20)
            }
        }
        .task { viewModel.configure(appState) }
        .onDisappear { viewModel.stop() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Player view

@Observable
@MainActor
final class PlayerBattleViewModel {
    var appState: AppState!
    let round: Int
    var mySide: Side = .red
    var turn: Side = .red
    var nowPlaying: MockSong?
    var nowPlayingSide: Side = .red
    var progress = 0.0
    var searchText = ""
    var selectedSong: MockSong?
    var selectedTrack: SCTrack?
    var previewingId: UUID?
    var previewingTrackId: String?
    var previewProgress = 0.0
    var bothPlayed = false

    /// Have I played this round yet? (Picker stays visible until I have.)
    var hasPlayedThisRound: Bool { playedSides.contains(mySide) }
    /// Can I hit play right now? Only on my turn.
    var isMyTurnToPlay: Bool { turn == mySide && !bothPlayed }

    /// Real mode: live catalog results (replaces the mock song list).
    var catalogSongs: [MockSong] = []
    private var trackById: [String: SCTrack] = [:]

    private var playedSides: Set<Side> = []
    private var syncedPlayId: UUID?
    private var clipTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var didConfigure = false

    init(round: Int) { self.round = round }

    func configure(_ state: AppState) {
        guard !didConfigure else { return }
        didConfigure = true
        appState = state
        mySide = state.mySide
        turn = state.firstTurn
        guard !SCPreview.isActive, state.roomId != nil else {
            if turn != mySide { autoPlayOpponent() } // preview mock
            return
        }
        // Real mode: voice on, and plays drive synced playback (AppState owns
        // the single room subscription and fans plays events out here).
        Task {
            do {
                try await VoiceService.shared.connect(
                    room: state.roomCode, identity: state.username, role: state.myRole
                )
            } catch {
                state.backendError = error.localizedDescription
            }
        }
        state.onPlaysChanged = { [weak self] in
            Task { @MainActor [weak self] in await self?.playsChanged() }
        }
        Task { await playsChanged() } // in case a play landed before we subscribed
    }

    var songs: [MockSong] { mySide == .red ? MockData.redSongs : MockData.blueSongs }

    var filteredSongs: [MockSong] {
        if SCPreview.isActive {
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return songs }
            return songs.filter { $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) }
        }
        return catalogSongs
    }

    /// Real mode: live Apple Music catalog search, scoped to my battle
    /// artist (replaces the mock song list).
    func search() {
        guard !SCPreview.isActive else { return }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        let artist = appState.artistPick(for: mySide)
        Task {
            do {
                let tracks = try await MusicMode.provider.searchCatalog(query: q, artist: artist, broad: false)
                for t in tracks { trackById[t.appleMusicId] = t }
                catalogSongs = tracks.map(MockSong.init)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    var isMyTurnToPick: Bool { turn == mySide && nowPlaying == nil && !bothPlayed }

    private func opponentSong() -> MockSong {
        mySide == .red ? MockData.round5Blue : MockData.round5Red
    }

    func autoPlayOpponent() {
        nowPlayingSide = turn
        nowPlaying = opponentSong()
        startClip()
    }

    func playSelected() {
        // New picker path: SCTrack selected directly.
        if let track = selectedTrack {
            guard !SCPreview.isActive,
                  let roundId = appState.currentRoundId,
                  let playerId = appState.myParticipantId else { return }
            previewTask?.cancel()
            previewingId = nil
            previewingTrackId = nil
            selectedTrack = nil
            selectedSong = nil
            Task { try? await MusicMode.provider.pause() }
            Task {
                do {
                    _ = try await SupabaseService.shared.recordPlay(
                        roundId: roundId, playerId: playerId, track: track
                    )
                } catch {
                    appState.backendError = error.localizedDescription
                }
            }
            return
        }
        guard let song = selectedSong else { return }
        guard !SCPreview.isActive,
              let roundId = appState.currentRoundId,
              let playerId = appState.myParticipantId,
              let track = trackById[song.appleMusicId] else {
            playSelectedMock(song)
            return
        }
        previewTask?.cancel()
        previewingId = nil
        selectedSong = nil
        MusicMode.provider.pause() // stop any preview
        Task {
            do {
                // Single code path: our own realtime echo starts synced playback,
                // exactly like every other device in the room.
                _ = try await SupabaseService.shared.recordPlay(
                    roundId: roundId, playerId: playerId, track: track
                )
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    /// Solo testing only: fabricates the opponent's pick locally so a lone
    /// tester can play both sides of a round. No Supabase write — a solo
    /// room has no opponent participant row (and plays.player_id has a FK
    /// to participants). Drives the real SyncEngine + provider + progress
    /// path, so the rest of the round behaves like a real pick. In Apple
    /// Music mode the simulated pick is a real catalog track by the
    /// opponent's battle artist.
    func simulateOpponentPick() {
        guard isSoloOpponentTurn,
              !SCPreview.isActive,
              let roundId = appState.currentRoundId else { return }
        let side = turn
        let opponentArtist = appState.artistPick(for: side)
        Task {
            do {
                let track: SCTrack
                if MusicMode.useDemoTracks {
                    track = DemoMusicProvider.demoTracks.randomElement()!
                } else {
                    var results: [SCTrack] = []
                    if let opponentArtist {
                        results = (try? await MusicMode.provider.searchCatalog(query: "", artist: opponentArtist, broad: false)) ?? []
                    }
                    if results.isEmpty {
                        results = try await MusicMode.provider.searchCatalog(query: "love", artist: nil, broad: true)
                    }
                    guard let first = results.first else {
                        appState.backendError = "Couldn't find a track for the simulated pick."
                        return
                    }
                    track = first
                }
                nowPlayingSide = side
                nowPlaying = MockSong(track)
                let startedAt = Date()
                let play = Play(id: UUID(), roundId: roundId, playerId: UUID(),
                                isrc: track.isrc, appleMusicId: track.appleMusicId,
                                title: track.title, artist: track.artist,
                                artworkUrl: track.artworkURL?.absoluteString,
                                startedAt: startedAt, createdAt: startedAt)
                syncedPlayId = play.id
                previewTask?.cancel()
                previewingId = nil
                try await SyncEngine.shared.startSyncedPlay(play: play, via: MusicMode.provider)
                startProgressPolling(startedAt: startedAt)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    /// True when the side whose turn it is has no real competitor — i.e. solo
    /// testing. The simulate-pick button only appears then, so it can never
    /// show in a real two-player battle.
    var isSoloOpponentTurn: Bool {
        guard !bothPlayed, nowPlaying == nil, !isMyTurnToPick else { return false }
        let opponentId = turn == .red ? appState.redCompetitorId : appState.blueCompetitorId
        return opponentId == nil
    }

    private func playSelectedMock(_ song: MockSong) {
        previewTask?.cancel()
        previewingId = nil
        nowPlayingSide = mySide
        nowPlaying = song
        startClip()
    }

    /// Real mode: a new play row drives synced playback for EVERY device —
    /// including the picker's (via their own realtime echo).
    private func playsChanged() async {
        guard !SCPreview.isActive,
              let roundId = appState.currentRoundId else { return }
        do {
            guard let play = try await PlaySync.nextPlay(roundId: roundId, excluding: syncedPlayId),
                  let startedAt = play.startedAt else { return }
            syncedPlayId = play.id
            previewTask?.cancel()
            previewingId = nil
            nowPlayingSide = PlaySync.side(for: play.playerId, in: appState)
            nowPlaying = MockSong(title: play.title, artist: play.artist,
                                  isrc: play.isrc, appleMusicId: play.appleMusicId)
            startProgressPolling(startedAt: startedAt)
        } catch {
            appState.backendError = error.localizedDescription
        }
    }

    /// Progress from the server timestamp (replaces the mock timer).
    /// clipLength defaults to MusicMode.clipSeconds (90s real, 30s demo).
    private func startProgressPolling(startedAt: Date, clipLength: TimeInterval = MusicMode.clipSeconds) {
        clipTask?.cancel()
        progress = 0
        clipTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                progress = min(1, max(0, elapsed / clipLength))
                if progress >= 1 { finishClip(); return }
            }
        }
    }

    func endTurnEarly() {
        clipTask?.cancel()
        if !SCPreview.isActive {
            SyncEngine.shared.stop()
            MusicMode.provider.pause()
        }
        finishClip()
    }

    private func startClip(duration: TimeInterval = 14) {
        clipTask?.cancel()
        progress = 0
        clipTask = Task { @MainActor in
            let steps = 100
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000 / Double(steps)))
                if Task.isCancelled { return }
                progress = Double(i) / Double(steps)
            }
            finishClip()
        }
    }

    private func finishClip() {
        if !SCPreview.isActive {
            // Real mode: the clip is over — kill the heartbeat and the audio.
            // Otherwise the finished track keeps playing (and the heartbeat
            // keeps restarting it) straight through the next turn.
            SyncEngine.shared.stop()
            MusicMode.provider.pause()
        }
        playedSides.insert(nowPlayingSide)
        if playedSides.count >= 2 {
            bothPlayed = true
            nowPlaying = nil
        } else {
            turn = turn.opponent
            nowPlaying = nil
            guard SCPreview.isActive else { return } // opponent's pick arrives via realtime
            if turn != mySide { autoPlayOpponent() }
        }
    }

    func preview(_ song: MockSong) {
        if SCPreview.isActive { previewMock(song); return }
        // Real mode: private 30s Apple Music preview, not synced.
        if previewingId == song.id {
            MusicMode.provider.pause()
            previewingId = nil
            return
        }
        guard let track = trackById[song.appleMusicId] else { return }
        previewingId = song.id
        previewProgress = 0
        Task {
            do { try await MusicMode.provider.playPreview(track: track) }
            catch { appState.backendError = error.localizedDescription }
        }
    }

    /// New picker path: preview an SCTrack directly (real preview clip).
    func previewTrack(_ track: SCTrack) {
        if SCPreview.isActive { return }
        if previewingTrackId == track.id {
            MusicMode.provider.pausePreview()
            previewingTrackId = nil
            return
        }
        previewingTrackId = track.id
        Task {
            do { try await MusicMode.provider.playPreview(track: track) }
            catch { appState.backendError = error.localizedDescription }
        }
    }

    private func previewMock(_ song: MockSong) {
        if previewingId == song.id {
            previewTask?.cancel()
            previewingId = nil
            return
        }
        previewTask?.cancel()
        previewingId = song.id
        previewProgress = 0
        // Preview-only simulated preview progress (no audio in previews).
        previewTask = Task { @MainActor in
            for i in 1...60 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                previewProgress = Double(i) / 60.0
            }
            previewingId = nil
        }
    }

    func goVoting() {
        guard !SCPreview.isActive, let roundId = appState.currentRoundId else {
            appState.go(.voting(round: round))
            return
        }
        Task {
            do {
                try await SupabaseService.shared.setRoundStatus(roundId: roundId, status: .voting)
                appState.go(.voting(round: round))
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    func stop() {
        clipTask?.cancel()
        previewTask?.cancel()
        if !SCPreview.isActive {
            SyncEngine.shared.stop()
            MusicMode.provider.pause()
            appState?.onPlaysChanged = nil
        }
    }
}

struct PlayerBattleView: View {
    let round: Int
    @Environment(AppState.self) private var appState
    @State private var viewModel: PlayerBattleViewModel

    init(round: Int) {
        self.round = round
        _viewModel = State(initialValue: PlayerBattleViewModel(round: round))
    }

    var body: some View {
        ZStack {
            VerzuzSplit(left: VerzuzTheme.clashA.color, right: VerzuzTheme.clashB.color)
            VMark(left: .black.opacity(0.85), right: .white.opacity(0.9))
                .frame(width: 260, height: 260)
                .opacity(0.25)
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VerzuzPill(text: "ROUND \(round)", fontSize: 24)
                        Spacer()
                        Text(viewModel.mySide.label.uppercased())
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(VerzuzTheme.clashColor(for: viewModel.mySide).opacity(0.9))
                            .clipShape(Capsule())
                    }

                    ScoreStrip(results: appState.scoreboard, totalRounds: 5, liveRound: round)

                    if viewModel.bothPlayed {
                        VStack(spacing: 12) {
                            Text("BOTH TRACKS PLAYED")
                                .font(VerzuzTheme.display(22))
                                .foregroundStyle(.white)
                            Button("GO TO VOTING") { viewModel.goVoting() }
                                .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 18))
                        }
                        .padding(20)
                        .background(.black.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        // Now playing: big card when it's the opponent's track.
                        if let song = viewModel.nowPlaying {
                            if viewModel.nowPlayingSide == viewModel.mySide {
                                NowPlayingCard(
                                    song: song,
                                    side: viewModel.nowPlayingSide,
                                    progress: viewModel.progress,
                                    phaseLabel: "YOUR TRACK IS PLAYING"
                                )
                                Button("End Turn Early") { viewModel.endTurnEarly() }
                                    .buttonStyle(VerzuzButtonStyle(fill: .white.opacity(0.14), textColor: .white, fontSize: 16))
                            } else {
                                BigNowPlayingCard(
                                    song: song,
                                    side: viewModel.nowPlayingSide,
                                    progress: viewModel.progress,
                                    phaseLabel: "OPPONENT IS PLAYING"
                                )
                            }
                        } else if !viewModel.hasPlayedThisRound {
                            // Nothing playing yet and I haven't picked: waiting.
                            waitingView
                        }

                        // Picker: visible whenever I haven't played this round —
                        // pick your next track while the opponent plays.
                        if !viewModel.hasPlayedThisRound {
                            TrackPickerView(
                                selectedTrack: $viewModel.selectedTrack,
                                battleArtist: appState.artistPick(for: viewModel.mySide) ?? "",
                                canPlay: viewModel.isMyTurnToPlay,
                                onPlay: { viewModel.playSelected() },
                                onPreview: { viewModel.previewTrack($0) },
                                previewingTrackId: viewModel.previewingTrackId
                            )
                        }
                    }

                    if TestingFlags.showSkipControls {
                        testingCard
                    }
                }
                .padding(20)
            }
        }
        .task { viewModel.configure(appState) }
        .onDisappear { viewModel.stop() }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Opponent's turn and nothing playing yet — the "waiting" state.
    /// Includes a solo-testing button to simulate the opponent's pick so a
    /// lone tester can play both sides of a round.
    private var waitingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(waitingTitle)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(viewModel.turn.color)
            Text("Get ready — you're up next")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(SCTheme.secondaryText)
            if viewModel.isSoloOpponentTurn {
                Button("Simulate opponent pick") { viewModel.simulateOpponentPick() }
                    .buttonStyle(SCSecondaryButton())
            }
        }
        .scCard()
    }

    /// Waiting title that doesn't leak mock names for a phantom opponent.
    private var waitingTitle: String {
        let side = viewModel.turn
        let id = side == .red ? appState.redCompetitorId : appState.blueCompetitorId
        guard id != nil else { return "OPPONENT IS PICKING" }
        return "\(appState.name(for: side).uppercased()) IS PICKING"
    }

    /// Testing-only escape hatch (Settings > Testing): force-advance the
    /// round state machine without waiting out full clips.
    private var testingCard: some View {
        VStack(spacing: 10) {
            Text("TESTING CONTROLS")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.orange)
            HStack(spacing: 10) {
                Button("End turn") { viewModel.endTurnEarly() }
                    .buttonStyle(SCSecondaryButton())
                    .disabled(viewModel.nowPlaying == nil)
                    .opacity(viewModel.nowPlaying == nil ? 0.4 : 1)
                Button("Skip to voting") { viewModel.goVoting() }
                    .buttonStyle(SCSecondaryButton())
            }
        }
        .scCard()
    }

    private var pickView: some View {
        VStack(spacing: 12) {
            Text("YOUR TURN — PICK A TRACK")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(VerzuzTheme.clashColor(for: viewModel.mySide))

            TextField("Search your songs", text: $viewModel.searchText)
                .onSubmit { viewModel.search() }
                .padding(12)
                .background(SCTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            ForEach(viewModel.filteredSongs) { song in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(song.artist)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                    }
                    Spacer()
                    if viewModel.previewingId == song.id {
                        SCProgressBar(progress: viewModel.previewProgress, color: .white)
                            .frame(width: 60)
                    }
                    Button {
                        viewModel.preview(song)
                    } label: {
                        Image(systemName: viewModel.previewingId == song.id ? "pause.fill" : "play.fill")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(viewModel.selectedSong?.id == song.id
                              ? VerzuzTheme.clashColor(for: viewModel.mySide).opacity(0.25)
                              : SCTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.selectedSong?.id == song.id ? VerzuzTheme.clashColor(for: viewModel.mySide) : .clear, lineWidth: 2)
                )
                .onTapGesture { viewModel.selectedSong = song }
            }

            Button("Play This Track") { viewModel.playSelected() }
                .buttonStyle(SCPrimaryButton())
                .disabled(viewModel.selectedSong == nil)
                .opacity(viewModel.selectedSong == nil ? 0.4 : 1)
        }
        .scCard()
    }
}

// MARK: - Audience / host spectator view

// MARK: - Spectator view (host / audience)

@Observable
@MainActor
final class SpectatorViewModel {
    var appState: AppState!
    var nowPlaying: MockSong?
    var currentSide: Side = .red
    var progress = 0.0
    var hasLivePlay = false

    private var syncedPlayId: UUID?
    private var clipTask: Task<Void, Never>?
    private var didConfigure = false

    func configure(_ state: AppState) {
        guard !didConfigure else { return }
        didConfigure = true
        appState = state
        guard !SCPreview.isActive, state.roomId != nil else {
            nowPlaying = MockData.round5Red // preview placeholder
            progress = 0.32
            return
        }
        // Audience tokens are subscribe-only; host/judge tokens can publish.
        Task {
            do {
                try await VoiceService.shared.connect(
                    room: state.roomCode, identity: state.username, role: state.myRole
                )
            } catch {
                state.backendError = error.localizedDescription
            }
        }
        state.onPlaysChanged = { [weak self] in
            Task { @MainActor [weak self] in await self?.playsChanged() }
        }
        Task { await playsChanged() }
    }

    private func playsChanged() async {
        guard !SCPreview.isActive,
              let roundId = appState.currentRoundId else { return }
        do {
            guard let play = try await PlaySync.nextPlay(roundId: roundId, excluding: syncedPlayId),
                  let startedAt = play.startedAt else { return }
            syncedPlayId = play.id
            hasLivePlay = true
            currentSide = PlaySync.side(for: play.playerId, in: appState)
            nowPlaying = MockSong(title: play.title, artist: play.artist,
                                  isrc: play.isrc, appleMusicId: play.appleMusicId)
            clipTask?.cancel()
            progress = 0
            clipTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if Task.isCancelled { return }
                    progress = min(1, max(0, Date().timeIntervalSince(startedAt) / MusicMode.clipSeconds))
                }
            }
        } catch {
            appState.backendError = error.localizedDescription
        }
    }

    func stop() {
        clipTask?.cancel()
        if !SCPreview.isActive {
            SyncEngine.shared.stop()
            MusicMode.provider.pause()
            appState?.onPlaysChanged = nil
        }
    }
}

struct SpectatorView: View {
    let round: Int
    @Environment(AppState.self) private var appState
    @State private var viewModel = SpectatorViewModel()

    var body: some View {
        ZStack {
            VerzuzSplit(left: VerzuzTheme.clashA.color, right: VerzuzTheme.clashB.color)
            VMark(left: .black.opacity(0.85), right: .white.opacity(0.9))
                .frame(width: 260, height: 260)
                .opacity(0.25)
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VerzuzPill(text: "ROUND \(round)", fontSize: 24)
                        Spacer()
                    }

                    ScoreStrip(results: appState.scoreboard, totalRounds: 5, liveRound: round)

                    if let song = viewModel.nowPlaying {
                        NowPlayingCard(
                            song: song,
                            side: viewModel.currentSide,
                            progress: viewModel.progress,
                            phaseLabel: "\(appState.name(for: viewModel.currentSide).uppercased()) PLAYS"
                        )
                    } else {
                        Text("Waiting for the first pick…")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(28)
                            .scCard()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "ear.fill").foregroundStyle(SCTheme.secondaryText)
                        Text("You're in the audience — listen only")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                    }
                    .scCard()
                }
                .padding(20)
            }
        }
        .task { viewModel.configure(appState) }
        .onDisappear { viewModel.stop() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview("Judge view") {
    JudgeBattleView(round: 5)
        .environment(MockData.previewState())
}

#Preview("Player view") {
    let state = MockData.previewState()
    state.myRole = .competitor
    return PlayerBattleView(round: 5)
        .environment(state)
}
