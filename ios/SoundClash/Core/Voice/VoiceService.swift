import Foundation
import LiveKit

/// Minimal LiveKit voice wrapper: join room, mic toggle, leave.
/// Publishing is gated server-side — the token service only grants canPublish
/// to competitor/judge/host roles, so audience clients subscribe only.
@Observable
@MainActor
final class VoiceService {
    static let shared = VoiceService()

    var isConnected = false
    var remoteParticipantCount = 0
    var microphoneEnabled = false

    private lazy var room: LiveKit.Room = LiveKit.Room(delegate: self)

    private init() {}

    /// Connects to the LiveKit room for this battle. `room` is the battle's
    /// room code so voice follows the same room as the game state.
    func connect(room roomName: String, identity: String, role: ParticipantRole) async throws {
        let creds = try await TokenService.shared.livekitToken(
            room: roomName, identity: identity, role: role
        )
        try await room.connect(url: creds.url, token: creds.token)
        isConnected = true
        remoteParticipantCount = room.remoteParticipants.count
        // Audience tokens carry no publish grant — don't even try the mic there.
        if role != .audience {
            try await setMicrophoneEnabled(true)
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) async throws {
        try await room.localParticipant.setMicrophone(enabled: enabled)
        microphoneEnabled = enabled
    }

    func disconnect() async {
        await room.disconnect()
        isConnected = false
        remoteParticipantCount = 0
        microphoneEnabled = false
    }
}

// MARK: - RoomDelegate

extension VoiceService: RoomDelegate {
    func room(_ room: LiveKit.Room, participantDidJoin participant: RemoteParticipant) {
        remoteParticipantCount = room.remoteParticipants.count
    }

    func room(_ room: LiveKit.Room, participantDidLeave participant: RemoteParticipant) {
        remoteParticipantCount = room.remoteParticipants.count
    }
}
