import Foundation

/// Mirrors the `rooms` table in Supabase.
/// Decode with `decoder.dateDecodingStrategy = .iso8601`.
struct Room: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case lobby
        case matchup
        case coinToss = "coin_toss"
        case live
        case voting
        case finished
    }

    var id: UUID
    var code: String
    var title: String
    var status: Status
    var roundsTotal: Int
    var clipSeconds: Int
    var currentRound: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case title
        case status
        case roundsTotal = "rounds_total"
        case clipSeconds = "clip_seconds"
        case currentRound = "current_round"
        case createdAt = "created_at"
    }
}
