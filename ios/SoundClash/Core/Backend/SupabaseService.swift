import Foundation
import Supabase

// MARK: - Errors

enum BackendError: Error, LocalizedError {
    case notConfigured
    case notFound(String)
    case requestFailed(Error)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase isn't configured — fill in SCConfig (see Core/Config.swift)."
        case .notFound(let what):
            return "Couldn't find \(what). Check the room code and try again."
        case .requestFailed(let error):
            return error.localizedDescription
        case .timedOut:
            return "The request timed out. Check your connection and try again."
        }
    }
}

// MARK: - Realtime events

/// Coarse-grained room events. Handlers refetch the relevant table rather than
/// decoding realtime payloads — battle traffic is tiny, and refetch-on-change
/// avoids a whole class of realtime decoding bugs.
enum RoomEvent: Sendable {
    case room
    case participants
    case rounds
    case plays
    case votes
}

// MARK: - Service

/// Thin wrapper over supabase-swift. All tables use the prototype-open RLS
/// policies from 001_initial_schema.sql, so no auth is needed yet — the day RLS
/// tightens, this is the one place that grows a sign-in.
@Observable
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    private let client: SupabaseClient
    private var roomChannel: RealtimeChannelV2?
    /// Retained — dropping an ObservationToken silently unsubscribes its callback.
    private var observationTokens: Set<ObservationToken> = []

    private init() {
        // Force-unwrap is deliberate: a malformed URL is a programmer error,
        // and checkConfigured() throws a friendly error before we get here.
        self.client = SupabaseClient(
            supabaseURL: URL(string: SCConfig.supabaseURL)!,
            supabaseKey: SCConfig.supabaseAnonKey
        )
    }

    // MARK: - Config

    func checkConfigured() throws {
        if SCConfig.supabaseURL.contains("YOUR_PROJECT")
            || SCConfig.supabaseAnonKey.contains("YOUR_")
            || SCConfig.supabaseAnonKey.isEmpty
        {
            throw BackendError.notConfigured
        }
    }

    // MARK: - Rooms

    static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    func createRoom(title: String, roundsTotal: Int = 5, clipSeconds: Int = 90) async throws -> Room {
        try checkConfigured()
        struct Payload: Encodable {
            var code: String
            var title: String
            var status: Room.Status
            var roundsTotal: Int
            var clipSeconds: Int
            enum CodingKeys: String, CodingKey {
                case code, title, status
                case roundsTotal = "rounds_total"
                case clipSeconds = "clip_seconds"
            }
        }
        let response: PostgrestResponse<[Room]> = try await client
            .from("rooms")
            .insert(
                Payload(code: Self.makeCode(), title: title, status: .lobby,
                        roundsTotal: roundsTotal, clipSeconds: clipSeconds),
                returning: .representation
            )
            .execute()
        guard let room = response.value.first else { throw BackendError.notFound("room") }
        return room
    }

    func fetchRoom(code: String) async throws -> Room {
        try checkConfigured()
        do {
            let response: PostgrestResponse<Room> = try await client
                .from("rooms")
                .select()
                .eq("code", value: code)
                .single()
                .execute()
            return response.value
        } catch {
            throw BackendError.notFound("a room with code \(code)")
        }
    }

    func fetchRoom(id: UUID) async throws -> Room {
        try checkConfigured()
        let response: PostgrestResponse<Room> = try await client
            .from("rooms")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
        return response.value
    }

    func advanceRoomStatus(roomId: UUID, status: Room.Status) async throws {
        try checkConfigured()
        let _: PostgrestResponse<Void> = try await client
            .from("rooms")
            .update(["status": status.rawValue])
            .eq("id", value: roomId.uuidString)
            .execute()
    }

    // MARK: - Participants

    func joinRoom(roomId: UUID, username: String, role: ParticipantRole, avatar: String?) async throws -> Participant {
        try checkConfigured()
        struct Payload: Encodable {
            var roomId: UUID
            var username: String
            var role: ParticipantRole
            var avatar: String?
            enum CodingKeys: String, CodingKey {
                case username, role, avatar
                case roomId = "room_id"
            }
        }
        let response: PostgrestResponse<[Participant]> = try await client
            .from("participants")
            .insert(Payload(roomId: roomId, username: username, role: role, avatar: avatar),
                    returning: .representation)
            .execute()
        guard let participant = response.value.first else { throw BackendError.notFound("participant") }
        return participant
    }

    func fetchParticipants(roomId: UUID) async throws -> [Participant] {
        try checkConfigured()
        let response: PostgrestResponse<[Participant]> = try await client
            .from("participants")
            .select()
            .eq("room_id", value: roomId.uuidString)
            .order("created_at")
            .execute()
        return response.value
    }

    /// Lobby profile update: role + avatar + ready flag in one write.
    func updateLobbyProfile(id: UUID, role: ParticipantRole, avatar: String, isReady: Bool) async throws {
        try checkConfigured()
        struct Payload: Encodable {
            var role: ParticipantRole
            var avatar: String
            var isReady: Bool
            enum CodingKeys: String, CodingKey {
                case role, avatar
                case isReady = "is_ready"
            }
        }
        let _: PostgrestResponse<Void> = try await client
            .from("participants")
            .update(Payload(role: role, avatar: avatar, isReady: isReady))
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Locks a competitor's artist pick (also marks them ready).
    /// Live-sync the artist pick on every select. (Lock-in is separate.)
    func setArtistPick(participantId: UUID, artist: String) async throws {
        try checkConfigured()
        struct Payload: Encodable {
            var artistPick: String
            enum CodingKeys: String, CodingKey {
                case artistPick = "artist_pick"
            }
        }
        let _: PostgrestResponse<Void> = try await client
            .from("participants")
            .update(Payload(artistPick: artist))
            .eq("id", value: participantId.uuidString)
            .execute()
    }

    /// Explicit lock-in: "I'm done picking." Separate from the live pick sync.
    func setArtistLocked(participantId: UUID, locked: Bool) async throws {
        try checkConfigured()
        struct Payload: Encodable {
            var artistLocked: Bool
            enum CodingKeys: String, CodingKey {
                case artistLocked = "artist_locked"
            }
        }
        let _: PostgrestResponse<Void> = try await client
            .from("participants")
            .update(Payload(artistLocked: locked))
            .eq("id", value: participantId.uuidString)
            .execute()
    }

    // MARK: - Rounds

    func createRound(roomId: UUID, roundNumber: Int, firstPlayerId: UUID?) async throws -> Round {
        try checkConfigured()
        struct Payload: Encodable {
            var roomId: UUID
            var roundNumber: Int
            var firstPlayerId: UUID?
            var status: Round.Status
            enum CodingKeys: String, CodingKey {
                case status
                case roomId = "room_id"
                case roundNumber = "round_number"
                case firstPlayerId = "first_player_id"
            }
        }
        let response: PostgrestResponse<[Round]> = try await client
            .from("rounds")
            .insert(Payload(roomId: roomId, roundNumber: roundNumber,
                            firstPlayerId: firstPlayerId, status: .playing),
                    returning: .representation)
            .execute()
        guard let round = response.value.first else { throw BackendError.notFound("round") }
        // Keep rooms.current_round in step so followers can navigate to the battle.
        let _: PostgrestResponse<Void> = try await client
            .from("rooms")
            .update(["current_round": roundNumber])
            .eq("id", value: roomId.uuidString)
            .execute()
        return round
    }

    func setRoundStatus(roundId: UUID, status: Round.Status) async throws {
        try checkConfigured()
        let _: PostgrestResponse<Void> = try await client
            .from("rounds")
            .update(["status": status.rawValue])
            .eq("id", value: roundId.uuidString)
            .execute()
    }

    func finishRound(roundId: UUID, winnerId: UUID?) async throws {
        try checkConfigured()
        struct Payload: Encodable {
            var status: Round.Status
            var winnerId: UUID?
            enum CodingKeys: String, CodingKey {
                case status
                case winnerId = "winner_id"
            }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(status, forKey: .status)
                try container.encodeIfPresent(winnerId, forKey: .winnerId)
            }
        }
        let _: PostgrestResponse<Void> = try await client
            .from("rounds")
            .update(Payload(status: .done, winnerId: winnerId))
            .eq("id", value: roundId.uuidString)
            .execute()
    }

    func fetchRounds(roomId: UUID) async throws -> [Round] {
        try checkConfigured()
        let response: PostgrestResponse<[Round]> = try await client
            .from("rounds")
            .select()
            .eq("room_id", value: roomId.uuidString)
            .order("round_number")
            .execute()
        return response.value
    }

    // MARK: - Plays

    /// Records a competitor's track pick. `started_at` is deliberately omitted so
    /// Postgres stamps the authoritative server time (see
    /// 002_started_at_default.sql) — every client syncs against the returned
    /// timestamp, which absorbs host clock skew.
    func recordPlay(roundId: UUID, playerId: UUID, track: SCTrack) async throws -> Play {
        try checkConfigured()
        struct Payload: Encodable {
            var roundId: UUID
            var playerId: UUID
            var isrc: String
            var appleMusicId: String
            var title: String
            var artist: String
            var artworkUrl: String?
            enum CodingKeys: String, CodingKey {
                case isrc, title, artist
                case roundId = "round_id"
                case playerId = "player_id"
                case appleMusicId = "apple_music_id"
                case artworkUrl = "artwork_url"
            }
        }
        let response: PostgrestResponse<[Play]> = try await client
            .from("plays")
            .insert(Payload(roundId: roundId, playerId: playerId, isrc: track.isrc,
                            appleMusicId: track.appleMusicId, title: track.title,
                            artist: track.artist,
                            artworkUrl: track.artworkURL?.absoluteString),
                    returning: .representation)
            .execute()
        guard let play = response.value.first else { throw BackendError.notFound("play") }
        return play
    }

    /// Explicit (possibly future) start time, for countdown-style drops.
    /// Encoded as an ISO8601 string to avoid client date-encoding ambiguity.
    func schedulePlay(playId: UUID, startAt: Date) async throws {
        try checkConfigured()
        let iso = ISO8601DateFormatter().string(from: startAt)
        let _: PostgrestResponse<Void> = try await client
            .from("plays")
            .update(["started_at": iso])
            .eq("id", value: playId.uuidString)
            .execute()
    }

    func fetchPlays(roundId: UUID) async throws -> [Play] {
        try checkConfigured()
        let response: PostgrestResponse<[Play]> = try await client
            .from("plays")
            .select()
            .eq("round_id", value: roundId.uuidString)
            .order("created_at")
            .execute()
        return response.value
    }

    // MARK: - Votes

    /// Upsert: a judge re-voting overwrites their previous vote (matches the
    /// unique(round_id, judge_id) constraint instead of fighting it).
    func castVote(roundId: UUID, judgeId: UUID, votedForId: UUID) async throws -> Vote {
        try checkConfigured()
        struct Payload: Encodable {
            var roundId: UUID
            var judgeId: UUID
            var votedForId: UUID
            enum CodingKeys: String, CodingKey {
                case roundId = "round_id"
                case judgeId = "judge_id"
                case votedForId = "voted_for_id"
            }
        }
        let response: PostgrestResponse<[Vote]> = try await client
            .from("votes")
            .upsert(Payload(roundId: roundId, judgeId: judgeId, votedForId: votedForId),
                    onConflict: "round_id,judge_id",
                    returning: .representation)
            .execute()
        guard let vote = response.value.first else { throw BackendError.notFound("vote") }
        return vote
    }

    func fetchVotes(roundId: UUID) async throws -> [Vote] {
        try checkConfigured()
        let response: PostgrestResponse<[Vote]> = try await client
            .from("votes")
            .select()
            .eq("round_id", value: roundId.uuidString)
            .order("created_at")
            .execute()
        return response.value
    }

    // MARK: - Rematch

    /// Fresh battle, same room + crew: drops rounds (plays/votes cascade),
    /// clears picks and ready flags, back to the lobby.
    func resetRoom(roomId: UUID) async throws {
        try checkConfigured()
        let _: PostgrestResponse<Void> = try await client
            .from("rounds")
            .delete()
            .eq("room_id", value: roomId.uuidString)
            .execute()
        let _: PostgrestResponse<Void> = try await client
            .from("participants")
            .update(["is_ready": false])
            .eq("room_id", value: roomId.uuidString)
            .execute()
        let _: PostgrestResponse<Void> = try await client
            .from("participants")
            .update(["artist_pick": nil] as [String: String?])
            .eq("room_id", value: roomId.uuidString)
            .execute()
        try await advanceRoomStatus(roomId: roomId, status: .lobby)
    }

    // MARK: - Realtime

    /// Subscribes to every table change in a room. Exactly one room subscription
    /// is kept — calling this again replaces the previous one. Handlers refetch
    /// rather than decode payloads (see RoomEvent). `onEvent` always runs on
    /// the main actor (the service hops for you).
    func subscribeToRoom(roomId: UUID, onEvent: @escaping @MainActor (RoomEvent) -> Void) async throws {
        try checkConfigured()
        await unsubscribe()
        let id = roomId.uuidString
        let channel = client.realtimeV2.channel("room-\(id)")

        let tokens: [ObservationToken] = [
            channel.onPostgresChange(
                UpdateAction.self, schema: "public", table: "rooms",
                filter: "id=eq.\(id)"
            ) { _ in Task { @MainActor in onEvent(.room) } },
            channel.onPostgresChange(
                InsertAction.self, schema: "public", table: "participants",
                filter: "room_id=eq.\(id)"
            ) { _ in Task { @MainActor in onEvent(.participants) } },
            channel.onPostgresChange(
                UpdateAction.self, schema: "public", table: "participants",
                filter: "room_id=eq.\(id)"
            ) { _ in Task { @MainActor in onEvent(.participants) } },
            channel.onPostgresChange(
                InsertAction.self, schema: "public", table: "rounds",
                filter: "room_id=eq.\(id)"
            ) { _ in Task { @MainActor in onEvent(.rounds) } },
            channel.onPostgresChange(
                UpdateAction.self, schema: "public", table: "rounds",
                filter: "room_id=eq.\(id)"
            ) { _ in Task { @MainActor in onEvent(.rounds) } },
            // plays/votes carry round_id, not room_id — subscribe unfiltered and
            // let the handler ignore rows for other rounds.
            channel.onPostgresChange(
                InsertAction.self, schema: "public", table: "plays"
            ) { _ in Task { @MainActor in onEvent(.plays) } },
            channel.onPostgresChange(
                UpdateAction.self, schema: "public", table: "plays"
            ) { _ in Task { @MainActor in onEvent(.plays) } },
            channel.onPostgresChange(
                InsertAction.self, schema: "public", table: "votes"
            ) { _ in Task { @MainActor in onEvent(.votes) } },
        ]
        observationTokens.formUnion(tokens)
        try await channel.subscribeWithError()
        roomChannel = channel
    }

    func unsubscribe() async {
        if let channel = roomChannel {
            await client.realtimeV2.removeChannel(channel)
            roomChannel = nil
        }
        observationTokens.removeAll()
    }
}
