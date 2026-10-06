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

    private var coinFill: some ShapeStyle {
        if let result = viewModel.result {
            return AnyShapeStyle(SCTheme.sideGradient(result))
        }
        return AnyShapeStyle(
            LinearGradient(colors: [SCTheme.gold, SCTheme.gold.opacity(0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    var body: some View {
        ZStack {
            SCTheme.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text("COIN TOSS")
                    .font(SCTheme.title(34))
                    .foregroundStyle(.white)

                Text("Winner plays first")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(SCTheme.secondaryText)

                // The coin
                ZStack {
                    Circle()
                        .fill(coinFill)
                        .frame(width: 170, height: 170)
                        .shadow(color: .black.opacity(0.5), radius: 20)
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 3)
                        .frame(width: 170, height: 170)
                    Text(coinFaceText)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .rotation3DEffect(.degrees(viewModel.rotation), axis: (x: 0, y: 1, z: 0))

                if let result = viewModel.result {
                    Text("\(appState.name(for: result)) plays first")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(result.color)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    Text(viewModel.isTossing ? "Flipping…" : "Tap to toss")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(SCTheme.secondaryText)
                }

                Spacer()

                if viewModel.result == nil {
                    Button(viewModel.isTossing ? "Flipping…" : "Toss the Coin") {
                        viewModel.toss()
                    }
                    .buttonStyle(SCPrimaryButton())
                    .disabled(viewModel.isTossing)
                } else {
                    Button(SCPreview.isActive ? "Start Round 5" : "Start Battle") { viewModel.cont() }
                        .buttonStyle(SCPrimaryButton())
                }
            }
            .padding(28)
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var coinFaceText: String {
        if let result = viewModel.result {
            return result == .red ? "RED" : "BLUE"
        }
        return viewModel.isTossing ? "" : "?"
    }
}

#Preview {
    CoinTossView()
        .environment(MockData.previewState())
}
