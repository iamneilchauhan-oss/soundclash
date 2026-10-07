import SwiftUI

// MARK: - Cheat sheet data

/// One entry in the player's private battle plan: a song plus freeform
/// rebuttal notes. Lives only on this phone — the opponent never sees it.
struct CheatEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var artworkURL: URL?
    var notes: String = ""
    var kind: Kind

    enum Kind: String, Codable, CaseIterable {
        case arsenal   // songs I plan to play
        case threat    // opponent songs I need counters for
    }
}

@Observable
@MainActor
final class CheatSheetViewModel {
    var entries: [CheatEntry] = []
    var showAdd = false
    var addKind: CheatEntry.Kind = .arsenal
    var expandedId: UUID?

    private let storeKey = "soundclash.cheatsheet"

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([CheatEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    func entries(for kind: CheatEntry.Kind) -> [CheatEntry] {
        entries.filter { $0.kind == kind }
    }

    func add(_ entry: CheatEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func delete(_ entry: CheatEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func updateNotes(_ entry: CheatEntry, notes: String) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].notes = notes
        save()
    }
}

// MARK: - Cheat sheet view

struct CheatSheetView: View {
    @State private var viewModel = CheatSheetViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("CHEAT SHEET")
                            .font(VerzuzTheme.display(34))
                            .foregroundStyle(.white)
                        Text("Your private battle plan. Lives only on this phone.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 8)

                    cheatSection(
                        kind: .arsenal,
                        title: "MY ARSENAL",
                        color: VerzuzTheme.clashA.color,
                        empty: "Songs you plan to play. Add rebuttal notes for each."
                    )
                    cheatSection(
                        kind: .threat,
                        title: "THEIR THREATS",
                        color: VerzuzTheme.clashB.color,
                        empty: "Songs you expect from the other side — and your counters."
                    )
                }
                .padding(20)
            }
        }
        .task { viewModel.load() }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $viewModel.showAdd) {
            AddCheatEntryView(kind: viewModel.addKind) { viewModel.add($0) }
        }
    }

    private func cheatSection(kind: CheatEntry.Kind, title: String, color: Color, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(VerzuzTheme.display(20))
                    .foregroundStyle(color)
                Spacer()
                Button {
                    viewModel.addKind = kind
                    viewModel.showAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 4)

            let list = viewModel.entries(for: kind)
            if list.isEmpty {
                Text(empty)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 4)
            }
            ForEach(list) { entry in
                CheatRow(
                    entry: entry,
                    expanded: viewModel.expandedId == entry.id,
                    onTap: {
                        viewModel.expandedId = viewModel.expandedId == entry.id ? nil : entry.id
                    },
                    onNotes: { viewModel.updateNotes(entry, notes: $0) },
                    onDelete: { viewModel.delete(entry) }
                )
            }
        }
    }
}

// MARK: - Cheat row (expandable notes)

struct CheatRow: View {
    let entry: CheatEntry
    let expanded: Bool
    let onTap: () -> Void
    let onNotes: (String) -> Void
    let onDelete: () -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    cheatArtwork
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(VerzuzTheme.display(15))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(entry.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer()
                    if !entry.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(10)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("REBUTTAL NOTES")
                        .font(VerzuzTheme.display(11))
                        .foregroundStyle(.white.opacity(0.5))
                    TextEditor(text: $draft)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onChange(of: draft) { _, new in onNotes(new) }
                    Button("Delete entry", role: .destructive) { onDelete() }
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(10)
                .onAppear { draft = entry.notes }
            }
        }
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var cheatArtwork: some View {
        if let url = entry.artworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Color.white.opacity(0.12)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(String(entry.title.prefix(1)).uppercased())
                    .font(VerzuzTheme.display(18))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Add entry (Apple Music search + manual)

struct AddCheatEntryView: View {
    let kind: CheatEntry.Kind
    let onAdd: (CheatEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SCTrack] = []
    @State private var isSearching = false
    @State private var manualTitle = ""
    @State private var manualArtist = ""
    private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    TextField("Search songs", text: $query)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                        .onChange(of: query) { _, new in searchChanged(new) }

                    if isSearching {
                        ProgressView().tint(.white)
                    }

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { track in
                                Button {
                                    onAdd(CheatEntry(
                                        title: track.title, artist: track.artist,
                                        artworkURL: track.artworkURL, kind: kind
                                    ))
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(track.title)
                                            .font(VerzuzTheme.display(14))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(track.artist)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.6))
                                            .lineLimit(1)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }

                    VStack(spacing: 8) {
                        Text("OR ADD MANUALLY")
                            .font(VerzuzTheme.display(11))
                            .foregroundStyle(.white.opacity(0.5))
                        TextField("Song title", text: $manualTitle)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                        TextField("Artist", text: $manualArtist)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                        Button("ADD") {
                            onAdd(CheatEntry(title: manualTitle, artist: manualArtist, kind: kind))
                            dismiss()
                        }
                        .buttonStyle(VerzuzButtonStyle(
                            fill: kind == .arsenal ? VerzuzTheme.clashA.color : VerzuzTheme.clashB.color,
                            textColor: .black, fontSize: 16
                        ))
                        .disabled(manualTitle.isEmpty)
                        .opacity(manualTitle.isEmpty ? 0.4 : 1)
                    }
                }
                .padding(20)
            }
            .navigationTitle(kind == .arsenal ? "Add to arsenal" : "Add threat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func searchChanged(_ text: String) {
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; isSearching = false; return }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let hits = (try? await MusicMode.provider.searchCatalog(query: q, artist: nil)) ?? []
            guard !Task.isCancelled else { return }
            results = Array(hits.prefix(20))
            isSearching = false
        }
    }
}

#Preview {
    CheatSheetView()
}
