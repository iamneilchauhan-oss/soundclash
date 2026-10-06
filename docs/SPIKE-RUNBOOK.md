# Device Spike Runbook — SoundClash

Do these on your iPhone after: Apple Developer enrollment, Xcode project created,
SPM packages added (supabase-swift, livekit-client), SCConfig filled in, Supabase
project created with both migrations run.

## Spike A — MusicKit (the "does music actually play" test)

1. Build & run on your physical iPhone (MusicKit does not work in Simulator).
2. You need an **Apple Music subscription** signed in on the device.
3. Tap through Menu → Host a battle → Lobby → ready up → Matchup → Coin toss → Battle.
4. As the player: search for a song, hit **Preview** — you should hear 30s through
   the phone speaker.
5. Hit **Play This Track** — the song should start. Watch the progress bar: it should
   move smoothly and roughly match what you hear.
6. **Pass criteria:** auth prompt appears once, search returns real Apple Music
   results, playback starts within ~2s, no crashes on background/foreground.
7. **Known traps:** first launch needs the MusicKit capability on the bundle ID;
   if search returns nothing, check the storefront (US default); Bluetooth adds
   ~200ms latency — test on speaker first, then AirPods.

## Spike B — Voice + ducking (the "can judges talk over music" test)

1. You need **two devices** (or one device + the Xcode preview on Mac won't cut it —
   use your iPhone + a friend's, or iPhone + iPad), both on the token service.
2. Deploy the token service somewhere reachable (Fly.io / Render / Tailscale to your Mac).
3. Both devices join the same room as judges. Start a battle round so music plays.
4. Unmute mic on device 2 and talk — on device 1 the **music should duck** while
   they speak and come back up after.
5. **Pass criteria:** voice is intelligible, music ducks (doesn't just keep blaring),
   no feedback squeal (use headphones if on speakerphone-style playback).
6. **Known traps:** iOS will not give you mic + speaker music without echo unless
   LiveKit's AEC is active — if you hear echo, that's the thing to tune, not the
   volume.

## Spike C — Sync (the "do two phones stay together" test)

1. Two devices, same room, both as audience/judges.
2. Player starts a track. On both devices, listen for the **first beat/drop**.
3. Clap test: they should land within ~1 second of each other. (Perfection isn't
   the goal — "the drop hits at basically the same moment" is.)
4. Background one phone mid-song, foreground it — it should re-sync within ~5s
   (that's the heartbeat), not restart the song.
5. **Pass criteria:** both phones audibly in sync; background/foreground recovers.

## Reporting back

For anything that fails, send: what you tapped, what you expected, what happened,
and any Xcode console output. That's the fastest path to a fix.
