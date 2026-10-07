import SwiftUI

// MARK: - Track picker (3 tabs: search / albums / cheat sheet)

/// Song picker for battle rounds. Apple Music-styled results with explicit
/// badges, album drill-in, and cheat-sheet arsenal. The picker's selection is
/// independent of turn — the Play button is gated by the caller.
struct TrackPickerView: View {
    @Binding var selectedTrack: SCTrack?
    let battleArtist: String
    let canPlay: Bool
    let onPlay: () -> Void
    let onPreview: (SCTrack) -> Void
    var previewingTrackId: String?

    @State private var tab: PickerTab = .search
    @State private var searchText = ""
    @State private var broadSearch = false
    @State private var results: [SCTrack] = []
    @State private var isSearching = false
    @State private var albums: [SCAlbum] = []
    @State private var selectedAlbum: SCAlbum?
    @State private var albumSongs: [SCTrack] = []
    @State private var isLoadingAlbums = false
    @State private var cheatEntries: [CheatEntry] = []

    @State private var searchTask: Task<Void, Never>?

    enum PickerTab: String, CaseIterable {
        case search = "SONG SEARCH"
        case albums = "ALBUMS"
        case cheats = "CHEAT SHEET"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("PICK YOUR TRACK")
                .font(VerzuzTheme.display(18))
                .foregroundStyle(.white)

            Picker("Pick", selection: $tab) {
                ForEach(PickerTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: tab) { _, new in
                if new == .albums && albums.isEmpty { loadAlbums() }
                if new == .cheats && cheatEntries.isEmpty { loadCheats() }
            }

            switch tab {
            case .search: searchTab
            case .albums: albumsTab
            case .cheats: cheatsTab
            }

            Button(canPlay ? "PLAY THIS TRACK" : "QUEUED — WAITING FOR YOUR TURN") {
                onPlay()
            }
            .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 18))
            .disabled(selectedTrack == nil || !canPlay)
            .opacity(selectedTrack == nil || !canPlay ? 0.4 : 1)
        }
        .padding(16)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task { loadCheats() }
    }

    // MARK: - Song search tab

    private var searchTab: some View {
        VStack(spacing: 10) {
            TextField("Search songs", text: $searchText)
                .padding(12)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .onChange(of: searchText) { _, new in searchChanged(new) }

            // Broader scope toggle: include features / writing credits.
            Toggle(isOn: $broadSearch) {
                Text("Include features & writing credits")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .tint(VerzuzTheme.clashA.color)
            .onChange(of: broadSearch) { _, _ in searchChanged(searchText) }

            if isSearching {
                ProgressView().tint(.white).padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results) { track in
                        trackRow(track)
                        Divider().background(Color.white.opacity(0.08))
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    // MARK: - Albums tab

    private var albumsTab: some View {
        VStack(spacing: 10) {
            if let album = selectedAlbum {
                // Drill-in: songs on the album.
                HStack {
                    Button {
                        selectedAlbum = nil
                        albumSongs = []
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(album.title.uppercased())
                        .font(VerzuzTheme.display(16))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                }
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(albumSongs) { track in
                            trackRow(track)
                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
                .frame(maxHeight: 280)
            } else {
                if isLoadingAlbums {
                    ProgressView().tint(.white).padding(.vertical, 12)
                }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 12) {
                        ForEach(albums) { album in
                            Button {
                                selectedAlbum = album
                                loadAlbumSongs(album)
                            } label: {
                                VStack(spacing: 6) {
                                    albumArt(url: album.artworkURL, size: 120)
                                    Text(album.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                    Text("\(album.trackCount) tracks")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .task { if albums.isEmpty { loadAlbums() } }
    }

    // MARK: - Cheat sheet tab

    private var cheatsTab: some View {
        VStack(spacing: 10) {
            if cheatEntries.isEmpty {
                Text("Your arsenal is empty — add songs in Cheat Sheets.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.vertical, 12)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(cheatEntries) { entry in
                        Button {
                            // Cheat entries map to a lightweight track for selection.
                            // Full catalog lookup happens on play via title/artist.
                            Task {
                                let hits = (try? await MusicMode.provider.searchCatalog(
                                    query: entry.title, artist: entry.artist, broad: true
                                )) ?? []
                                if let hit = hits.first {
                                    selectedTrack = hit
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                cheatArt(url: entry.artworkURL, title: entry.title)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(entry.artist)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                                Spacer()
                                if !entry.notes.isEmpty {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        Divider().background(Color.white.opacity(0.08))
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    // MARK: - Track row (Apple Music style)

    private func trackRow(_ track: SCTrack) -> some View {
        Button {
            selectedTrack = (selectedTrack?.id == track.id) ? nil : track
        } label: {
            HStack(spacing: 12) {
                // Artwork
                ZStack {
                    if let url = track.artworkURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Color.white.opacity(0.1)
                            }
                        }
                    } else {
                        Color.white.opacity(0.1)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Title + explicit badge + details
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if track.isExplicit {
                            Text("E")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.85))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    Text(track.detailLine.isEmpty ? track.artist : "\(track.artist)  ·  \(track.detailLine)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Preview button
                Button {
                    onPreview(track)
                } label: {
                    Image(systemName: previewingTrackId == track.id ? "pause.fill" : "play.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)

                // Selection check
                if selectedTrack?.id == track.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(VerzuzTheme.clashA.color)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedTrack?.id == track.id
                          ? Color.white.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func albumArt(url: URL?, size: CGFloat) -> some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.white.opacity(0.1)
                    }
                }
            } else {
                Color.white.opacity(0.1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func cheatArt(url: URL?, title: String) -> some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.white.opacity(0.1)
                    }
                }
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Text(String(title.prefix(1)).uppercased())
                        .font(VerzuzTheme.display(18))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Data

    private func searchChanged(_ text: String) {
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; isSearching = false; return }
        isSearching = true
        let broad = broadSearch
        let artist = battleArtist
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let hits = (try? await MusicMode.provider.searchCatalog(
                query: q, artist: artist, broad: broad
            )) ?? []
            guard !Task.isCancelled else { return }
            results = hits
            isSearching = false
        }
    }

    private func loadAlbums() {
        isLoadingAlbums = true
        Task {
            let list = (try? await MusicMode.provider.searchAlbums(artist: battleArtist)) ?? []
            albums = list
            isLoadingAlbums = false
        }
    }

    private func loadAlbumSongs(_ album: SCAlbum) {
        Task {
            albumSongs = (try? await MusicMode.provider.albumTracks(album)) ?? []
        }
    }

    private func loadCheats() {
        guard let data = UserDefaults.standard.data(forKey: "soundclash.cheatsheet"),
              let decoded = try? JSONDecoder().decode([CheatEntry].self, from: data)
        else { return }
        cheatEntries = decoded.filter { $0.kind == .arsenal }
    }
}
