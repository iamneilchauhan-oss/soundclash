import SwiftUI

@Observable
@MainActor
final class MenuViewModel {
    var appState: AppState!

    func configure(_ state: AppState) { appState = state }

    func play() {
        guard !SCPreview.isActive else { appState.go(.joinHost); return }
        // Fail fast: backend configured + Apple Music authorized before entering.
        Task {
            do {
                try SupabaseService.shared.checkConfigured()
                try await AppleMusicProvider.shared.requestAuthorization()
                appState.go(.joinHost)
            } catch {
                appState.backendError = error.localizedDescription
            }
        }
    }
}

struct MenuView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = MenuViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            SCTheme.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 8) {
                    Text("SOUNDCLASH")
                        .font(SCTheme.title(46))
                        .foregroundStyle(.white)
                    Text("Remote Verzuz battles")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(SCTheme.secondaryText)
                    Text("2 competitors · 3 judges · one winner")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(SCTheme.secondaryText.opacity(0.8))
                }

                Spacer()

                Button("Play") { viewModel.play() }
                    .buttonStyle(SCPrimaryButton())

                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                }
                .buttonStyle(SCSecondaryButton())
            }
            .padding(28)
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .alert("Couldn't continue", isPresented: Binding(
            get: { appState.backendError != nil },
            set: { if !$0 { appState.backendError = nil } }
        )) {
            Button("OK") { appState.backendError = nil }
        } message: {
            Text(appState.backendError ?? "")
        }
        .task { viewModel.configure(appState) }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Settings (mock)

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var appleMusicConnected = true
    @State private var notifications = false
    @State private var highQuality = true

    var body: some View {
        NavigationStack {
            ZStack {
                SCTheme.background.ignoresSafeArea()
                Form {
                    Section("Music") {
                        Toggle("Apple Music connected", isOn: $appleMusicConnected)
                            .disabled(true)
                            .task {
                                guard !SCPreview.isActive else { return }
                                appleMusicConnected = await AppleMusicProvider.shared.isAuthorized
                            }
                    }
                    Section("Preferences") {
                        Toggle("Battle notifications", isOn: $notifications)
                        Toggle("High quality audio", isOn: $highQuality)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    MenuView()
        .environment(MockData.previewState())
}
