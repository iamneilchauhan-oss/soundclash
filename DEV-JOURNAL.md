# SoundClash Dev Journal

*Running log of how this app got built — the product bets, the decisions, and
what it's like building as a PM with an AI eng team. Written for future-me:
interviews, portfolio write-ups, talks.*

---

## Day 1 — 2026-10-05: From idea to working scaffold in one day

### The hypothesis

**Product bet:** Stationhead proved people want to listen to music together
remotely. Verzuz proved people want to watch artists battle. Nobody's combined
them into a competitive product ordinary people can run themselves: two friends
pick tracks head-to-head, three judges vote live, everyone remote. That's
SoundClash.

**Enabling insight (the thing I'd lead with in an interview):** Stationhead
never streams music itself and never needed label deals. Every listener plays
from their own subscription — the app only syncs *what's playing*. I stole that
architecture wholesale: my server sends *commands*, not audio ("play this
track at server-time T"). Three consequences that make the product viable: no
music licensing problem, near-zero audio bandwidth cost, and better audio
quality than Verzuz-on-Instagram-Live (a phone mic pointed at a speaker).

**What would kill it:** if synced playback across devices couldn't be built
simply, or if music licensing turned out to be unavoidable. Both got answered
on day one — the architecture sidesteps licensing by construction, and the
sync design only needs "the drop hits at basically the same moment," not
sample-accurate sync.

### Building with AI: how we work

I'm the founder/PM; Lucifer (my AI agent) is the entire eng team. The split:

- **I own:** the product idea, every scope and architecture decision, UX flow,
  Xcode project setup, device builds, on-device QA.
- **Lucifer owns:** all code, backend provisioning, docs, debugging. I pull a
  fresh zip from Drive and rebuild.

What that felt like on day one: I made roughly ten product decisions in a few
hours (listed below) and each one turned into working infrastructure or code
within the hour — no sprint planning, no estimates, no handoffs. The
constraint that replaced all of that was **decision quality**: the agent
executes whatever I decide, so vague decisions produce vague systems. Locking
the 8-card UX flow before any code existed was the highest-leverage thing I
did today.

Operational lesson, learned the hard way: **delete the old `verzuz-clone`
folder before unzipping the new build** — macOS appends timestamps to
re-unzipped files and breaks Xcode's file references. Info.plist keys live
outside that folder, so deleting is safe. If reference errors linger after a
clean re-unzip + clean build, restart Xcode.

### What I stood up today (real infra, ~$0 + the $99 dev account)

Everything below is live on free tiers — a deliberate choice: prove the
product before spending on infra.

- **Supabase** project `soundclash` (us-west-2): auth, Postgres, realtime —
  rooms, votes, presence with minimal ops
- **LiveKit Cloud** project `soundclash` (US region): voice channel for
  competitors + judges
- **Token service** on Render free tier:
  `https://soundclash-token-service.onrender.com` — mints LiveKit access tokens
- **GitHub** repo `iamneilchauhan-oss/soundclash` (one-time access token
  revoked after push)
- **Apple Developer** enrollment submitted ($99); portal pending ~48h
  activation, then I enable the MusicKit App Service on the App ID
- **iOS scaffold** (SwiftUI, iOS 17+): the full 8-card flow, sync engine,
  voice service, backend clients
- **Demo mode** (Settings > Testing): 6 on-device synthesized tracks so the
  entire battle flow is testable *before* Apple's MusicKit service is enabled —
  a product decision to unblock testing, not just an eng convenience. It gets
  deleted once real catalog testing begins.

### Decisions I made today

1. **Apple Music only; Spotify out.** SDK complexity wasn't worth it for an
   MVP, and MusicKit is first-class on iOS. Scope discipline on day one.
2. **No SharePlay.** Evaluated it, rejected it: no turnkey synced-playback API
   exists, and it would have tied the product to FaceTime calls + iOS-only +
   every participant needing the app and a subscription. Own sync engine
   instead.
3. **Sync target ~1 second, not sample-accurate.** Server sends play commands
   with server timestamps; clients self-correct, re-syncing if drift passes
   ~750ms. A battle needs shared *moments*, not shared *samples*.
4. **ISRC as canonical track identity** — survives remasters and re-releases.
   Unhappy path gets a graceful "unavailable" screen (Stationhead's infamous
   "Sad Bowie").
5. **All scoring server-side.** Never trust client tallies — the battle state
   machine is authoritative.
6. **UX flow locked before code:** Menu → Join/Host → Lobby → artist matchup
   (Smash Bros-style) → coin toss → live rounds → judge vote → winner card.
7. **Spike-first on the two riskiest unknowns:** (A) does a real track actually
   play via MusicKit on a physical device, (B) can judges talk over music with
   live ducking across two devices. Wrote a runbook with pass criteria for
   both before building further.

### Things I learned today

- **My biggest assumed cost didn't exist.** I expected to build a token service
  for MusicKit auth; turns out native iOS MusicKit needs no developer JWT in
  app code — the system attaches it via app signing. An hour of verification
  killed a whole service. (Kept one endpoint for potential server-side catalog
  calls.)
- **Solo-test your two-player flows.** First solo pass exposed an infinite
  loop: my pick mapped to the wrong side, so the round never completed. Fix:
  the lone competitor takes the red corner, plus a demo-only "simulate
  opponent" button. Found it in minutes because demo mode existed.
- **Match test fixtures to test parameters.** Demo tracks were 20s; the clip
  length was 90s. Small mismatch, confusing results — lengthened tracks to 30s.
- **Surface backend errors in the UI.** A denied Apple Music permission failed
  silently and I stared at a dead app. Errors on the menu screen now.

*(Deeper technical notes — Swift 6 concurrency patterns, LiveKit 2.x SDK
quirks — live in the repo and plan, not here.)*

### References to keep

- **Mockups (early):** artifact `verzuz-clone-mockups` — the 8-card flow as
  first designed; compare against the shipped UI as it evolves
- **Plan:** `PLAN.md` — architecture, phased roadmap, portfolio framing
- **Spike runbook:** `docs/SPIKE-RUNBOOK.md` — pass criteria for the two
  riskiest unknowns
- **Repo:** `github.com/iamneilchauhan-oss/soundclash`
- **Token service:** `https://soundclash-token-service.onrender.com`

### What's next

1. Dev portal activates (~48h) → enable MusicKit App Service → rebuild on iPhone
2. Spike A: real track playback (device only — MusicKit doesn't work in Simulator)
3. Spike B: two-device voice + music ducking
4. TestFlight for 2-player friend testing (demo mode means no Apple Music
   needed on either device)

### Open questions (parked)

- Full tracks or timed clips per round?
- Separate host role, or is one judge the host?
- Audience in MVP or later? (Leaning later — multiplies sync/QA surface.)
- Async mode (submit rounds beforehand, judges score later)? Big scope — parked.

---
