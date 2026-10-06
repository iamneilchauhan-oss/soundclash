import SwiftUI

@Observable
@MainActor
final class VotingViewModel {
    var appState: AppState!
    let round: Int
    var myVote: Side?
    var judgeVotes: [(name: String, side: Side)] = []

    init(round: Int) { self.round = round }

    func configure(_ state: AppState) {
        appState = state
        guard !SCPreview.isActive else { return }
        // Real mode: votes stream in via the shared room subscription.
        state.onVotesChanged = { [weak self] in
            Task { @MainActor [weak self] in await self?.refreshVotes() }
        }
        Task { await refreshVotes() }
    }

    var allVotes: [(name: String, side: Side)] {
        if SCPreview.isActive {
            var votes = judgeVotes
            if let myVote { votes.insert((name: "You", side: myVote), at: 0) }
            return votes
        }
        return realVotes.map { vote in
            let name: String
            if vote.judgeId == appState.myParticipantId {
                name = "You"
            } else {
                name = appState.participants.first(where: { $0.id == vote.judgeId })?.username ?? "Judge"
            }
            let side: Side = vote.votedForId == appState.blueCompetitorId ? .blue : .red
            return (name: name, side: side)
        }
    }

    /// Real votes from Supabase. Local myVote is folded in via refreshVotes().
    private var realVotes: [Vote] = []

    var tally: (red: Int, blue: Int) {
        (
            red: allVotes.filter { $0.side == .red }.count,
            blue: allVotes.filter { $0.side == .blue }.count
        )
    }

    var winner: Side? {
        let t = tally
        guard t.red + t.blue > 0 else { return nil }
        return t.red >= t.blue ? .red : .blue
    }

    func vote(_ side: Side) {
        guard myVote == nil else { return }
        myVote = side
        if SCPreview.isActive {
            simulateFellowJudges()
            return
        }
        guard let roundId = appState.currentRoundId,
              let judgeId = appState.myParticipantId else { return }
        // Real mode: upsert my vote; the realtime echo refreshes the tally.
        let votedForId: UUID? = side == .red ? appState.redCompetitorId : appState.blueCompetitorId
        guard let votedForId else { return }
        Task {
            do {
                _ = try await SupabaseService.shared.castVote(
                    roundId: roundId, judgeId: judgeId, votedForId: votedForId
                )
                await refreshVotes()
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    /// Real mode: refresh participants (for judge names) + the vote tally.
    private func refreshVotes() async {
        guard !SCPreview.isActive,
              let roundId = appState.currentRoundId else { return }
        do {
            if let roomId = appState.roomId {
                appState.participants = try await SupabaseService.shared.fetchParticipants(roomId: roomId)
            }
            realVotes = try await SupabaseService.shared.fetchVotes(roundId: roundId)
        } catch {
            appState.backendError = error.localizedDescription
        }
    }

    /// Mock: the other two judges deliberate, then their votes land.
    private func simulateFellowJudges() {
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            judgeVotes.append((name: "Kai", side: .red))
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            judgeVotes.append((name: "Jules", side: .blue))
        }
    }

    var canLock: Bool { myVote != nil }

    func lockIn() {
        if SCPreview.isActive {
            appState.finalRoundWinner = winner ?? .red
            appState.go(.results)
            return
        }
        guard let roundId = appState.currentRoundId,
              let roomId = appState.roomId,
              let winner else { return }
        // Real mode: finish the round with the real winner, then close the room.
        // (v1 runs a single decisive round; multi-round progression comes later.)
        let winnerId = winner == .red ? appState.redCompetitorId : appState.blueCompetitorId
        Task {
            do {
                try await SupabaseService.shared.finishRound(roundId: roundId, winnerId: winnerId)
                try await SupabaseService.shared.advanceRoomStatus(roomId: roomId, status: .finished)
                appState.finalRoundWinner = winner
                appState.go(.results)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    func stop() {
        if !SCPreview.isActive { appState?.onVotesChanged = nil }
    }
}

struct VotingView: View {
    let round: Int
    @Environment(AppState.self) private var appState
    @State private var viewModel: VotingViewModel
    @State private var pulsing = false

    init(round: Int) {
        self.round = round
        _viewModel = State(initialValue: VotingViewModel(round: round))
    }

    var body: some View {
        ZStack {
            SCTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text("ROUND \(round)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                        Text("JUDGES VOTE")
                            .font(SCTheme.title(34))
                            .foregroundStyle(.white)
                    }

                    // Deliberation banner
                    HStack(spacing: 10) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(SCTheme.gold)
                            .opacity(pulsing ? 0.45 : 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Judges deliberating")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Live talk open — make your case")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(SCTheme.secondaryText)
                        }
                        Spacer()
                    }
                    .scCard()
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever()) {
                            pulsing = true
                        }
                    }

                    // Red vs blue vote buttons
                    HStack(spacing: 12) {
                        voteButton(for: .red)
                        voteButton(for: .blue)
                    }

                    // Tally
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TALLY  ·  RED \(viewModel.tally.red) — \(viewModel.tally.blue) BLUE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                        if viewModel.allVotes.isEmpty {
                            Text("Waiting for the first vote…")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(SCTheme.secondaryText.opacity(0.7))
                        }
                        ForEach(viewModel.allVotes, id: \.name) { vote in
                            HStack(spacing: 10) {
                                Circle().fill(vote.side.color).frame(width: 12, height: 12)
                                Text(vote.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("voted \(vote.side == .red ? "Red" : "Blue")")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(SCTheme.secondaryText)
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .scCard()
                    .animation(.easeInOut, value: viewModel.allVotes.count)

                    Button("Lock In & See Results") { viewModel.lockIn() }
                        .buttonStyle(SCPrimaryButton())
                        .disabled(!viewModel.canLock)
                        .opacity(viewModel.canLock ? 1 : 0.4)
                        .padding(.bottom, 8)
                }
                .padding(20)
            }
        }
        .task { viewModel.configure(appState) }
        .onDisappear { viewModel.stop() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func voteButton(for side: Side) -> some View {
        Button {
            viewModel.vote(side)
        } label: {
            VStack(spacing: 8) {
                Text(appState.name(for: side))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(side.label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                if viewModel.myVote == side {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(SCSideButton(side: side, isSelected: viewModel.myVote == side))
        .disabled(viewModel.myVote != nil)
    }
}

#Preview {
    VotingView(round: 5)
        .environment(MockData.previewState())
}
