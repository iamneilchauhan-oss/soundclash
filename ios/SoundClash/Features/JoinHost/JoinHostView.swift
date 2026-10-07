import SwiftUI

@Observable
@MainActor
final class JoinHostViewModel {
    var appState: AppState!
    var username = ""
    var roomCode = ""

    private let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    func configure(_ state: AppState) {
        appState = state
        if username.isEmpty {
            username = UserDefaults.standard.string(forKey: "soundclash.username") ?? ""
        }
    }

    private func rememberUsername(_ name: String) {
        UserDefaults.standard.set(name, forKey: "soundclash.username")
    }

    var canJoin: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && roomCode.trimmingCharacters(in: .whitespaces).count >= 4
    }

    var canHost: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func join() {
        guard canJoin else { return }
        let name = username.trimmingCharacters(in: .whitespaces)
        let code = roomCode.trimmingCharacters(in: .whitespaces).uppercased()
        rememberUsername(name)
        appState.username = name
        appState.roomCode = code
        guard !SCPreview.isActive else { appState.go(.lobby); return }
        // Real mode: validate the code against rooms, then insert this device's
        // participant row (role/avatar get finalized in the lobby).
        Task {
            do {
                let room = try await SupabaseService.shared.fetchRoom(code: code)
                let participant = try await SupabaseService.shared.joinRoom(
                    roomId: room.id, username: name, role: .audience, avatar: "👤"
                )
                appState.roomId = room.id
                appState.myParticipantId = participant.id
                appState.startFollowingRoom()
                appState.go(.lobby)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }

    func host() {
        guard canHost else { return }
        let name = username.trimmingCharacters(in: .whitespaces)
        rememberUsername(name)
        appState.username = name
        guard !SCPreview.isActive else {
            let code = String((0..<6).map { _ in codeAlphabet.randomElement()! })
            appState.roomCode = code
            appState.go(.lobby)
            return
        }
        Task {
            do {
                let room = try await SupabaseService.shared.createRoom(title: "\(name)'s Battle")
                let participant = try await SupabaseService.shared.joinRoom(
                    roomId: room.id, username: name, role: .host, avatar: "👑"
                )
                appState.roomCode = room.code
                appState.roomId = room.id
                appState.myParticipantId = participant.id
                appState.startFollowingRoom()
                appState.go(.lobby)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }
}

struct JoinHostView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = JoinHostViewModel()
    @FocusState private var focusedField: Field?

    private enum Field { case username, code }

    private var accent: VerzuzTheme.Accent { VerzuzTheme.menuAccent }

    var body: some View {
        ZStack {
            VerzuzSplit(left: accent.color, right: .black)

            ScrollView {
                VStack(spacing: 20) {
                    Text("Who's battling?")
                        .font(VerzuzTheme.display(34))
                        .foregroundStyle(accent.onColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("USERNAME")
                            .font(VerzuzTheme.display(13))
                            .foregroundStyle(.white)
                        TextField("Pick a name", text: $viewModel.username)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .username)
                            .padding(14)
                            .background(.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROOM CODE")
                            .font(VerzuzTheme.display(13))
                            .foregroundStyle(.white)
                        TextField("e.g. KX7Q2M", text: $viewModel.roomCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .code)
                            .padding(14)
                            .background(.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                            .onChange(of: viewModel.roomCode) { _, new in
                                let filtered = new.uppercased().prefix(6)
                                if String(filtered) != new { viewModel.roomCode = String(filtered) }
                            }
                    }

                    Button("JOIN BATTLE") { viewModel.join() }
                        .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 22))
                        .disabled(!viewModel.canJoin)
                        .opacity(viewModel.canJoin ? 1 : 0.4)
                        .padding(.top, 8)

                    HStack(spacing: 12) {
                        Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.3))
                        Text("or").foregroundStyle(.white.opacity(0.7)).font(.caption)
                        Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.3))
                    }

                    Button("HOST A BATTLE") { viewModel.host() }
                        .buttonStyle(VerzuzButtonStyle(fill: accent.color, textColor: accent.onColor, fontSize: 22))
                        .disabled(!viewModel.canHost)
                        .opacity(viewModel.canHost ? 1 : 0.4)

                    Spacer()
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    JoinHostView()
        .environment(MockData.previewState())
}
