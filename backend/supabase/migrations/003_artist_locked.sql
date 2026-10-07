-- 003: track matchup artist lock-in per competitor.
-- Picks sync live to artist_pick on every select; artist_locked marks "I'm done".
alter table participants add column artist_locked boolean not null default false;
