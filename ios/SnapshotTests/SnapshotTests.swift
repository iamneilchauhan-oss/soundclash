import SwiftUI
import UIKit
import XCTest

@testable import SoundClash

/// Renders every screen in mock (SCPreview) mode and writes PNGs to
/// $SNAPSHOT_DIR. Runs on a macOS GitHub Actions runner; the workflow commits
/// the PNGs back to design/snapshots/ for the design gallery.
///
/// Mock mode is forced via the XCODE_RUNNING_FOR_PREVIEWS env var (set before
/// SCPreview.isActive is first read), so no network or device services are
/// touched — the renders are pure SwiftUI, exactly what the phone draws.
final class SnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
    }

    func testRenderAllScreens() throws {
        let dirPath = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? "/tmp/snapshots"
        let dir = URL(fileURLWithPath: dirPath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        render(AnyView(MenuView().environment(mockState())), named: "01-menu", in: dir)
        render(AnyView(SettingsSheet().environment(mockState())), named: "02-settings", in: dir)
        render(AnyView(JoinHostView().environment(mockState())), named: "03-join-host", in: dir)
        render(AnyView(LobbyView().environment(mockState())), named: "04-lobby", in: dir)
        render(AnyView(MatchupView().environment(mockState())), named: "05-matchup", in: dir)
        render(AnyView(CoinTossView().environment(mockState())), named: "06-coin-toss", in: dir)

        let playerState = mockState()
        playerState.myRole = .competitor
        render(AnyView(PlayerBattleView(round: 1).environment(playerState)), named: "07-battle-player", in: dir)

        let judgeState = mockState()
        judgeState.myRole = .judge
        render(AnyView(JudgeBattleView(round: 1).environment(judgeState)), named: "08-battle-judge", in: dir)

        render(AnyView(VotingView(round: 1).environment(mockState())), named: "09-voting", in: dir)

        let resultsState = mockState()
        resultsState.finalRoundWinner = .red
        render(AnyView(ResultsView().environment(resultsState)), named: "10-results", in: dir)
    }

    // MARK: - Helpers

    /// Mirrors MockData.previewState() with a test-appropriate username.
    private func mockState() -> AppState {
        let state = AppState()
        state.username = "Neil"
        state.myRole = .competitor
        state.roomCode = "KX7Q2M"
        state.participants = MockData.participants
        state.scoreboard = MockData.scoreboard
        return state
    }

    /// Hosts the view in a real window, spins the runloop so .task/configure
    /// blocks execute, then captures the layer tree to PNG.
    private func render(_ view: AnyView, named name: String, in dir: URL) {
        let work = {
            let size = CGSize(width: 390, height: 844)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = UIHostingController(rootView: view)
            window.makeKeyAndVisible()
            // Let SwiftUI attach, run .task blocks, and lay out.
            RunLoop.main.run(until: Date().addingTimeInterval(2.0))

            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let url = dir.appendingPathComponent("\(name).png")
            try! image.pngData()!.write(to: url)
            print("SNAPSHOT wrote \(url.path)")
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}
