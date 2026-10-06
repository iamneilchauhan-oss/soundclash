import SwiftUI

// MARK: - Router

/// Every screen in the 8-card flow. NavigationStack path lives in AppState.
enum Route: Hashable {
    case menu
    case joinHost
    case lobby
    case matchup
    case coinToss
    case battle(round: Int)
    case voting(round: Int)
    case results
}

// MARK: - Battle sides

enum Side: String, Codable, CaseIterable, Hashable {
    case red
    case blue

    var color: Color { self == .red ? SCTheme.red : SCTheme.blue }
    var label: String { self == .red ? "Red Side" : "Blue Side" }

    var opponent: Side { self == .red ? .blue : .red }
}

// MARK: - Mock domain types (stand-ins until the real services land)

struct MockSong: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let isrc: String
    let appleMusicId: String
}

extension MockSong {
    /// Maps a real catalog SCTrack into the view-facing mock shape, so the
    /// battle views work unchanged in real mode.
    init(_ track: SCTrack) {
        self.init(title: track.title, artist: track.artist,
                  isrc: track.isrc, appleMusicId: track.appleMusicId)
    }
}

struct RoundResult: Identifiable, Hashable {
    let id = UUID()
    let roundNumber: Int
    let redSong: MockSong
    let blueSong: MockSong
    let winner: Side
}

// MARK: - Mock data

enum MockData {
    static let roomId = UUID()

    static let redCompetitor = Participant(
        id: UUID(), roomId: roomId, username: "Maya", role: .competitor,
        avatar: "🎤", artistPick: "Alicia Keys", isReady: true, createdAt: Date()
    )
    static let blueCompetitor = Participant(
        id: UUID(), roomId: roomId, username: "Dre", role: .competitor,
        avatar: "🎧", artistPick: "Usher", isReady: true, createdAt: Date()
    )
    static let judges: [Participant] = [
        Participant(id: UUID(), roomId: roomId, username: "Kai", role: .judge, avatar: "🎚️", artistPick: nil, isReady: true, createdAt: Date()),
        Participant(id: UUID(), roomId: roomId, username: "Jules", role: .judge, avatar: "🎙️", artistPick: nil, isReady: true, createdAt: Date()),
        Participant(id: UUID(), roomId: roomId, username: "Rae", role: .judge, avatar: "📀", artistPick: nil, isReady: true, createdAt: Date()),
    ]

    static var participants: [Participant] {
        [redCompetitor, blueCompetitor] + judges
    }

    static let redSongs: [MockSong] = [
        MockSong(title: "If I Ain't Got You", artist: "Alicia Keys", isrc: "USJI10300677", appleMusicId: "mock-am-1"),
        MockSong(title: "Fallin'", artist: "Alicia Keys", isrc: "USJI10100585", appleMusicId: "mock-am-2"),
        MockSong(title: "No One", artist: "Alicia Keys", isrc: "USJI10700174", appleMusicId: "mock-am-3"),
        MockSong(title: "Girl on Fire", artist: "Alicia Keys", isrc: "USRC11201074", appleMusicId: "mock-am-4"),
        MockSong(title: "Un-thinkable (I'm Ready)", artist: "Alicia Keys", isrc: "USJI10900730", appleMusicId: "mock-am-5"),
        MockSong(title: "Try Sleeping with a Broken Heart", artist: "Alicia Keys", isrc: "USJI10900728", appleMusicId: "mock-am-6"),
        MockSong(title: "Empire State of Mind", artist: "Jay-Z & Alicia Keys", isrc: "USRC10900826", appleMusicId: "mock-am-7"),
        MockSong(title: "Superwoman", artist: "Alicia Keys", isrc: "USJI10700172", appleMusicId: "mock-am-8"),
    ]

    static let blueSongs: [MockSong] = [
        MockSong(title: "U Remind Me", artist: "Usher", isrc: "USAR10100532", appleMusicId: "mock-am-101"),
        MockSong(title: "Yeah!", artist: "Usher ft. Lil Jon & Ludacris", isrc: "USAR10300589", appleMusicId: "mock-am-102"),
        MockSong(title: "Burn", artist: "Usher", isrc: "USAR10400888", appleMusicId: "mock-am-103"),
        MockSong(title: "Confessions Part II", artist: "Usher", isrc: "USAR10400890", appleMusicId: "mock-am-104"),
        MockSong(title: "U Got It Bad", artist: "Usher", isrc: "USAR10100533", appleMusicId: "mock-am-105"),
    ]

    /// Rounds 1–4 are "already played" in the mock; round 5 is played live.
    static let scoreboard: [RoundResult] = [
        RoundResult(roundNumber: 1, redSong: redSongs[0], blueSong: blueSongs[0], winner: .red),
        RoundResult(roundNumber: 2, redSong: redSongs[1], blueSong: blueSongs[1], winner: .blue),
        RoundResult(roundNumber: 3, redSong: redSongs[2], blueSong: blueSongs[2], winner: .red),
        RoundResult(roundNumber: 4, redSong: redSongs[3], blueSong: blueSongs[3], winner: .blue),
    ]

    static let round5Red = redSongs[5]
    static let round5Blue = blueSongs[4]

    static let presetArtists = [
        "Alicia Keys", "Usher", "Chris Brown", "Beyoncé", "John Legend",
        "Rihanna", "Drake", "Mary J. Blige", "Missy Elliott", "JAY-Z",
    ]

