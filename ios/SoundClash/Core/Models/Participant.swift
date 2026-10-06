import Foundation

/// Mirrors the `participants` table in Supabase.
/// Decode with `decoder.dateDecodingStrategy = .iso8601`.
struct Participant: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var roomId: UUID
    var username: String
    var role: ParticipantRole
    var avatar: String?
    var artistPick: String?
    var isReady: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case username
        case role
        case avatar
        case artistPick = "artist_pick"
        case isReady = "is_ready"
        case createdAt = "created_at"
    }
}

enum ParticipantRole: String, Codable, CaseIterable, Sendable {
    case host
    case competitor
    case judge
    case audience

    var displayName: String {
        switch self {
        case .host: "Host"
        case .competitor: "Competitor"
        case .judge: "Judge"
        case .audience: "Audience"
        }
    }
}
