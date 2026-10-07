import SwiftUI
import UIKit

@Observable
@MainActor
final class LobbyViewModel {
    /// Optional: SwiftUI evaluates the body before `.task` runs `configure`,
    /// so every read must tolerate nil on the first pass.
    var appState: AppState?
    var isReady = false

    func configure(_ state: AppState) {
        appState = state
        // Preview: materialize "me" as a real participant row so the whole
        // host-assignment flow is testable with one device.
        if SCPreview.isActive {
            let meId = state.myParticipantId ?? UUID()
            state.myParticipantId = meId
            if !state.participants.contains(where: { $0.id == meId }) {
                let name = state.username.isEmpty ? "You" : state.username
                state.participants.insert(
                    Participant(id: meId, roomId: UUID(), username: name, role: .host,
                                avatar: nil, artistPick: nil, isReady: false, createdAt: Date()),
                    at: 0
                )
            }
        }
    }

    var myParticipant: Participant? {
        guard let appState else { return nil }
        return appState.participants.first(where: { $0.id == appState.myParticipantId })
    }

    /// Only the host assigns roles. In preview the tester always drives.
    /// Host powers survive the host assigning themselves as a player.
    var isHost: Bool {
        if SCPreview.isActive { return true }
        guard let appState else { return false }
        return appState.amHost || myParticipant?.role == .host
    }

    // MARK: - Tiers

    var players: [Participant] { (appState?.participants ?? []).filter { $0.role == .competitor } }
    var judges: [Participant] { (appState?.participants ?? []).filter { $0.role == .judge } }
    /// Audience doubles as the host's home — no separate host tier.
    var audience: [Participant] {
        (appState?.participants ?? []).filter { $0.role == .audience || $0.role == .host }
    }

    /// True when this participant should show the host V badge.
    func isHostBadge(for p: Participant) -> Bool {
        if p.role == .host { return true }
        guard let appState else { return false }
        return appState.amHost && p.id == appState.myParticipantId
    }

    // MARK: - Bottom button: READY arms it, second tap starts (host only)

    var bottomLabel: String {
        if isHost { return isReady ? "START BATTLE" : "READY" }
        return isReady ? "WAITING FOR HOST" : "READY"
    }

    var bottomDisabled: Bool { !isHost && isReady }

    func bottomTap() {
        if isHost {
            if isReady { start() } else { toggleReady() }
        } else if !isReady {
            toggleReady()
        }
    }

