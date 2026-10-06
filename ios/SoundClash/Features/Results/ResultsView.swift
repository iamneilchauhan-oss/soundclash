import SwiftUI

@Observable
@MainActor
final class ResultsViewModel {
    var appState: AppState!

    func configure(_ state: AppState) {
        appState = state
        guard !SCPreview.isActive else { return }
        // Real mode: build the results from actual rounds/plays/winner rows.
        Task { await loadRealResults() }
    }

    /// Rounds 1–4 from the mock scoreboard, plus the live round 5 just voted on.
    var displayRounds: [RoundResult] {
        if SCPreview.isActive {
            var rounds = appState.scoreboard
            rounds.append(
                RoundResult(
                    roundNumber: 5,
                    redSong: MockData.round5Red,
                    blueSong: MockData.round5Blue,
                    winner: appState.finalRoundWinner ?? .red
                )
            )
            return rounds.sorted { $0.roundNumber < $1.roundNumber }
        }
        return realResults.sorted { $0.roundNumber < $1.roundNumber }
    }

    private var realResults: [RoundResult] = []

    /// Real mode: one RoundResult per finished round, from real rows.
    private func loadRealResults() async {
        guard let roomId = appState.roomId else { return }
        do {
            let rounds = try await SupabaseService.shared.fetchRounds(roomId: roomId)
            var results: [RoundResult] = []
            for round in rounds {
                let plays = try await SupabaseService.shared.fetchPlays(roundId: round.id)
                let redPlay = plays.first { $0.playerId == appState.redCompetitorId }
                let bluePlay = plays.first { $0.playerId == appState.blueCompetitorId }
                let redSong = redPlay.map {
                    MockSong(title: $0.title, artist: $0.artist, isrc: $0.isrc, appleMusicId: $0.appleMusicId)
                } ?? MockSong(title: "—", artist: "", isrc: "", appleMusicId: "")
                let blueSong = bluePlay.map {
                    MockSong(title: $0.title, artist: $0.artist, isrc: $0.isrc, appleMusicId: $0.appleMusicId)
                } ?? MockSong(title: "—", artist: "", isrc: "", appleMusicId: "")
                let winnerSide: Side? = {
                    guard let winnerId = round.winnerId else { return nil }
                    return winnerId == appState.blueCompetitorId ? .blue : .red
                }()
                results.append(RoundResult(
                    roundNumber: round.roundNumber,
                    redSong: redSong, blueSong: blueSong,
                    winner: winnerSide ?? appState.finalRoundWinner ?? .red
                ))
            }
            realResults = results
        } catch {
            appState.backendError = error.localizedDescription
        }
    }

    var winner: Side {
        let red = displayRounds.filter { $0.winner == .red }.count
        let blue = displayRounds.filter { $0.winner == .blue }.count
        return red >= blue ? .red : .blue
    }

    var score: (red: Int, blue: Int) {
        (
            red: displayRounds.filter { $0.winner == .red }.count,
            blue: displayRounds.filter { $0.winner == .blue }.count
        )
    }

    func rematch() {
        appState.finalRoundWinner = nil
        guard !SCPreview.isActive, let roomId = appState.roomId else {
            appState.go(.matchup)
            return
        }
        // Real mode: fresh rounds, same room + crew; the room status drops back
        // to lobby, and other devices rejoin the flow when the host advances
        // to the matchup (their room subscription follows the status).
        Task {
            do {
                try await SupabaseService.shared.resetRoom(roomId: roomId)
                appState.currentRoundId = nil
                appState.redCompetitorId = nil
                appState.blueCompetitorId = nil
                appState.currentRoundNumber = 1
                appState.go(.matchup)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    func home() {
        if !SCPreview.isActive {
            Task {
                await VoiceService.shared.disconnect()
            }
            appState.stopFollowingRoom()
        }
        appState.goHome()
    }
}

struct ResultsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ResultsViewModel()

    var body: some View {
        ZStack {
            SCTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    // Winner card
                    VStack(spacing: 10) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(SCTheme.gold)
                        Text("WINNER")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(appState.name(for: viewModel.winner).uppercased())
                            .font(SCTheme.title(40))
                            .foregroundStyle(.white)
                        Text("\(viewModel.score.red) — \(viewModel.score.blue)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("takes the battle")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(SCTheme.sideGradient(viewModel.winner))
                    )

                    // Round-by-round
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROUND BY ROUND")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                            .padding(.horizontal, 4)

                        ForEach(viewModel.displayRounds) { result in
                            HStack(spacing: 10) {
                                Text("R\(result.roundNumber)")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(SCTheme.secondaryText)
                                    .frame(width: 30, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.redSong.title)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(result.winner == .red ? .white : SCTheme.secondaryText)
                                    Text(result.blueSong.title)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(result.winner == .blue ? .white : SCTheme.secondaryText)
                                }
                                Spacer()
                                Circle()
                                    .fill(result.winner.color)
                                    .frame(width: 14, height: 14)
                            }
                            .padding(.vertical, 6)
                            Divider().background(SCTheme.cardBorder)
                        }
                    }
                    .scCard()

                    Button("Rematch") { viewModel.rematch() }
                        .buttonStyle(SCPrimaryButton())
                    Button("Back to Home") { viewModel.home() }
                        .buttonStyle(SCSecondaryButton())
                        .padding(.bottom, 8)
                }
                .padding(20)
            }
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    let state = MockData.previewState()
    state.finalRoundWinner = .red
    return ResultsView()
        .environment(state)
}
