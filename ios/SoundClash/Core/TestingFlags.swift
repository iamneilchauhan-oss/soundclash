import Foundation

/// Testing-only escape hatches. Toggle in Settings > Testing.
///
/// When `showSkipControls` is on, the battle screen shows an "End turn" and
/// a "Skip to voting" button so a lone tester can force-advance the round
/// state machine without waiting out full clips.
enum TestingFlags {
    private static let skipKey = "soundclash.testing.skipControls"

    static var showSkipControls: Bool {
        get { UserDefaults.standard.bool(forKey: skipKey) }
        set { UserDefaults.standard.set(newValue, forKey: skipKey) }
    }
}
