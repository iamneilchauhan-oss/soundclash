import SwiftUI

@Observable
@MainActor
final class MatchupViewModel {
    var appState: AppState!
    var searchText = ""
    var assigningSide: Side = .red

    // MARK: - My pick (local, pre-lock)

    var myPick: String?
    var myPickArtwork: URL?
    var myLocked = false

    // MARK: - Solo fallback (preview or single competitor): I drive both sides

    var redArtist: String?
    var blueArtist: String?
    var redLocked = false
    var blueLocked = false
    var artwork: [Side: URL?] = [.red: nil, .blue: nil]

    var artistResults: [ArtistHit] = []
    var isSearching = false
    private var searchTask: Task<Void, Never>?
    private var proceedTask: Task<Void, Never>?

    func configure(_ state: AppState) {
        appState = state
        guard !SCPreview.isActive else {
            redArtist = MockData.redCompetitor.artistPick
            blueArtist = MockData.blueCompetitor.artistPick
            return
        }
        // Sides were decided in the lobby (first player in the column = red).
        // Recompute here as a fallback for devices that didn't tap START.
        if state.redCompetitorId == nil { state.assignSidesFromLobby() }
        assigningSide = state.mySide
    }

    // MARK: - Sides & opponents

    /// Solo when I'm the only competitor (or preview) — I drive both sides.
    var isSolo: Bool {
        if SCPreview.isActive { return true }
        let count = (appState?.participants ?? []).count(where: { $0.role == .competitor })
        return count < 2
    }

    var mySide: Side { appState?.mySide ?? .red }

    private var opponentId: UUID? {
        guard let appState else { return nil }
        return mySide == .red ? appState.blueCompetitorId : appState.redCompetitorId
    }

    private var opponent: Participant? {
        guard let id = opponentId else { return nil }
        return appState?.participants.first(where: { $0.id == id })
    }

    /// The opponent's pick, synced live via their participant row.
    var opponentArtist: String? { opponent?.artistPick }
    var opponentLocked: Bool { opponent?.artistLocked == true }

    /// I can only touch my own side — unless solo, where I drive both.
    func canPick(_ side: Side) -> Bool {
        isSolo || side == mySide
    }

    // MARK: - Display

    func artist(for side: Side) -> String? {
        if isSolo { return side == .red ? redArtist : blueArtist }
        if side == mySide { return myLocked ? appState?.myParticipant?.artistPick : myPick }
        return opponentArtist
    }

    func artworkURL(for side: Side) -> URL? {
        if isSolo { return artwork[side] ?? nil }
        if side == mySide { return myPickArtwork }
        return nil // opponent artwork: name-only for now (no DB column yet)
    }

    func isLocked(_ side: Side) -> Bool {
        if isSolo { return side == .red ? redLocked : blueLocked }
        if side == mySide { return myLocked }
        return opponentLocked
    }

    /// Locks secured: mine (local) + opponent's (synced).
    var lockCount: Int {
        if isSolo { return (redLocked ? 1 : 0) + (blueLocked ? 1 : 0) }
        return (myLocked ? 1 : 0) + (opponentLocked ? 1 : 0)
    }

    var lockLabel: String { "\(lockCount)/2 LOCKED IN" }

    // MARK: - Picking

    func tapArtist(_ hit: ArtistHit) {
        if isSolo {
            if assigningSide == .red {
                guard !redLocked else { return }
                redArtist = hit.name; artwork[.red] = hit.artworkURL
            } else {
                guard !blueLocked else { return }
                blueArtist = hit.name; artwork[.blue] = hit.artworkURL
            }
            assigningSide = assigningSide.opponent
            return
        }
        // Real mode: I only ever pick for my own side. Every select
        // syncs live so the opponent sees my pick as I browse.
        guard !myLocked, !SCPreview.isActive,
              let id = appState.myParticipantId else { return }
        myPick = hit.name
        myPickArtwork = hit.artworkURL
        Task {
            try? await SupabaseService.shared.setArtistPick(participantId: id, artist: hit.name)
        }
    }

    func selectSide(_ side: Side) {
        guard canPick(side) else { return }
        assigningSide = side
    }

    /// Swap the two sides' artists. Solo-only — in a real battle each player
    /// owns their side, so there's nothing to swap. Blocked once locked.
    var canSwap: Bool {
        isSolo && !redLocked && !blueLocked
    }

    func swapSides() {
        guard canSwap else { return }
        (redArtist, blueArtist) = (blueArtist, redArtist)
        (artwork[.red], artwork[.blue]) = (artwork[.blue], artwork[.red])
    }

    func lock(_ side: Side) {
        if isSolo {
            guard artist(for: side) != nil, !isLocked(side) else { return }
            if side == .red { redLocked = true } else { blueLocked = true }
            if let artist = artist(for: side) { appState.matchupArtists[side] = artist }
            checkAutoProceed()
            return
        }
        // Real mode: I lock only my side. The pick already synced live;
        // the lock is the explicit "I'm done."
        guard side == mySide, myPick != nil, !myLocked,
              !SCPreview.isActive,
              let id = appState.myParticipantId else {
            checkAutoProceed()
            return
        }
        myLocked = true
        if let pick = myPick { appState.matchupArtists[mySide] = pick }
        Task {
            do {
                try await SupabaseService.shared.setArtistLocked(participantId: id, locked: true)
            } catch {
                appState.backendError = error.localizedDescription
            }
            checkAutoProceed()
        }
    }

    /// When both locks land, hold a beat then proceed on its own.
    func checkAutoProceed() {
        proceedTask?.cancel()
        guard lockCount == 2 else { return }
        proceedTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            cont()
        }
    }

    // MARK: - Search (unchanged)

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

    // MARK: - Continue

    var canContinue: Bool { lockCount == 2 }

    func cont() {
        guard !SCPreview.isActive, let roomId = appState.roomId else {
            appState.go(.coinToss)
            return
        }
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

                Button(viewModel.lockLabel) { viewModel.cont() }
                    .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 20))
                    .disabled(!viewModel.canContinue)
                    .opacity(viewModel.canContinue ? 1 : 0.4)
                    .padding(16)
                    .background(.black)
                    .onChange(of: viewModel.lockCount) { _, _ in
                        viewModel.checkAutoProceed()
                    }
            }
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Fighter half (Heavyweight)

    @ViewBuilder
    private func fighterHalf(side: Side) -> some View {
        let artist = viewModel.artist(for: side)
        let artworkURL = viewModel.artworkURL(for: side)
        let isLocked = viewModel.isLocked(side)
        let mine = viewModel.canPick(side)
        let isAssigning = mine && viewModel.assigningSide == side
        // Empty-state copy: my side invites a pick, theirs shows waiting.
        let emptyCopy = mine ? "TAP TO PICK" : "WAITING FOR PICK"

        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Button { viewModel.selectSide(side) } label: {
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

                    Text(artist ?? emptyCopy)
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
            .disabled(!mine || isLocked || artist == nil)
            .opacity(mine ? ((isLocked || artist == nil) ? 0.85 : 1) : 0.45)
        }
        .frame(maxWidth: .infinity)
        .opacity(mine ? 1 : 0.75)
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
