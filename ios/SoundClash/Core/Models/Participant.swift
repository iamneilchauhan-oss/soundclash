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
    var artistLocked: Bool
    var isReady: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case username
        case role
        case avatar
        case artistPick = "artist_pick"
        case artistLocked = "artist_locked"
        case isReady = "is_ready"
        case createdAt = "created_at"
    }

    // Memberwise init (a custom init(from:) suppresses the synthesized one).
    init(id: UUID, roomId: UUID, username: String, role: ParticipantRole,
         avatar: String?, artistPick: String?, artistLocked: Bool,
         isReady: Bool, createdAt: Date) {
        self.id = id
        self.roomId = roomId
        self.username = username
        self.role = role
        self.avatar = avatar
        self.artistPick = artistPick
        self.artistLocked = artistLocked
        self.isReady = isReady
        self.createdAt = createdAt
    }

    // artist_locked is new (migration 003); tolerate rows from before it existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        roomId = try c.decode(UUID.self, forKey: .roomId)
        username = try c.decode(String.self, forKey: .username)
        role = try c.decode(ParticipantRole.self, forKey: .role)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        artistPick = try c.decodeIfPresent(String.self, forKey: .artistPick)
        artistLocked = try c.decodeIfPresent(Bool.self, forKey: .artistLocked) ?? false
        isReady = try c.decode(Bool.self, forKey: .isReady)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
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
