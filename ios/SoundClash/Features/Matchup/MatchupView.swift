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
        // Keep a local copy of every locked pick — solo/phantom opponents
        // never get a participant row, but the battle still needs their artist.
        if let artist = artist(for: side) {
            appState.matchupArtists[side] = artist
        }
        // Real mode: lock my artist pick on my participant row — but ONLY when
        // locking my own side. (Prototype simplification: the matchup screen
        // is driven from one device, like the mock; sides map to competitor
        // participants at the coin toss. In solo testing one device locks
        // both sides, and writing the opponent's artist to my row would
        // corrupt my own pick.)
        guard !SCPreview.isActive,
              side == appState.mySide,
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
            VerzuzSplit(left: VerzuzTheme.clashA.color, right: VerzuzTheme.clashB.color)

            // V watermark behind the content.
            VMark(left: .black.opacity(0.85), right: .white.opacity(0.9))
                .frame(width: 300, height: 300)
                .opacity(0.35)

            ScrollView {
                VStack(spacing: 16) {
                    VerzuzPill(text: "PICK YOUR ARTIST", fontSize: 22)
                        .padding(.top, 8)

                    Text("Tap a corner, then tap an artist. Lock in when both sides are set.")
                        .font(VerzuzTheme.display(14))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(radius: 2)

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
                            .font(VerzuzTheme.display(20))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Circle().fill(.black))
                    }

                    // Artist search + grid
                    VStack(spacing: 10) {
                        TextField("Search artists", text: $viewModel.searchText)
                            .padding(12)
                            .background(.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(viewModel.filteredArtists, id: \.self) { artist in
                                Button { viewModel.tapArtist(artist) } label: {
                                    Text(artist)
                                        .font(VerzuzTheme.display(15))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(.black.opacity(0.85))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }

                    Button("SURPRISE ME") { viewModel.surpriseMe() }
                        .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 20))

                    Button("CONTINUE TO COIN TOSS") { viewModel.cont() }
                        .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 20))
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

    private var clash: Color { VerzuzTheme.clashColor(for: side) }

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onSelect) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(clash)
                            .frame(width: 84, height: 84)
                        Text(initials)
                            .font(VerzuzTheme.display(30))
                            .foregroundStyle(.black)
                    }
                    Text(name)
                        .font(VerzuzTheme.display(16))
                        .foregroundStyle(.white)
                    Text(artist ?? "Tap artists below")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(artist == nil ? .white.opacity(0.7) : .white)
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
                    Text(isLocked ? "LOCKED" : "LOCK IN")
                        .font(VerzuzTheme.display(14))
                }
                .foregroundStyle(isLocked ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isLocked ? clash : .black.opacity(0.85))
                )
            }
            .disabled(isLocked || artist == nil)
        }
        .padding(14)
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isAssigning ? clash : .white.opacity(0.25), lineWidth: isAssigning ? 3 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isAssigning)
    }
}

#Preview {
    MatchupView()
        .environment(MockData.previewState())
}
