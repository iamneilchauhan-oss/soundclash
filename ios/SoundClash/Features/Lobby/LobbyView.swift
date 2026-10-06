import SwiftUI
import UIKit

@Observable
@MainActor
final class LobbyViewModel {
    var appState: AppState!
    var selectedRole: ParticipantRole = .competitor
    var selectedAvatar = "🎤"
    var isReady = false

    let avatarOptions = ["🎤", "🎧", "🎹", "🎷", "🎸", "🥁", "🎺", "🎻", "📀", "🎙️", "🔥", "⭐"]
    let selectableRoles: [ParticipantRole] = [.competitor, .judge, .audience]

    func configure(_ state: AppState) { appState = state }

    func toggleReady() {
        isReady.toggle()
        // Real mode: push role + avatar + ready flag; every device sees it via
        // the shared participants subscription in AppState.
        guard !SCPreview.isActive, let id = appState.myParticipantId else { return }
        Task {
            do {
                try await SupabaseService.shared.updateLobbyProfile(
                    id: id, role: selectedRole, avatar: selectedAvatar, isReady: isReady
                )
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    func start() {
        appState.myRole = selectedRole
        appState.mySide = .red // mock: local competitor always takes the red corner
        guard !SCPreview.isActive, let roomId = appState.roomId else {
            appState.go(.matchup)
            return
        }
        // Real mode: the room status drives every device (AppState.syncFromRoom).
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

    var body: some View {
        ZStack {
            SCTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Room code
                    VStack(spacing: 6) {
                        Text("ROOM CODE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                        Button {
                            UIPasteboard.general.string = appState.roomCode
                        } label: {
                            Text(appState.roomCode.isEmpty ? "------" : appState.roomCode)
                                .font(.system(size: 40, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        Text("Tap to copy")
                            .font(.caption)
                            .foregroundStyle(SCTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .scCard()

                    // You: role + avatar + ready
                    VStack(alignment: .leading, spacing: 12) {
                        Text("YOU — \(appState.username.isEmpty ? "Player" : appState.username)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Picker("Role", selection: $viewModel.selectedRole) {
                            ForEach(viewModel.selectableRoles, id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(viewModel.avatarOptions, id: \.self) { emoji in
                                Button {
                                    viewModel.selectedAvatar = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 28))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(viewModel.selectedAvatar == emoji
                                                      ? SCTheme.blue.opacity(0.35)
                                                      : SCTheme.background)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(viewModel.selectedAvatar == emoji ? SCTheme.blue : .clear, lineWidth: 2)
                                        )
                                }
                            }
                        }

                        Button {
                            viewModel.toggleReady()
                        } label: {
                            HStack {
                                Image(systemName: viewModel.isReady ? "checkmark.circle.fill" : "circle")
                                Text(viewModel.isReady ? "Ready!" : "Ready Up")
                            }
                        }
                        .buttonStyle(SCSecondaryButton())
                    }
                    .scCard()

                    // Participants
                    VStack(alignment: .leading, spacing: 4) {
                        Text("IN THE ROOM (\(appState.participants.count + (SCPreview.isActive ? 1 : 0)))")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                            .padding(.horizontal, 4)

                        ForEach(appState.participants) { p in
                            ParticipantRow(
                                avatar: p.avatar ?? "👤",
                                name: p.id == appState.myParticipantId ? "\(p.username) (You)" : p.username,
                                role: p.role,
                                isReady: p.isReady
                            )
                        }
                        // Preview only: the mock list doesn't include you. In real mode
                        // your participant row arrives via the shared subscription.
                        if SCPreview.isActive {
                            ParticipantRow(
                                avatar: viewModel.selectedAvatar,
                                name: appState.username.isEmpty ? "You" : appState.username,
                                role: viewModel.selectedRole,
                                isReady: viewModel.isReady
                            )
                        }
                    }

                    Button("Start Battle") { viewModel.start() }
                        .buttonStyle(SCPrimaryButton())
                        .disabled(!viewModel.isReady)
                        .opacity(viewModel.isReady ? 1 : 0.4)
                        .padding(.bottom, 8)
                }
                .padding(20)
            }
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct ParticipantRow: View {
    let avatar: String
    let name: String
    let role: ParticipantRole
    let isReady: Bool

    private var roleColor: Color {
        switch role {
        case .competitor: .orange
        case .judge: .green
        case .audience: .gray
        case .host: .yellow
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(avatar).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(role.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(roleColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(roleColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            Spacer()
            Image(systemName: isReady ? "checkmark.circle.fill" : "clock")
                .foregroundStyle(isReady ? .green : SCTheme.secondaryText)
                .font(.system(size: 20))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

#Preview {
    LobbyView()
        .environment(MockData.previewState())
}
