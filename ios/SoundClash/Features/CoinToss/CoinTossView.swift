import SwiftUI

@Observable
@MainActor
final class CoinTossViewModel {
    var appState: AppState!
    var isTossing = false
    var rotation: Double = 0
    var result: Side?

    func configure(_ state: AppState) { appState = state }

    func toss() {
        guard !isTossing, result == nil else { return }
        isTossing = true
        let winner: Side = [.red, .blue].randomElement()!
        withAnimation(.easeInOut(duration: 2.0)) {
            rotation += 1440
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            result = winner
            appState.firstTurn = winner
            isTossing = false
            guard !SCPreview.isActive, let roomId = appState.roomId else { return }
            // Real mode: map sides to the two competitor participants (join order
            // decides corners), create round 1, and go live. Every device follows
            // via AppState.syncFromRoom.
            do {
                let participants = try await SupabaseService.shared.fetchParticipants(roomId: roomId)
                let competitors = participants.filter { $0.role == .competitor }
                if competitors.count >= 2 {
                    appState.redCompetitorId = competitors[0].id
                    appState.blueCompetitorId = competitors[1].id
                } else if let solo = competitors.first {
                    // Solo testing: seat the lone competitor in the red corner.
                    // PlaySync.side maps unknown player IDs to red, so this keeps
                    // the side mapping consistent — otherwise a solo player's own
                    // picks never count toward their side and the round can't end.
                    appState.redCompetitorId = solo.id
                }
                if let myId = appState.myParticipantId {
                    appState.mySide = (myId == appState.redCompetitorId) ? .red : .blue
                }
                let firstId = winner == .red ? appState.redCompetitorId : appState.blueCompetitorId
                let round = try await SupabaseService.shared.createRound(
                    roomId: roomId, roundNumber: 1, firstPlayerId: firstId
                )
                appState.currentRoundId = round.id
                appState.currentRoundNumber = 1
                try await SupabaseService.shared.advanceRoomStatus(roomId: roomId, status: .live)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    func cont() {
        // Mock: the live decider is round 5. Real mode: round 1 (set in toss()).
        appState.go(.battle(round: SCPreview.isActive ? 5 : appState.currentRoundNumber))
    }
}

struct CoinTossView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = CoinTossViewModel()

    var body: some View {
        ZStack {
            // Match the matchup's Color Clash language.
            VerzuzSplit(left: VerzuzTheme.clashA.color, right: VerzuzTheme.clashB.color)

            VStack(spacing: 24) {
                Spacer()

                VerzuzPill(text: "COIN TOSS", fontSize: 24)

                Text("Winner plays first")
                    .font(VerzuzTheme.display(15))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)

                // The coin — black V coin, flips to the winner's color.
                ZStack {
                    Circle()
                        .fill(coinFill)
                        .frame(width: 170, height: 170)
                        .shadow(color: .black.opacity(0.5), radius: 20)
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                        .frame(width: 170, height: 170)
                    if let result = viewModel.result {
                        Text(result == .red ? "RED" : "BLUE")
                            .font(VerzuzTheme.display(30))
                            .foregroundStyle(.white)
                    } else if !viewModel.isTossing {
                        VMark(left: .white, right: .white.opacity(0.7))
                            .frame(width: 90, height: 90)
                    }
                }
                .rotation3DEffect(.degrees(viewModel.rotation), axis: (x: 0, y: 1, z: 0))

                if let result = viewModel.result {
                    Text("\(appState.name(for: result).uppercased()) PLAYS FIRST")
                        .font(VerzuzTheme.display(24))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Text(viewModel.isTossing ? "FLIPPING…" : "TAP TO TOSS")
                        .font(VerzuzTheme.display(17))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 2)
                }

                Spacer()

                if viewModel.result == nil {
                    Button(viewModel.isTossing ? "FLIPPING…" : "TOSS THE COIN") {
                        viewModel.toss()
                    }
                    .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 20))
                    .disabled(viewModel.isTossing)
                } else {
                    Button(SCPreview.isActive ? "START ROUND 5" : "START BATTLE") { viewModel.cont() }
                        .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 20))
                }
            }
            .padding(28)
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var coinFill: Color {
        if let result = viewModel.result {
            return VerzuzTheme.clashColor(for: result)
        }
        return .black
    }
}

#Preview {
    CoinTossView()
        .environment(MockData.previewState())
}
