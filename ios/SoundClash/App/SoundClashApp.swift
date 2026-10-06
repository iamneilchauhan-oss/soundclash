import SwiftUI

@main
struct SoundClashApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $appState.path) {
                MenuView()
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .menu:
                            MenuView()
                        case .joinHost:
                            JoinHostView()
                        case .lobby:
                            LobbyView()
                        case .matchup:
                            MatchupView()
                        case .coinToss:
                            CoinTossView()
                        case .battle(let round):
                            BattleView(round: round)
                        case .voting(let round):
                            VotingView(round: round)
                        case .results:
                            ResultsView()
                        }
                    }
            }
            .environment(appState)
            .preferredColorScheme(.dark)
        }
    }
}
