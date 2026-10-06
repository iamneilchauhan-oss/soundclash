import Foundation

/// Shared realtime-play plumbing for the battle screens (judge / player /
/// spectator). Each screen keeps its own `syncedPlayId` and calls this from
/// its plays-changed handler; the helper starts synced playback and returns
/// the new Play, or nil when there's nothing new to sync.
enum PlaySync {
    @MainActor
    static func nextPlay(roundId: UUID, excluding syncedId: UUID?) async throws -> Play? {
        let plays = try await SupabaseService.shared.fetchPlays(roundId: roundId)
        guard let latest = plays.last,
              latest.startedAt != nil,
              latest.id != syncedId else { return nil }
        try await SyncEngine.shared.startSyncedPlay(play: latest, via: AppleMusicProvider.shared)
        return latest
    }

    /// Which corner a play belongs to, from the room's competitor mapping.
    @MainActor
    static func side(for playerId: UUID, in state: AppState) -> Side {
        playerId == state.blueCompetitorId ? .blue : .red
    }
}
