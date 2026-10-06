import Foundation

/// Mirrors the `plays` table in Supabase.
/// `startedAt` is the server timestamp every client syncs against:
/// local position = now - startedAt.
/// Decode with `decoder.dateDecodingStrategy = .iso8601`.
struct Play: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var roundId: UUID
    var playerId: UUID
    var isrc: String
    var appleMusicId: String
    var title: String
    var artist: String
    var artworkUrl: String?
    var startedAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roundId = "round_id"
        case playerId = "player_id"
        case isrc
        case appleMusicId = "apple_music_id"
        case title
        case artist
        case artworkUrl = "artwork_url"
        case startedAt = "started_at"
        case createdAt = "created_at"
    }
}
