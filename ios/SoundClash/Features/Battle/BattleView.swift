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

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(phaseLabel)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(side.color)
                Spacer()
                Text(side.label.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(side.color.opacity(0.9))
                    .clipShape(Capsule())
            }
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(SCTheme.sideGradient(side))
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
            SCProgressBar(progress: progress, color: side.color)
        }
        .scCard()
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
    /// clipLength should match the room's clipSeconds (90s default).
    private func startProgressPolling(startedAt: Date, clipLength: TimeInterval = 90) {
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
            SCTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("ROUND \(round)")
                            .font(SCTheme.title(28))
                            .foregroundStyle(.white)
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
                        NowPlayingCard(
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
    var previewingId: UUID?
    var previewProgress = 0.0
    var bothPlayed = false

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

    /// Real mode: live Apple Music catalog search (replaces the mock song list).
    func search() {
        guard !SCPreview.isActive else { return }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        Task {
            do {
                let tracks = try await MusicMode.provider.searchCatalog(query: q)
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
    /// clipLength should match the room's clipSeconds (90s default).
    private func startProgressPolling(startedAt: Date, clipLength: TimeInterval = 90) {
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
            SCTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("ROUND \(round)")
                            .font(SCTheme.title(28))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(viewModel.mySide.label.uppercased())
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(viewModel.mySide.color.opacity(0.9))
                            .clipShape(Capsule())
                    }

                    ScoreStrip(results: appState.scoreboard, totalRounds: 5, liveRound: round)

                    if viewModel.bothPlayed {
                        VStack(spacing: 12) {
                            Text("Both tracks played")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Button("Go to Voting") { viewModel.goVoting() }
                                .buttonStyle(SCPrimaryButton())
                        }
                        .scCard()
                    } else if viewModel.isMyTurnToPick {
                        pickView
                    } else if let song = viewModel.nowPlaying {
                        NowPlayingCard(
                            song: song,
                            side: viewModel.nowPlayingSide,
                            progress: viewModel.progress,
                            phaseLabel: viewModel.nowPlayingSide == viewModel.mySide
                                ? "YOUR TRACK IS PLAYING" : "OPPONENT IS PLAYING"
                        )
                        if viewModel.nowPlayingSide == viewModel.mySide {
                            Button("End Turn Early") { viewModel.endTurnEarly() }
                                .buttonStyle(SCSecondaryButton())
                        } else {
                            Text("Get ready — you're up next")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(SCTheme.secondaryText)
                        }
                    }
                }
                .padding(20)
            }
        }
        .task { viewModel.configure(appState) }
        .onDisappear { viewModel.stop() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var pickView: some View {
        VStack(spacing: 12) {
            Text("YOUR TURN — PICK A TRACK")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(viewModel.mySide.color)

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
                              ? viewModel.mySide.color.opacity(0.25)
                              : SCTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(viewModel.selectedSong?.id == song.id ? viewModel.mySide.color : .clear, lineWidth: 2)
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
                    progress = min(1, max(0, Date().timeIntervalSince(startedAt) / 90))
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
            SCTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("ROUND \(round)")
                        .font(SCTheme.title(28))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

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
