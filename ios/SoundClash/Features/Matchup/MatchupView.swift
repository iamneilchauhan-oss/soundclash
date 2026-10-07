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

    /// Swap the two sides' artists (and their artwork). Locks stay as they
    /// are — this is for the "wrong side" oops, not a re-pick.
    func swapSides() {
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
            VerzuzSplit(left: VerzuzTheme.clashA.color, right: VerzuzTheme.clashB.color)

            // V watermark behind the content.
            VMark(left: .black.opacity(0.85), right: .white.opacity(0.9))
                .frame(width: 300, height: 300)
                .opacity(0.35)

            VStack(spacing: 0) {
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
                                artworkURL: viewModel.artwork[.red] ?? nil,
                                isAssigning: viewModel.assigningSide == .red,
                                isLocked: viewModel.redLocked,
                                onSelect: { viewModel.assigningSide = .red },
                                onLock: { viewModel.lock(.red) }
                            )
                            FighterCard(
                                side: .blue,
                                name: appState.name(for: .blue),
                                artist: viewModel.blueArtist,
                                artworkURL: viewModel.artwork[.blue] ?? nil,
                                isAssigning: viewModel.assigningSide == .blue,
                                isLocked: viewModel.blueLocked,
                                onSelect: { viewModel.assigningSide = .blue },
                                onLock: { viewModel.lock(.blue) }
                            )
                        }
                        .overlay(alignment: .center) {
                            VStack(spacing: 6) {
                                Text("VS")
                                    .font(VerzuzTheme.display(18))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(Circle().fill(.black))
                                Button { viewModel.swapSides() } label: {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(Circle().fill(.black.opacity(0.85)))
                                        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                                }
                                .accessibilityLabel("Swap sides")
                            }
                        }

                        // Artist search — live catalog results, bounded so the
                        // continue button never gets pushed off screen.
                        VStack(spacing: 10) {
                            TextField("Search artists", text: $viewModel.searchText)
                                .padding(12)
                                .background(.black.opacity(0.85))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                                .onChange(of: viewModel.searchText) { _, new in
                                    viewModel.searchChanged(new)
                                }

                            if viewModel.isSearching || !viewModel.artistResults.isEmpty || !viewModel.searchText.isEmpty {
                                ScrollView {
                                    if viewModel.isSearching {
                                        ProgressView()
                                            .tint(.white)
                                            .padding(.vertical, 8)
                                    } else if viewModel.artistResults.isEmpty {
                                        Text("No artists found — try another search.")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.6))
                                            .padding(.vertical, 8)
                                    }
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                                        ForEach(viewModel.artistResults) { hit in
                                            Button { viewModel.tapArtist(hit) } label: {
                                                HStack(spacing: 8) {
                                                    artistThumb(url: hit.artworkURL, name: hit.name, size: 36)
                                                    Text(hit.name)
                                                        .font(VerzuzTheme.display(14))
                                                        .foregroundStyle(.white)
                                                        .lineLimit(1)
                                                    Spacer(minLength: 0)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding(8)
                                                .background(.black.opacity(0.85))
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            }
                                        }
                                    }
                                }
                                .frame(height: 240)
                            }
                        }
                    }
                    .padding(20)
                }

                Button("CONTINUE TO COIN TOSS") { viewModel.cont() }
                    .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 20))
                    .disabled(!viewModel.canContinue)
                    .opacity(viewModel.canContinue ? 1 : 0.4)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.6))
            }
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
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

struct FighterCard: View {
    let side: Side
    let name: String
    let artist: String?
    let artworkURL: URL?
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
                        if let artworkURL {
                            AsyncImage(url: artworkURL) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: Circle().fill(clash)
                                }
                            }
                            .frame(width: 84, height: 84)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(clash)
                                .frame(width: 84, height: 84)
                            Text(initials)
                                .font(VerzuzTheme.display(30))
                                .foregroundStyle(.black)
                        }
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