    func toggleReady() {
        guard let appState else { return }
        isReady.toggle()
        if let id = appState.myParticipantId,
           let i = appState.participants.firstIndex(where: { $0.id == id }) {
            appState.participants[i].isReady = isReady
        }
        guard !SCPreview.isActive, let id = appState.myParticipantId,
              let p = myParticipant else { return }
        let isReadyValue = isReady
        Task { @MainActor in
            do {
                try await SupabaseService.shared.updateLobbyProfile(
                    id: id, role: p.role, avatar: p.avatar ?? "", isReady: isReadyValue
                )
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    // MARK: - Host role assignment

    func assignRole(_ role: ParticipantRole, toId id: UUID) {
        guard let p = appState?.participants.first(where: { $0.id == id }) else { return }
        assignRole(role, to: p)
    }

    func assignRole(_ role: ParticipantRole, to participant: Participant) {
        guard let appState else { return }
        if role == .competitor && players.count >= 2 && participant.role != .competitor {
            appState.backendError = "Players are full (2 max)."
            return
        }
        if role == .judge && judges.count >= 3 && participant.role != .judge {
            appState.backendError = "Judges are full (3 max)."
            return
        }
        if SCPreview.isActive {
            if let i = appState.participants.firstIndex(where: { $0.id == participant.id }) {
                appState.participants[i].role = role
            }
            return
        }
        Task { @MainActor in
            do {
                try await SupabaseService.shared.updateLobbyProfile(
                    id: participant.id, role: role,
                    avatar: participant.avatar ?? "", isReady: participant.isReady
                )
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    func start() {
        guard let appState else { return }
        if let role = myParticipant?.role { appState.myRole = role }
        appState.mySide = .red // mock: local competitor always takes the red corner
        guard !SCPreview.isActive, let roomId = appState.roomId else {
            appState.go(.matchup)
            return
        }
        Task { @MainActor in
            do {
                try await SupabaseService.shared.advanceRoomStatus(roomId: roomId, status: .matchup)
                appState.go(.matchup)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }
}

struct LobbyView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = LobbyViewModel()
    @State private var dropTarget: ParticipantRole?

    private var accent: VerzuzTheme.Accent { VerzuzTheme.menuAccent }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()


            ScrollView {
                VStack(spacing: 18) {
                    // Room code
                    Button {
                        UIPasteboard.general.string = appState.roomCode
                    } label: {
                        VStack(spacing: 4) {
                            Text("ROOM CODE")
                                .font(VerzuzTheme.display(13))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(appState.roomCode.isEmpty ? "------" : appState.roomCode)
                                .font(VerzuzTheme.display(46))
                                .foregroundStyle(.white)
                            Text("TAP TO COPY")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }

                    TierSection(title: "PLAYERS", subtitle: "\(viewModel.players.count)/2",
                                color: VerzuzTheme.clashA.color, role: .competitor,
                                entries: viewModel.players,
                                isHost: viewModel.isHost, isHostBadge: viewModel.isHostBadge, dropTarget: $dropTarget,
                                onDrop: { viewModel.assignRole(.competitor, toId: $0) })

                    TierSection(title: "JUDGES", subtitle: "\(viewModel.judges.count)/3",
                                color: VerzuzTheme.clashB.color, role: .judge,
                                entries: viewModel.judges,
                                isHost: viewModel.isHost, isHostBadge: viewModel.isHostBadge, dropTarget: $dropTarget,
                                onDrop: { viewModel.assignRole(.judge, toId: $0) })

                    TierSection(title: "AUDIENCE", color: .gray, role: .audience,
                                entries: viewModel.audience,
                                isHost: viewModel.isHost, isHostBadge: viewModel.isHostBadge, dropTarget: $dropTarget,
                                onDrop: { viewModel.assignRole(.audience, toId: $0) })

                    if viewModel.isHost {
                        Text("Drag people into roles to assign them.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Button(viewModel.bottomLabel) { viewModel.bottomTap() }
                        .buttonStyle(VerzuzButtonStyle(fill: accent.color, textColor: accent.onColor, fontSize: 24))
                        .disabled(viewModel.bottomDisabled)
                        .opacity(viewModel.bottomDisabled ? 0.5 : 1)
                        .padding(.bottom, 8)
                }
                .padding(20)
            }
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Couldn't continue", isPresented: Binding(
            get: { appState.backendError != nil },
            set: { if !$0 { appState.backendError = nil } }
        )) {
            Button("OK") { appState.backendError = nil }
        } message: {
            Text(appState.backendError ?? "")
        }
    }
}

// MARK: - Tier section (no emojis: initial circles only)

struct TierSection: View {
    let title: String
    var subtitle: String?
    let color: Color
    let role: ParticipantRole
    let entries: [Participant]
    let isHost: Bool
    let isHostBadge: (Participant) -> Bool
    @Binding var dropTarget: ParticipantRole?
    let onDrop: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(VerzuzTheme.display(20))
                    .foregroundStyle(color)
                if let subtitle {
                    Text(subtitle)
                        .font(VerzuzTheme.display(14))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(entries) { p in
                    participantCircle(p)
                }
            }
            .frame(minHeight: 96)
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(dropTarget == role ? color.opacity(0.22) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        dropTarget == role ? color : Color.white.opacity(0.12),
                        lineWidth: dropTarget == role ? 2 : 1
                    )
            )
            .dropDestination(for: String.self) { ids, _ in
                guard isHost,
                      let idString = ids.first,
                      let id = UUID(uuidString: idString) else { return false }
                onDrop(id)
                return true
            } isTargeted: { targeted in
                dropTarget = targeted ? role : nil
            }
        }
    }

    @ViewBuilder
    private func participantCircle(_ p: Participant) -> some View {
        let circle = VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 60, height: 60)
                Text(initials(of: p.username))
                    .font(VerzuzTheme.display(20))
                    .foregroundStyle(.black)
            }
            HStack(spacing: 3) {
                Text(p.username)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if isHostBadge(p) {
                    VMark(left: .white.opacity(0.55), right: .white.opacity(0.55))
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 72)
        }

        if isHost {
            circle.draggable(p.id.uuidString) {
                ZStack {
                    Circle().fill(color).frame(width: 48, height: 48)
                    Text(initials(of: p.username))
                        .font(VerzuzTheme.display(16))
                        .foregroundStyle(.black)
                }
            }
        } else {
            circle
        }
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.map { String($0.prefix(1)) }.joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}

#Preview {
    LobbyView()
        .environment(MockData.previewState())
}
