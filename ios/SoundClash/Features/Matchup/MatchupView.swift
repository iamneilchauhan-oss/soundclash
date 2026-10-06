import SwiftUI

@Observable
@MainActor
final class MatchupViewModel {
    var appState: AppState!
    var searchText = ""
    var assigningSide: Side = .red
    var redArtist: String? = MockData.redCompetitor.artistPick
    var blueArtist: String? = MockData.blueCompetitor.artistPick
    var redLocked = false
    var blueLocked = false

    func configure(_ state: AppState) { appState = state }

    var filteredArtists: [String] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return MockData.presetArtists }
        return MockData.presetArtists.filter { $0.lowercased().contains(q) }
    }

    func artist(for side: Side) -> String? {
        side == .red ? redArtist : blueArtist
    }

    func isLocked(_ side: Side) -> Bool {
        side == .red ? redLocked : blueLocked
    }

    func tapArtist(_ name: String) {
        if assigningSide == .red {
            guard !redLocked else { return }
            redArtist = name
        } else {
            guard !blueLocked else { return }
            blueArtist = name
        }
        // Auto-advance to the other corner so both picks take two taps.
        assigningSide = assigningSide.opponent
    }

    func lock(_ side: Side) {
        guard artist(for: side) != nil else { return }
        if side == .red { redLocked = true } else { blueLocked = true }
        // Real mode: lock my artist pick on my participant row. (Prototype
        // simplification: the matchup screen is driven from one device, like the
        // mock; sides map to competitor participants at the coin toss.)
        guard !SCPreview.isActive,
              let id = appState.myParticipantId,
              let artist = artist(for: side) else { return }
        Task {
            do {
                try await SupabaseService.shared.setArtistPick(participantId: id, artist: artist)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    func surpriseMe() {
        var pool = MockData.presetArtists.shuffled()
        redArtist = pool.removeFirst()
        blueArtist = pool.removeFirst()
        // Leave unlocked so players can still change their minds.
    }

    var canContinue: Bool {
        redLocked && blueLocked && redArtist != nil && blueArtist != nil
    }

    func cont() {
        guard !SCPreview.isActive, let roomId = appState.roomId else {
            appState.go(.coinToss)
            return
        }
        // Real mode: the room status drives every device (AppState.syncFromRoom).
        Task {
            do {
                try await SupabaseService.shared.advanceRoomStatus(roomId: roomId, status: .coinToss)
                appState.go(.coinToss)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }
}

struct MatchupView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = MatchupViewModel()

    var body: some View {
        ZStack {
            SCTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Text("PICK YOUR ARTIST")
                        .font(SCTheme.title(30))
                        .foregroundStyle(.white)
                        .padding(.top, 8)

                    Text("Tap a corner, then tap an artist. Lock in when both sides are set.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(SCTheme.secondaryText)
                        .multilineTextAlignment(.center)

                    // Head-to-head cards
                    HStack(spacing: 12) {
                        FighterCard(
                            side: .red,
                            name: appState.name(for: .red),
                            artist: viewModel.redArtist,
                            isAssigning: viewModel.assigningSide == .red,
                            isLocked: viewModel.redLocked,
                            onSelect: { viewModel.assigningSide = .red },
                            onLock: { viewModel.lock(.red) }
                        )
                        FighterCard(
                            side: .blue,
                            name: appState.name(for: .blue),
                            artist: viewModel.blueArtist,
                            isAssigning: viewModel.assigningSide == .blue,
                            isLocked: viewModel.blueLocked,
                            onSelect: { viewModel.assigningSide = .blue },
                            onLock: { viewModel.lock(.blue) }
                        )
                    }
                    .overlay(alignment: .center) {
                        Text("VS")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Circle().fill(SCTheme.card).overlay(Circle().stroke(SCTheme.cardBorder)))
                    }

                    // Artist search + grid
                    VStack(spacing: 10) {
                        TextField("Search artists", text: $viewModel.searchText)
                            .padding(12)
                            .background(SCTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(viewModel.filteredArtists, id: \.self) { artist in
                                Button { viewModel.tapArtist(artist) } label: {
                                    Text(artist)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(SCTheme.card)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }

                    Button("Surprise Me") { viewModel.surpriseMe() }
                        .buttonStyle(SCSecondaryButton())

                    Button("Continue to Coin Toss") { viewModel.cont() }
                        .buttonStyle(SCPrimaryButton())
                        .disabled(!viewModel.canContinue)
                        .opacity(viewModel.canContinue ? 1 : 0.4)
                        .padding(.bottom, 8)
                }
                .padding(20)
            }
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct FighterCard: View {
    let side: Side
    let name: String
    let artist: String?
    let isAssigning: Bool
    let isLocked: Bool
    let onSelect: () -> Void
    let onLock: () -> Void

    private var initials: String {
        guard let artist else { return "?" }
        let parts = artist.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined()
    }

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onSelect) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(SCTheme.sideGradient(side))
                            .frame(width: 84, height: 84)
                        Text(initials)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text(name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(artist ?? "Tap artists below")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(artist == nil ? SCTheme.secondaryText : .white)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 36)
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                onLock()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                    Text(isLocked ? "Locked" : "Lock In")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isLocked ? .white : side.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isLocked ? side.color.opacity(0.9) : side.color.opacity(0.15))
                )
            }
            .disabled(isLocked || artist == nil)
        }
        .padding(14)
        .background(SCTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isAssigning ? side.color : SCTheme.cardBorder, lineWidth: isAssigning ? 3 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isAssigning)
    }
}

#Preview {
    MatchupView()
        .environment(MockData.previewState())
}
