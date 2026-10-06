# SoundClash (working title)

A Stationhead-style social listening app re-architected as a competitive game: remote Verzuz battles with **2 competitors, 3 judges**, synced music playback, live voice, and round-by-round voting.

> Portfolio project. iOS-first (SwiftUI + MusicKit), own sync engine, LiveKit voice, Supabase backend.

## The idea in one paragraph

Every player streams music from **their own** Apple Music subscription — the server only sends playback *commands* ("play ISRC X at server-time T"), never audio. That means no music licensing, near-zero bandwidth, and way better quality than pointing a phone mic at a speaker. Voice (competitors + judges) rides over LiveKit WebRTC, mixed on-device with the local music.

## UX flow (mockups: `verzuz-clone-mockups` artifact)

1. **Menu** — Play, Settings
2. **Join / Host** — pick a username, enter a room code or host
3. **Lobby** — select role (competitor / judge / audience), avatar, ready up
4. **Verzuz matchup select** — Smash Bros-style: each competitor picks an artist, matchup displayed head-to-head with artist art
5. **Coin toss** — decides who plays first
6. **Live rounds** — judges see the song + spam-able positive react buttons; players get song selection + private previews
7. **Judge vote** — red vs blue, judges can talk live while deliberating
8. **Winner card** — end of battle results

## Repo layout

```
backend/
  supabase/migrations/   # Postgres schema: rooms, participants, rounds, plays, votes
  token-service/         # Tiny Node service: LiveKit access tokens (iOS MusicKit needs no in-app token)
ios/
  SoundClash/            # SwiftUI app (screens, view models, core services)
docs/
  PLAN.md                # Full technical plan
```

## Architecture

| Layer | Choice |
|---|---|
| Client | SwiftUI, iOS 17+ (MusicKit) |
| Voice | LiveKit (self-host or cloud) |
| Backend | Supabase (Auth, Postgres, Realtime) |
| Sync | Server-timestamped play commands, client drift correction (~1s tolerance) |
| Track identity | ISRC as cross-service key (Spotify `external_ids.isrc` ↔ Apple Music `filter[isrc]`), cached in `track_resolutions` |

## Status

- [x] Technical plan
- [x] UX mockups (8-card flow)
- [x] Backend schema + token service scaffold
- [ ] SwiftUI screens
- [ ] MusicKit playback + sync engine
- [ ] LiveKit voice + ducking (device spike)
- [ ] Judge voting + results wiring
