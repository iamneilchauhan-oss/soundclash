import Foundation

/// Mirrors the `rounds` table in Supabase.
/// Decode with `decoder.dateDecodingStrategy = .iso8601`.
struct Round: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case pending
        case playing
        case voting
        case done
    }

    var id: UUID
    var roomId: UUID
    var roundNumber: Int
    var firstPlayerId: UUID?
    var status: Status
    var winnerId: UUID?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case roundNumber = "round_number"
        case firstPlayerId = "first_player_id"
        case status
        case winnerId = "winner_id"
        case createdAt = "created_at"
    }
}
