import Foundation

/// Which music backend the app talks to.
///
/// Demo mode exists so the full battle flow (rounds, sync, voting) is
/// testable while the Apple Music catalog is unavailable — e.g. before the
/// MusicKit App Service is enabled for the bundle ID. Toggle it in
/// Settings > Testing. Delete DemoMusicProvider.swift once real catalog
/// testing begins.
enum MusicMode {
    private static let demoKey = "soundclash.demoMusicMode"

    static var useDemoTracks: Bool {
        get { UserDefaults.standard.bool(forKey: demoKey) }
        set { UserDefaults.standard.set(newValue, forKey: demoKey) }
    }

    @MainActor static var provider: any MusicProvider {
        useDemoTracks ? DemoMusicProvider.shared : AppleMusicProvider.shared
    }
}
