-- SoundClash initial schema
-- Run in Supabase SQL editor (or `supabase db push`).
-- Rooms, participants (2 competitors / 3 judges / audience), rounds, plays, votes,
-- plus an ISRC-keyed track metadata cache.

-- ---------- rooms ----------
create table rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,                       -- 6-char join code, generated app-side
  title text not null default 'Untitled Battle',
  status text not null default 'lobby',            -- lobby | matchup | coin_toss | live | voting | finished
  rounds_total int not null default 5,
  clip_seconds int not null default 90,
  current_round int not null default 0,
  created_at timestamptz not null default now()
);

-- ---------- participants ----------
create table participants (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms(id) on delete cascade,
  username text not null,
  role text not null,                              -- host | competitor | judge | audience
  avatar text,                                     -- emoji or asset name
  artist_pick text,                                -- competitors: chosen artist for the matchup screen
  is_ready boolean not null default false,
  created_at timestamptz not null default now()
);
create index participants_room_idx on participants(room_id);

-- ---------- rounds ----------
create table rounds (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms(id) on delete cascade,
  round_number int not null,
  first_player_id uuid references participants(id),
  status text not null default 'pending',          -- pending | playing | voting | done
  winner_id uuid references participants(id),
  created_at timestamptz not null default now(),
  unique(room_id, round_number)
);

-- ---------- plays ----------
-- One row per competitor's song per round. started_at is the server timestamp
-- clients sync against: position = now - started_at.
create table plays (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references rounds(id) on delete cascade,
  player_id uuid not null references participants(id),
  isrc text not null,
  apple_music_id text not null,
  title text not null,
  artist text not null,
  artwork_url text,
  started_at timestamptz,                          -- set when the host starts playback
  created_at timestamptz not null default now()
);
create index plays_round_idx on plays(round_id);

-- ---------- votes ----------
create table votes (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references rounds(id) on delete cascade,
  judge_id uuid not null references participants(id),
  voted_for_id uuid not null references participants(id),  -- red side or blue side competitor
  created_at timestamptz not null default now(),
  unique(round_id, judge_id)                        -- one vote per judge per round
);

-- ---------- track_resolutions ----------
-- ISRC-keyed metadata cache: resolve once via the Apple Music API, reuse forever.
create table track_resolutions (
  isrc text primary key,
  apple_music_id text not null,
  title text,
  artist text,
  artwork_url text,
  resolved_at timestamptz not null default now()
);

-- ---------- realtime ----------
-- Supabase Realtime: subscribe to per-room changes.
alter publication supabase_realtime add table rooms;
alter publication supabase_realtime add table participants;
alter publication supabase_realtime add table rounds;
alter publication supabase_realtime add table plays;
alter publication supabase_realtime add table votes;

-- ---------- row level security ----------
-- Prototype-open policies. Tighten before any public TestFlight:
-- scope reads/writes to the participant's own room via a room-membership check.
alter table rooms enable row level security;
alter table participants enable row level security;
alter table rounds enable row level security;
alter table plays enable row level security;
alter table votes enable row level security;
alter table track_resolutions enable row level security;

create policy "prototype: open read"  on rooms              for select using (true);
create policy "prototype: open write" on rooms              for all using (true) with check (true);
create policy "prototype: open read"  on participants       for select using (true);
create policy "prototype: open write" on participants       for all using (true) with check (true);
create policy "prototype: open read"  on rounds             for select using (true);
create policy "prototype: open write" on rounds             for all using (true) with check (true);
create policy "prototype: open read"  on plays              for select using (true);
create policy "prototype: open write" on plays              for all using (true) with check (true);
create policy "prototype: open read"  on votes              for select using (true);
create policy "prototype: open write" on votes              for all using (true) with check (true);
create policy "prototype: open read"  on track_resolutions  for select using (true);
create policy "prototype: open write" on track_resolutions  for all using (true) with check (true);
