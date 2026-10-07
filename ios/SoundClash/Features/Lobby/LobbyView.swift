import SwiftUI
import UIKit

@Observable
@MainActor
final class LobbyViewModel {
    var appState: AppState!
    var isReady = false
    var assigning: Participant?

    func configure(_ state: AppState) {
        appState = state
        // Preview: materialize "me" as a real participant row so the whole
        // host-assignment flow is testable with one device.
        if SCPreview.isActive {
            let meId = appState.myParticipantId ?? UUID()
            appState.myParticipantId = meId
            if !appState.participants.contains(where: { $0.id == meId }) {
                let name = appState.username.isEmpty ? "You" : appState.username
                appState.participants.insert(
                    Participant(id: meId, roomId: UUID(), username: name, role: .host,
                                avatar: nil, artistPick: nil, isReady: false, createdAt: Date()),
                    at: 0
                )
            }
        }
    }

    var myParticipant: Participant? {
        appState.participants.first(where: { $0.id == appState.myParticipantId })
    }

    /// Only the host assigns roles. In preview the tester always drives.
    var isHost: Bool {
        if SCPreview.isActive { return true }
        return myParticipant?.role == .host
    }

    // MARK: - Tiers

    var hosts: [Participant] { appState.participants.filter { $0.role == .host } }
    var players: [Participant] { appState.participants.filter { $0.role == .competitor } }
    var judges: [Participant] { appState.participants.filter { $0.role == .judge } }
    var audience: [Participant] { appState.participants.filter { $0.role == .audience } }

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
        isReady.toggle()
        if let id = appState.myParticipantId,
           let i = appState.participants.firstIndex(where: { $0.id == id }) {
            appState.participants[i].isReady = isReady
        }
        guard !SCPreview.isActive, let id = appState.myParticipantId,
              let p = myParticipant else { return }
        Task {
            do {
                try await SupabaseService.shared.updateLobbyProfile(
                    id: id, role: p.role, avatar: p.avatar ?? "", isReady: isReady
                )
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    // MARK: - Host role assignment

    func assignRole(_ role: ParticipantRole, to participant: Participant) {
        defer { assigning = nil }
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
        Task {
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
        if let role = myParticipant?.role { appState.myRole = role }
        appState.mySide = .red // mock: local competitor always takes the red corner
        guard !SCPreview.isActive, let roomId = appState.roomId else {
            appState.go(.matchup)
            return
        }
        Task {
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

    private var accent: VerzuzTheme.Accent { VerzuzTheme.menuAccent }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle brand watermark (split lives on the home screen only).
            VMark(left: accent.color, right: accent.color)
                .opacity(0.06)
                .frame(width: 320, height: 320)

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

                    TierSection(title: "HOST", color: SCTheme.gold,
                                entries: viewModel.hosts, myId: appState.myParticipantId,
                                canAssign: viewModel.isHost,
                                onAssign: { viewModel.assigning = $0 })

                    TierSection(title: "PLAYERS", subtitle: "\(viewModel.players.count)/2",
                                color: VerzuzTheme.clashA.color,
                                entries: viewModel.players, myId: appState.myParticipantId,
                                canAssign: viewModel.isHost,
                                onAssign: { viewModel.assigning = $0 })

                    TierSection(title: "JUDGES", subtitle: "\(viewModel.judges.count)/3",
                                color: VerzuzTheme.clashB.color,
                                entries: viewModel.judges, myId: appState.myParticipantId,
                                canAssign: viewModel.isHost,
                                onAssign: { viewModel.assigning = $0 })

                    TierSection(title: "AUDIENCE", color: .gray,
                                entries: viewModel.audience, myId: appState.myParticipantId,
                                canAssign: viewModel.isHost,
                                onAssign: { viewModel.assigning = $0 })

                    if viewModel.isHost {
                        Text("Tap a player to assign their role.")
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
        .confirmationDialog(
            "Assign role",
            isPresented: Binding(
                get: { viewModel.assigning != nil },
                set: { if !$0 { viewModel.assigning = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let p = viewModel.assigning {
                Button("Player") { viewModel.assignRole(.competitor, to: p) }
                Button("Judge") { viewModel.assignRole(.judge, to: p) }
                Button("Audience") { viewModel.assignRole(.audience, to: p) }
            }
        } message: {
            if let p = viewModel.assigning {
                Text("Choose \(p.username)'s role in this battle.")
            }
        }
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
    let entries: [Participant]
    let myId: UUID?
    let canAssign: Bool
    let onAssign: (Participant) -> Void

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

            if entries.isEmpty {
                Text("No one yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 4)
            }

            ForEach(entries) { p in
                Button {
                    if canAssign { onAssign(p) }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(color).frame(width: 40, height: 40)
                            Text(initials(of: p.username))
                                .font(VerzuzTheme.display(16))
                                .foregroundStyle(.black)
                        }
                        Text(p.id == myId ? "\(p.username) (YOU)" : p.username)
                            .font(VerzuzTheme.display(16))
                            .foregroundStyle(.white)
                        Spacer()
                        if canAssign {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        Image(systemName: p.isReady ? "checkmark.circle.fill" : "clock")
                            .font(.system(size: 20))
                            .foregroundStyle(p.isReady ? .green : .white.opacity(0.35))
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canAssign)
            }
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
