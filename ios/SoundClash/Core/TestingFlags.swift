import Foundation

/// Testing-only escape hatches. Toggle in Settings > Testing.
///
/// When `showSkipControls` is on, the battle screen shows an "End turn" and
/// a "Skip to voting" button so a lone tester can force-advance the round
/// state machine without waiting out full clips.
enum TestingFlags {
    private static let skipKey = "soundclash.testing.skipControls"

    static var showSkipControls: Bool {
        // Defaults ON while the app is in active solo testing — the toggle
        // in Settings > Testing can turn it off.
        get { UserDefaults.standard.object(forKey: skipKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: skipKey) }
    }
}
