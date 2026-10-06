import Foundation

/// Talks to the SoundClash token service (see backend/token-service/server.js).
///
/// IMPORTANT — MusicKit developer tokens: the service mints one at
/// GET /v1/musickit-token, but the iOS app must NEVER fetch or use it. On native
/// iOS there is no developer-token API at all — MusicKit generates and attaches
/// the token itself, invisibly, once the MusicKit capability/App Service is
/// enabled for the bundle ID and MusicAuthorization.request() succeeds. That
/// endpoint exists for server-side Apple Music API calls only. Fetching a
/// developer token into app code is a documented non-starter (it cannot work),
/// so this service exposes only the LiveKit token.
@MainActor
final class TokenService {
    static let shared = TokenService()

    private init() {}

    struct LiveKitCredentials: Decodable {
        var token: String
        var url: String
    }

    enum TokenError: Error, LocalizedError {
        case notConfigured
        case badResponse(Int)
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Token service isn't configured — fill in SCConfig.tokenServiceBaseURL."
            case .badResponse(let code):
                return "Token service returned HTTP \(code)."
            case .network(let error):
                return error.localizedDescription
            }
        }
    }

    /// POST /v1/livekit-token { room, identity, role } -> { token, url }.
    /// The `role` gates the grant server-side: competitor/judge/host get
    /// canPublish; audience subscribes only.
    func livekitToken(room: String, identity: String, role: ParticipantRole) async throws -> LiveKitCredentials {
        guard !SCConfig.tokenServiceBaseURL.contains("YOUR_TOKEN_SERVICE") else {
            throw TokenError.notConfigured
        }
        var request = URLRequest(
            url: URL(string: SCConfig.tokenServiceBaseURL + "/v1/livekit-token")!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "room": room,
            "identity": identity,
            "role": role.rawValue,
        ])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TokenError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw TokenError.badResponse(status)
        }
        do {
            return try JSONDecoder().decode(LiveKitCredentials.self, from: data)
        } catch {
            throw TokenError.network(error)
        }
    }
}
