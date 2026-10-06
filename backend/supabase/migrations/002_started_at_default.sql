-- 002_started_at_default.sql
-- Plays get their authoritative start timestamp from the DB server, so every
-- client syncs against the same clock. recordPlay() omits started_at and
-- Postgres stamps it; schedulePlay() can overwrite it with a future time for
-- countdown-style drops.

alter table plays alter column started_at set default now();
