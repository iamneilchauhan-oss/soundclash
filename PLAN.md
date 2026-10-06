# Verzuz Battle App — Build Plan
*Personal clone of Stationhead with a competitive twist: remote Verzuz-style battles, 2 competitors, 3 judges. Portfolio project.*

## The core insight (steal this from Stationhead)

Stationhead never streams music itself and never needed label deals. Every listener plays from
**their own Apple Music subscription** — the app only syncs *what's playing*. The host's track picks go out as playback commands; the host's voice rides on top as live audio. Your clone should use this exact architecture:

- **Music channel:** each device plays locally from the user's own subscription. Your server sends *commands*, not audio: "play ISRC X, starting at server-time T."
- **Voice channel:** WebRTC for competitor + judge mics, mixed on-device with the local music.

This kills three birds: no music licensing problem, near-zero audio bandwidth cost, and dramatically better audio quality than Verzuz-on-Instagram-Live (which was literally a phone mic pointed at a speaker).

## Architecture decision (2026-10-05)

Evaluated a SharePlay (GroupActivities) alternative where the FaceTime call would carry voice and Apple's session would carry sync transport. Rejected: no turnkey MusicKit synced-playback API exists (each app wires its own coordination anyway), it would tie the product to FaceTime + iOS-only + every participant needing the app and an Apple Music sub, and reference implementations were unverified. Sticking with the default: own sync engine + LiveKit voice + Supabase backend, per below.

## UX flow (locked 2026-10-05 — mockups in artifact `verzuz-clone-mockups`)

8 cards: **Menu** (Play, Settings) → **Join/Host** (username, room code) → **Lobby**
(role: competitor/judge/audience, avatar, ready) → **Verzuz matchup select**
(Smash Bros-style, each competitor picks an artist, head-to-head artist art) →
**Coin toss** (who plays first) → **Live rounds** (judge view: song + spam-able
positive reacts; player view: song selection + private previews) → **Judge vote**
(red vs blue, live talk during deliberation) → **Winner card**.

## System parts

### 1. Auth + music linking (Apple Music only — scope decision 2026-10-05)

Native **MusicKit** framework. Requires a $99/yr Apple Developer account and per-user
auth tokens. The user needs an Apple Music subscription for full playback. Note: native
iOS MusicKit needs **no developer JWT in app code** — the system attaches it via the
app's signing automatically (verified 2026-10-05; the token service's `/v1/musickit-token`
endpoint is kept only for potential server-side catalog calls). Big win: playback
happens **in-app**, so you get full control of mixing/ducking. Spotify support is
explicitly out of scope.

### 2. Track identity layer
- Canonical key: **ISRC** (International Standard Recording Code), exposed by the Apple
  Music API on every song. Use it as the canonical track ID everywhere (plays, votes,
  cache) so matching stays exact even across remasters and re-releases.
- When a competitor picks a track, resolve and store the Apple Music song ID + ISRC +
  metadata at pick time (server-side, cached in `track_resolutions`).
