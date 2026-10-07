import SwiftUI

@Observable
@MainActor
final class JoinHostViewModel {
    var appState: AppState!
    var username = ""
    var roomCode = ""

    private let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    func configure(_ state: AppState) { appState = state }

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

    var body: some View {
        ZStack {
            SCTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("Who's battling?")
                        .font(VerzuzTheme.display(30))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("USERNAME")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                        TextField("Pick a name", text: $viewModel.username)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .username)
                            .padding(14)
                            .background(SCTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ROOM CODE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(SCTheme.secondaryText)
                        TextField("e.g. KX7Q2M", text: $viewModel.roomCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .code)
                            .padding(14)
                            .background(SCTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .onChange(of: viewModel.roomCode) { _, new in
                                let filtered = new.uppercased().prefix(6)
                                if String(filtered) != new { viewModel.roomCode = String(filtered) }
                            }
                    }

                    Button("Join Battle") { viewModel.join() }
                        .buttonStyle(SCPrimaryButton())
                        .disabled(!viewModel.canJoin)
                        .opacity(viewModel.canJoin ? 1 : 0.4)
                        .padding(.top, 8)

                    HStack(spacing: 12) {
                        Rectangle().frame(height: 1).foregroundStyle(SCTheme.cardBorder)
                        Text("or").foregroundStyle(SCTheme.secondaryText).font(.caption)
                        Rectangle().frame(height: 1).foregroundStyle(SCTheme.cardBorder)
                    }

                    Button("Host a Battle") { viewModel.host() }
                        .buttonStyle(SCSecondaryButton())
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
