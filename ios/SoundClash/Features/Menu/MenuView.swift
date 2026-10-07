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
                try await MusicMode.provider.requestAuthorization()
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

    private var accent: VerzuzTheme.Accent { VerzuzTheme.menuAccent }

    var body: some View {
        ZStack {
            VerzuzSplit(left: accent.color, right: .black)

            VStack(spacing: 0) {
                HStack {
                    Text("SOUNDCLASH")
                        .font(VerzuzTheme.display(30))
                        .foregroundStyle(accent.onColor)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

                // V monogram straddling the split: black on the accent side,
                // accent on the black side.
                VMark(left: .black, right: accent.color)
                    .frame(width: 220, height: 220)

                Spacer()

                HStack(spacing: 14) {
                    Button { viewModel.play() } label: {
                        Text("PLAY")
                    }
                    .buttonStyle(VerzuzButtonStyle(fill: .black, textColor: .white, fontSize: 24))

                    Button {
                        // Placeholder — destination TBD.
                    } label: {
                        Text("PLACEHOLDER")
                    }
                    .buttonStyle(VerzuzButtonStyle(fill: accent.color, textColor: accent.onColor, fontSize: 24))
                }
                .padding(.horizontal, 24)

                HStack {
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(accent.color)
                            .padding(16)
                    }
                    .padding(.trailing, 8)
                }
                .padding(.bottom, 8)
            }
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
    @AppStorage("soundclash.demoMusicMode") private var demoMode = false
    @AppStorage("soundclash.testing.skipControls") private var skipControls = true

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
                    Section("Testing") {
                        Toggle("Demo tracks mode", isOn: $demoMode)
                        Text("Uses built-in demo tracks instead of Apple Music, so the full battle flow is testable before the MusicKit service is enabled.")
                            .font(.footnote)
                            .foregroundStyle(SCTheme.secondaryText)
                        Toggle("Battle skip controls", isOn: $skipControls)
                        Text("Shows End turn / Skip to voting buttons on the battle screen so you can force-advance the round while testing.")
                            .font(.footnote)
                            .foregroundStyle(SCTheme.secondaryText)
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