- Fallbacks for the unhappy path: catalog miss → title+artist search → mark "unavailable"
  (Stationhead's infamous "Sad Bowie" screen) and skip gracefully.

### 3. Sync engine
- Server-authoritative play commands with server timestamps: `{ isrc, apple_music_id, start_at_server_time }`.
- Clients compute `position = now - start_at` and seek; periodic heartbeat re-syncs and drift correction (snap if drift > ~750ms).
- Target: everyone within ~1s. You don't need sample-accurate sync for a battle — you need "the drop hits at basically the same moment."
- Judges must hear both competitors' rounds under the same sync regime, or scoring feels unfair.

### 4. Live voice stage (WebRTC)
- **LiveKit** (recommended): open source (Apache 2.0), self-hostable, first-party iOS SDK, generous free cloud tier. Agora/Daily are fine managed alternatives but worse portfolio stories.
- Roles: 2 competitors (mic + track control on their turn), 3 judges (mic + vote), optional audience (listen-only). Mic priority/ducking handled client-side.
- Echo is the enemy: music on speakers + live mic = feedback. Require/recommend headphones; lean on WebRTC acoustic echo cancellation.

### 5. Battle state machine (server-authoritative)
- Room lifecycle: lobby → round N (competitor A plays → judges score → competitor B plays → judges score) → results.
- Per round: track pick → synced playback (e.g., 90-second clip or full track) → judge voting window (winner-pick or 1–10) → tally → next.
- Tie-break rules decided up front (e.g., sudden-death round, host decides).
- Transport: Supabase Realtime channels or raw websockets. All scoring writes go through the server — never trust client tallies.

### 6. Client app
- **iOS native (SwiftUI).** MusicKit is first-class on iOS. Native keeps the two hard problems
  (audio session management, background playback) tractable.
- iOS realities to handle: background audio mode, `AVAudioSession` mixing/ducking (in-app
  playback = full control when a judge talks), interruptions (phone calls), Bluetooth
  route changes, Now Playing info.

## Tricky problems, ranked by "will ruin your week"

1. **MusicKit auth plumbing.** Per-user auth flow + subscription-status checks. Get this wrong and nothing plays — it's the first thing to spike.
2. **Sync under real networks.** Jitter, backgrounded apps, Bluetooth latency (~200ms on some codecs). Heartbeat re-sync + drift thresholds, and never re-seek more often than ~5s or you'll cause audible stutter.
3. **Voice-over-music mixing.** In-app MusicKit playback gives full control — duck music when a judge talks, restore after. Test on device with LiveKit's echo cancellation.
4. **Legal/App Store.** The per-user-subscription model keeps you clean for a personal/portfolio build. Don't record mixes containing copyrighted music for redistribution. If you ever TestFlight it, MusicKit + a privacy policy are required.

## Suggested stack

| Layer | Pick | Why |
|---|---|---|
| Client | SwiftUI, iOS 17+ | MusicKit is first-class; full audio-session control |
| Voice | LiveKit (cloud free tier → self-host) | OSS, portfolio-friendly, iOS SDK |
| Backend | Supabase (Auth, Postgres, Realtime) | Rooms, votes, presence with minimal ops |
| Token service | Tiny Node service | LiveKit access tokens (native iOS MusicKit needs no in-app developer token) |
| Track metadata cache | Postgres table keyed by ISRC | Avoid repeat Apple Music API hits |

## Phased roadmap

**Phase 0 — Spikes (1–2 weeks, kill criteria attached)**
- Spike A: MusicKit auth + catalog search + play a track programmatically on a real device.
- Spike B: LiveKit voice room + local music playback with ducking on a real device.
- If either fails badly, redesign before writing app code.

**Phase 1 — MVP (4–6 weeks)**
- iOS, Apple Music only. Create/join room via code, role assignment (2 competitors, 3 judges), 5-round battle flow, per-round judge voting, synced playback, results screen. No audience yet (or listen-only without chat).

**Phase 2 — Polish (ongoing)**
- Audience + chat + reactions, battle history, shareable results cards, rematch flow.

## Portfolio framing (for the README)

Lead with: *"A Stationhead-style social listening room re-architected as a competitive battle system."* Brag about: the dual-channel architecture (commands-not-audio), the server-authoritative battle state machine, in-app MusicKit playback with live voice ducking, and why the design needs no music licensing. Demo video > screenshots: show two phones staying in sync while judges vote live.

## Open questions
- Full tracks or timed clips per round? (Clips = tighter battles, fewer licensing eyebrows, less dead air.)
- Does the host role exist separately, or is one judge the host?
- Audience in MVP or later? (Recommendation: later — it multiplies sync/QA surface.)
- Async mode (competitors submit rounds beforehand, judges score later)? Big scope — park it.
