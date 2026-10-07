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

    var isBusy = false

    /// Backend stalls get one transparent retry before surfacing an error.
    private static let maxAttempts = 2
    private static let attemptTimeout: Double = 15
    private var operationGeneration = 0

    func join() {
        guard canJoin, !isBusy else { return }
        let name = username.trimmingCharacters(in: .whitespaces)
        let code = roomCode.trimmingCharacters(in: .whitespaces).uppercased()
        rememberUsername(name)
        appState.username = name
        appState.roomCode = code
        appState.amHost = false
        guard !SCPreview.isActive else { appState.go(.lobby); return }
        // Real mode: validate the code against rooms, then insert this device's
        // participant row (role/avatar get finalized in the lobby).
        attemptJoin(name: name, code: code, attempt: 1)
    }

    private func attemptJoin(name: String, code: String, attempt: Int) {
        operationGeneration += 1
        let generation = operationGeneration
        isBusy = true
        let work = Task { @MainActor in
            do {
                let room = try await SupabaseService.shared.fetchRoom(code: code)
                let participant = try await SupabaseService.shared.joinRoom(
                    roomId: room.id, username: name, role: .audience, avatar: ""
                )
                guard generation == self.operationGeneration else { return }
                appState.roomId = room.id
                appState.myParticipantId = participant.id
                appState.startFollowingRoom()
                appState.go(.lobby)
            } catch {
                guard generation == self.operationGeneration else { return }
                if Task.isCancelled { return }
                appState.backendError = error.localizedDescription
            }
            if generation == self.operationGeneration { isBusy = false }
        }
        // Watchdog: a hung backend call retries once, then surfaces a timeout.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.attemptTimeout))
            guard !work.isCancelled, generation == self.operationGeneration, isBusy else { return }
            work.cancel()
            if attempt < Self.maxAttempts {
                self.attemptJoin(name: name, code: code, attempt: attempt + 1)
            } else {
                isBusy = false
                appState.backendError = BackendError.timedOut.localizedDescription
            }
        }
    }

    func host() {
        guard canHost, !isBusy else { return }
        let name = username.trimmingCharacters(in: .whitespaces)
        rememberUsername(name)
        appState.username = name
        appState.amHost = true
        guard !SCPreview.isActive else {
            let code = String((0..<6).map { _ in codeAlphabet.randomElement()! })
            appState.roomCode = code
            appState.go(.lobby)
            return
        }
        attemptHost(name: name, attempt: 1)
    }

    private func attemptHost(name: String, attempt: Int) {
        operationGeneration += 1
        let generation = operationGeneration
        isBusy = true
        let work = Task { @MainActor in
            do {
                let room = try await SupabaseService.shared.createRoom(title: "\(name)'s Battle")
                let participant = try await SupabaseService.shared.joinRoom(
                    roomId: room.id, username: name, role: .competitor, avatar: ""
                )
                guard generation == self.operationGeneration else { return }
                appState.roomCode = room.code
                appState.roomId = room.id
                appState.myParticipantId = participant.id
                appState.startFollowingRoom()
                appState.go(.lobby)
            } catch {
                guard generation == self.operationGeneration else { return }
                if Task.isCancelled { return }
                appState.backendError = error.localizedDescription
            }
            if generation == self.operationGeneration { isBusy = false }
        }
        // Watchdog: a hung backend call retries once, then surfaces a timeout.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.attemptTimeout))
            guard !work.isCancelled, generation == self.operationGeneration, isBusy else { return }
            work.cancel()
            if attempt < Self.maxAttempts {
                self.attemptHost(name: name, attempt: attempt + 1)
            } else {
                isBusy = false
                appState.backendError = BackendError.timedOut.localizedDescription
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
            Color.black.ignoresSafeArea()


            ScrollView {
                VStack(spacing: 20) {
                    Text("Who's battling?")
                        .font(VerzuzTheme.display(34))
                        .foregroundStyle(.white)
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
                            .background(Color.white.opacity(0.1))
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
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                            .onChange(of: viewModel.roomCode) { _, new in
                                let filtered = new.uppercased().prefix(6)
                                if String(filtered) != new { viewModel.roomCode = String(filtered) }
                            }
                    }

                    Button("JOIN BATTLE") { viewModel.join() }
                        .buttonStyle(VerzuzButtonStyle(fill: accent.color, textColor: accent.onColor, fontSize: 22))
                        .disabled(!viewModel.canJoin || viewModel.isBusy)
                        .opacity(viewModel.canJoin && !viewModel.isBusy ? 1 : 0.4)
                        .padding(.top, 8)

                    HStack(spacing: 12) {
                        Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.3))
                        Text("or").foregroundStyle(.white.opacity(0.7)).font(.caption)
                        Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.3))
                    }

                    Button("HOST A BATTLE") { viewModel.host() }
                        .buttonStyle(VerzuzButtonStyle(fill: .white.opacity(0.12), textColor: .white, fontSize: 22))
                        .disabled(!viewModel.canHost || viewModel.isBusy)
                        .opacity(viewModel.canHost && !viewModel.isBusy ? 1 : 0.4)

                    Spacer()
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)

            if viewModel.isBusy {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
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

#Preview {
    JoinHostView()
        .environment(MockData.previewState())
}
