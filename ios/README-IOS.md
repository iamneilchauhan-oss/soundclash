# iOS app setup (SoundClash)

Xcode project scaffolding lives here. Because `.xcodeproj` files are generated,
create the project in Xcode once, then add the Swift sources as they're written.

## One-time setup

1. Xcode → New → App → **SoundClash**, SwiftUI, Swift, iOS 17+ deployment target.
2. Add this folder structure inside the project (Groups, matching disk layout):
   ```
   SoundClash/
     App/            SoundClashApp.swift, AppState.swift
     Features/
       Menu/         MenuView.swift
       JoinHost/     JoinHostView.swift
       Lobby/        LobbyView.swift
       Matchup/      MatchupView.swift
       CoinToss/     CoinTossView.swift
       Battle/       BattleView.swift (+ JudgeBattleView, PlayerBattleView)
       Voting/       VotingView.swift
       Results/     ResultsView.swift
     Core/
       Models/       Room.swift, Participant.swift, Round.swift, Play.swift, Vote.swift
       Music/        MusicProvider.swift (protocol), AppleMusicProvider.swift
       Sync/         SyncEngine.swift   (play-at-timestamp + drift correction)
       Voice/        VoiceService.swift (LiveKit wrapper)
       Backend/      SupabaseService.swift, TokenService.swift
   ```
3. Swift Package dependencies (File → Add Package):
   - LiveKit: `https://github.com/livekit/client-sdk-swift`
   - Supabase: `https://github.com/supabase/supabase-swift`
4. Signing & Capabilities → Background Modes → **Audio, AirPlay, and Picture in Picture**.
5. `Info.plist` keys:
   - `NSAppleMusicUsageDescription` — "SoundClash plays battle tracks from your Apple Music subscription."
   - `NSMicrophoneUsageDescription` — "SoundClash uses your mic so competitors and judges can talk live."
6. No MusicKit entitlement needed (Apple DTS: MusicKit is not entitlement-gated) —
   just `import MusicKit` and request authorization at runtime.

## What talks to what

```
SwiftUI views
  → ViewModels (per feature, @Observable)
    → SupabaseService   (rooms, participants, rounds, plays, votes — realtime)
    → SyncEngine        (converts play.started_at → local seek; heartbeat re-sync)
    → MusicProvider     (AppleMusicProvider now; SpotifyProvider later)
    → VoiceService      (LiveKit room; token from token-service)
```

## Build order

1. Models + SupabaseService (rooms/lobby working, no music yet)
2. The 8 screens as navigable SwiftUI (mock data first)
3. AppleMusicProvider + SyncEngine (real synced playback — Spike A)
4. VoiceService + ducking (Spike B, needs device)
5. Voting + results wiring
