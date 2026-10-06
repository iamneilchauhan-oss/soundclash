import Foundation

/// Mirrors the `votes` table in Supabase.
/// One vote per judge per round (unique constraint on round_id + judge_id).
/// Decode with `decoder.dateDecodingStrategy = .iso8601`.
struct Vote: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var roundId: UUID
    var judgeId: UUID
    var votedForId: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roundId = "round_id"
        case judgeId = "judge_id"
        case votedForId = "voted_for_id"
        case createdAt = "created_at"
    }
}
