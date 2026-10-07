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

    var artistResults: [ArtistHit] = []
    var isSearching = false
    private var searchTask: Task<Void, Never>?

    /// Artwork for the currently picked artists (Apple Music, when available).
    var artwork: [Side: URL?] = [.red: nil, .blue: nil]

    /// Debounced live artist search — no presets, just the catalog.
    func searchChanged(_ text: String) {
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            artistResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let names = try await MusicMode.provider.searchArtists(query: q)
                guard !Task.isCancelled else { return }
                artistResults = names
            } catch {
                artistResults = []
            }
            isSearching = false
        }
    }

    func artist(for side: Side) -> String? {
        side == .red ? redArtist : blueArtist
    }

    func isLocked(_ side: Side) -> Bool {
        side == .red ? redLocked : blueLocked
    }

    func tapArtist(_ hit: ArtistHit) {
        if assigningSide == .red {
            guard !redLocked else { return }
            redArtist = hit.name
            artwork[.red] = hit.artworkURL
        } else {
            guard !blueLocked else { return }
            blueArtist = hit.name
            artwork[.blue] = hit.artworkURL
        }
        // Auto-advance to the other corner so both picks take two taps.
        assigningSide = assigningSide.opponent
    }

    /// Swap the two sides' artists (and their artwork). Blocked once either
    /// side locks — the swap is for the "wrong side" oops before lock-in.
    /// (Previously the swap ignored locks, so the banner could change after
    /// locking while the code kept the locked pick.)
    var canSwap: Bool { !redLocked && !blueLocked }

    func swapSides() {
        guard canSwap else { return }
        (redArtist, blueArtist) = (blueArtist, redArtist)
        (artwork[.red], artwork[.blue]) = (artwork[.blue], artwork[.red])
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
            // Full-bleed Color Clash split — the halves ARE the cards.
            VerzuzSplit(left: VerzuzTheme.clashA.color, right: VerzuzTheme.clashB.color)

            VStack(spacing: 0) {
                VerzuzPill(text: "PICK YOUR ARTIST", fontSize: 20)
                    .padding(.top, 12)

                // Fighters — left vs right, big proportions.
                HStack(spacing: 0) {
                    fighterHalf(side: .red)
                    fighterHalf(side: .blue)
                }
                .overlay(alignment: .center) {
                    VStack(spacing: 8) {
                        Text("VS")
                            .font(VerzuzTheme.display(20))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Circle().fill(.black))
                        Button { viewModel.swapSides() } label: {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(Circle().fill(.black))
                                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                        }
                        .disabled(!viewModel.canSwap)
                        .opacity(viewModel.canSwap ? 1 : 0.25)
                        .accessibilityLabel("Swap sides")
                    }
                }

                // Search — compact, Apple Music style rows, black container so
                // results never push the continue button.
                VStack(spacing: 8) {
                    TextField("Search artists", text: $viewModel.searchText)
                        .padding(12)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .onChange(of: viewModel.searchText) { _, new in
                            viewModel.searchChanged(new)
                        }

                    if viewModel.isSearching || !viewModel.artistResults.isEmpty || !viewModel.searchText.isEmpty {
                        ScrollView {
                            if viewModel.isSearching {
                                ProgressView().tint(.white).padding(.vertical, 8)
                            } else if viewModel.artistResults.isEmpty {
                                Text("No artists found — try another search.")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .padding(.vertical, 8)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(viewModel.artistResults) { hit in
                                        Button { viewModel.tapArtist(hit) } label: {
                                            HStack(spacing: 12) {
                                                artistThumb(url: hit.artworkURL, name: hit.name, size: 52)
                                                Text(hit.name)
                                                    .font(.system(size: 17, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.vertical, 8)
                                            .contentShape(Rectangle())
                                        }
                                        Divider().background(Color.white.opacity(0.12))
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 230)
                    }
                }
                .padding(12)
                .background(.black)

                Button("CONTINUE TO COIN TOSS") { viewModel.cont() }
                    .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 20))
                    .disabled(!viewModel.canContinue)
                    .opacity(viewModel.canContinue ? 1 : 0.4)
                    .padding(16)
                    .background(.black)
            }
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Fighter half (Heavyweight)

    @ViewBuilder
    private func fighterHalf(side: Side) -> some View {
        let artist = viewModel.artist(for: side)
        let artworkURL = viewModel.artwork[side] ?? nil
        let isLocked = viewModel.isLocked(side)
        let isAssigning = viewModel.assigningSide == side

        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Button { viewModel.assigningSide = side } label: {
                VStack(spacing: 12) {
                    Text(appState.name(for: side).uppercased())
                        .font(VerzuzTheme.display(15))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                    ZStack {
                        if let artworkURL {
                            AsyncImage(url: artworkURL) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: Circle().fill(.black.opacity(0.3))
                                }
                            }
                            .frame(width: 140, height: 140)
                            .clipShape(Circle())
                        } else {
                            ZStack {
                                Circle().fill(.black.opacity(0.3)).frame(width: 140, height: 140)
                                Text(artist.map { String($0.prefix(1)).uppercased() } ?? "?")
                                    .font(VerzuzTheme.display(52))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .overlay(
                        Circle()
                            .stroke(.white, lineWidth: isAssigning ? 5 : 0)
                    )
                    .shadow(radius: 8)

                    Text(artist ?? "TAP TO PICK")
                        .font(VerzuzTheme.display(30))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }

            Spacer(minLength: 12)

            Button { viewModel.lock(side) } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 14, weight: .bold))
                    Text(isLocked ? "LOCKED" : "LOCK IN")
                        .font(VerzuzTheme.display(16))
                }
                .foregroundStyle(isLocked ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isLocked ? .white : .black)
            }
            .disabled(isLocked || artist == nil)
            .opacity((isLocked || artist == nil) ? 0.85 : 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    func artistThumb(url: URL?, name: String, size: CGFloat) -> some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Color.white.opacity(0.12)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(Color.white.opacity(0.12)).frame(width: size, height: size)
                Text(String(name.prefix(1)).uppercased())
                    .font(VerzuzTheme.display(size * 0.4))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

#Preview {
    MatchupView()
        .environment(MockData.previewState())
}