    /// A pre-populated AppState for Xcode Previews.
    static func previewState() -> AppState {
        let state = AppState()
        state.username = "You"
        state.myRole = .judge
        state.roomCode = "KX7Q2M"
        state.participants = participants
        state.scoreboard = scoreboard
        return state
    }
}

// MARK: - Shared session state

@Observable
@MainActor
final class AppState {
    var path: [Route] = []
    var username = ""
    var myRole: ParticipantRole = .judge
    var mySide: Side = .red
    var roomCode = ""
    var firstTurn: Side = .red
    var participants: [Participant] = MockData.participants
    var scoreboard: [RoundResult] = MockData.scoreboard
    var finalRoundWinner: Side? = nil

    // Real-backend session state (nil in previews / mock mode).
    var roomId: UUID? = nil
    var myParticipantId: UUID? = nil
    var currentRoundId: UUID? = nil
    var currentRoundNumber = 5
    var redCompetitorId: UUID? = nil
    var blueCompetitorId: UUID? = nil
    /// Local cache of the matchup screen's artist picks, keyed by side.
    /// Covers solo/phantom opponents, who have no participant row to read
    /// an artist pick from.
    var matchupArtists: [Side: String] = [:]
    /// Last backend error, for future error UI.
    var backendError: String? = nil

    /// Screen callbacks for realtime table events. Set by the currently visible
    /// battle/voting view model; invoked from the single room subscription below.
    var onPlaysChanged: (() -> Void)? = nil
    var onVotesChanged: (() -> Void)? = nil

    func go(_ route: Route) { path.append(route) }

    func goHome() {
        path.removeAll()
        finalRoundWinner = nil
        // Reset real-backend session state for a clean next battle.
        roomId = nil
        myParticipantId = nil
        currentRoundId = nil
        currentRoundNumber = 5
        redCompetitorId = nil
        blueCompetitorId = nil
        matchupArtists = [:]
        backendError = nil
        onPlaysChanged = nil
        onVotesChanged = nil
    }

    // MARK: - Room following (real mode)

    /// Starts the single shared realtime subscription for this room. Call once
    /// after join/host; the subscription survives screen changes so every
    /// device follows the host's flow. Screens set onPlaysChanged/onVotesChanged
    /// for the table events they care about.
    func startFollowingRoom() {
        guard !SCPreview.isActive, let roomId else { return }
        Task {
            do {
                // Seed immediately so screens never render stale mock data.
                if let list = try? await SupabaseService.shared.fetchParticipants(roomId: roomId) {
                    participants = list
                }
                try await SupabaseService.shared.subscribeToRoom(roomId: roomId) { [weak self] event in
                    guard let self else { return }
                    Task { await self.handleRoomEvent(event) }
                }
            } catch {
                self.backendError = error.localizedDescription
            }
        }
    }

    func stopFollowingRoom() {
        onPlaysChanged = nil
        onVotesChanged = nil
        Task { await SupabaseService.shared.unsubscribe() }
    }

    private func handleRoomEvent(_ event: RoomEvent) async {
        switch event {
        case .room:
            guard let roomId,
                  let room = try? await SupabaseService.shared.fetchRoom(id: roomId)
            else { return }
            syncFromRoom(room)
        case .participants:
            guard let roomId else { return }
            if let list = try? await SupabaseService.shared.fetchParticipants(roomId: roomId) {
                participants = list
            }
        case .plays:
            onPlaysChanged?()
        case .votes:
            onVotesChanged?()
        case .rounds:
            break
        }
    }

    /// Drives navigation from the server's room status so every device follows
    /// the host. Guards prevent double-pushing on the acting device's own echo.
    func syncFromRoom(_ room: Room) {
        guard !SCPreview.isActive else { return }
        if room.currentRound > 0 { currentRoundNumber = room.currentRound }
        switch room.status {
        case .lobby:
            break
        case .matchup:
            if !path.contains(.matchup) { go(.matchup) }
        case .coinToss:
            if !path.contains(.coinToss) { go(.coinToss) }
        case .live:
            let route = Route.battle(round: currentRoundNumber)
            if !path.contains(route) { go(route) }
        case .voting:
            let route = Route.voting(round: currentRoundNumber)
            if !path.contains(route) { go(route) }
        case .finished:
            if !path.contains(.results) { go(.results) }
        }
    }

    func name(for side: Side) -> String {
        // Real mode: competitor names come from the participant rows.
        if !SCPreview.isActive {
            let id = side == .red ? redCompetitorId : blueCompetitorId
            if let id, let p = participants.first(where: { $0.id == id }) {
                return p.id == myParticipantId ? "\(p.username) (You)" : p.username
            }
        }
        let base = side == .red ? MockData.redCompetitor.username : MockData.blueCompetitor.username
        return (myRole == .competitor && mySide == side) ? "\(base) (You)" : base
    }

    /// The artist a side is battling with. Prefers the competitor's locked
    /// participant row; falls back to the matchup screen's local picks (solo
    /// / phantom opponents have no row). Nil when nothing was picked.
    func artistPick(for side: Side) -> String? {
        if !SCPreview.isActive {
            let id = side == .red ? redCompetitorId : blueCompetitorId
            if let id,
               let pick = participants.first(where: { $0.id == id })?.artistPick,
               !pick.isEmpty {
                return pick
            }
        }
        return matchupArtists[side]
    }

    var finalScore: (red: Int, blue: Int) {
        var red = scoreboard.filter { $0.winner == .red }.count
        var blue = scoreboard.filter { $0.winner == .blue }.count
        if let w = finalRoundWinner {
            if w == .red { red += 1 } else { blue += 1 }
        }
        return (red, blue)
    }
}
