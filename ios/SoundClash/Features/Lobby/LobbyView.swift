import SwiftUI
import UIKit

// MARK: - Tier drop frames (for touch-drag hit testing)

/// Each tier reports its frame in the "lobby" coordinate space so the
/// touch-drag gesture can find the drop target under the finger.
struct TierFrameKey: PreferenceKey {
    static var defaultValue: [ParticipantRole: CGRect] = [:]
    static func reduce(value: inout [ParticipantRole: CGRect],
                       nextValue: () -> [ParticipantRole: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

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
    @State private var tierFrames: [ParticipantRole: CGRect] = [:]
    @State private var dragTarget: ParticipantRole?

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
                                isHost: viewModel.isHost, isHostBadge: viewModel.isHostBadge, tierFrames: tierFrames, dragTarget: dragTarget,
                                onTargetChanged: { dragTarget = $0 },
                                onDragDrop: { viewModel.assignRole($0, toId: $1) })

                    TierSection(title: "JUDGES", subtitle: "\(viewModel.judges.count)/3",
                                color: VerzuzTheme.clashB.color, role: .judge,
                                entries: viewModel.judges,
                                isHost: viewModel.isHost, isHostBadge: viewModel.isHostBadge, tierFrames: tierFrames, dragTarget: dragTarget,
                                onTargetChanged: { dragTarget = $0 },
                                onDragDrop: { viewModel.assignRole($0, toId: $1) })

                    TierSection(title: "AUDIENCE", color: .gray, role: .audience,
                                entries: viewModel.audience,
                                isHost: viewModel.isHost, isHostBadge: viewModel.isHostBadge, tierFrames: tierFrames, dragTarget: dragTarget,
                                onTargetChanged: { dragTarget = $0 },
                                onDragDrop: { viewModel.assignRole($0, toId: $1) })

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
            .coordinateSpace(name: "lobby")
            .onPreferenceChange(TierFrameKey.self) { tierFrames = $0 }
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

// MARK: - Tier section (touch-drag circles)

struct TierSection: View {
    let title: String
    var subtitle: String?
    let color: Color
    let role: ParticipantRole
    let entries: [Participant]
    let isHost: Bool
    let isHostBadge: (Participant) -> Bool
    let tierFrames: [ParticipantRole: CGRect]
    let dragTarget: ParticipantRole?
    let onTargetChanged: (ParticipantRole?) -> Void
    /// (target tier, participant id)
    let onDragDrop: (ParticipantRole, UUID) -> Void

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
                    ParticipantCircle(
                        participant: p,
                        color: color,
                        isHost: isHost,
                        showHostBadge: isHostBadge(p),
                        tierFrames: tierFrames,
                        onTargetChanged: onTargetChanged,
                        onDrop: { onDragDrop($0, p.id) }
                    )
                }
            }
            .frame(minHeight: 96)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(dragTarget == role ? color.opacity(0.22) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        dragTarget == role ? color : Color.white.opacity(0.12),
                        lineWidth: dragTarget == role ? 2 : 1
                    )
            )
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: TierFrameKey.self,
                        value: [role: geo.frame(in: .named("lobby"))]
                    )
                }
            )
        }
    }
}

// MARK: - Draggable participant circle (touch-drag, no long-press)

/// A participant rendered as a circle. The host touch-drags it straight into
/// a tier — `DragGesture(minimumDistance: 0)` starts the drag the moment the
/// finger moves, no long-press. The drop target is found by hit-testing the
/// release point against the tier frames in the "lobby" coordinate space.
struct ParticipantCircle: View {
    let participant: Participant
    let color: Color
    let isHost: Bool
    let showHostBadge: Bool
    let tierFrames: [ParticipantRole: CGRect]
    let onTargetChanged: (ParticipantRole?) -> Void
    /// Target tier the circle was released over.
    let onDrop: (ParticipantRole) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 60, height: 60)
                Text(initials(of: participant.username))
                    .font(VerzuzTheme.display(20))
                    .foregroundStyle(.black)
            }
            HStack(spacing: 3) {
                Text(participant.username)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if showHostBadge {
                    VMark(left: .white.opacity(0.55), right: .white.opacity(0.55))
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 72)
        }
        .scaleEffect(isDragging ? 1.18 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.5 : 0), radius: isDragging ? 10 : 0)
        .offset(dragOffset)
        .zIndex(isDragging ? 10 : 0)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("lobby"))
                .onChanged { value in
                    guard isHost else { return }
                    isDragging = true
                    dragOffset = value.translation
                    onTargetChanged(target(at: value.location))
                }
                .onEnded { value in
                    guard isHost else { return }
                    isDragging = false
                    dragOffset = .zero
                    onTargetChanged(nil)
                    if let target = target(at: value.location) {
                        onDrop(target)
                    }
                },
            including: isHost ? .all : .none
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
    }

    private func target(at location: CGPoint) -> ParticipantRole? {
        tierFrames.first(where: { $0.value.contains(location) })?.key
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
