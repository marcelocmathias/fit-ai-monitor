-- ============================================================================
-- Fit AI Monitor - complete setup for a NEW Supabase project
--
-- Paste this whole file into Supabase -> SQL Editor -> New query, and press Run.
-- Once, on an empty project. It is generated from the numbered files in this
-- folder (01, 03, 04, 05 + new_user_seed.sql) by build_setup.py - edit those,
-- not this.
--
-- Cole este arquivo inteiro em Supabase -> SQL Editor -> New query e clique em
-- Run. Uma vez só, num projeto vazio.
-- ============================================================================


-- >>>>>>>>>>>>>>>>>>>> 01_schema.sql >>>>>>>>>>>>>>>>>>>>

-- ============================================================================
-- Segments — schema
-- Run in the Supabase SQL Editor, once, on a fresh project.
--
-- Two writers meet here:
--   the watch  writes sessions + segments          (objective: time, heart rate)
--   Claude     writes segment_exercises + sets     (subjective: what, how heavy)
-- They join on (session_id, ordinal). Neither needs the other's data to write.
-- ============================================================================

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Reference
-- ---------------------------------------------------------------------------

create table gyms (
  id         text primary key,
  name       text not null,
  lat        double precision,
  lon        double precision,
  radius_m   integer not null default 300,
  notes      text,
  is_fallback boolean not null default false,   -- "Other": never suggested by GPS
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- The four-day cycle, plus core as an off-cycle type.
create table workout_types (
  id          text primary key,
  cycle_order integer unique,                   -- null = off-cycle (core)
  active      boolean not null default true
);

create table exercises (
  id           text primary key,
  load_type    text not null
    check (load_type in ('plate_per_side','stack','dumbbell','barbell','bodyweight','other')),
  muscle_group text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

-- One table doing two jobs: translation AND alias resolution.
-- A canonical row per (entity, entity_id, lang); any number of alias rows.
create table labels (
  id        bigserial primary key,
  entity    text not null check (entity in ('exercise','gym','workout_type','hr_zone')),
  entity_id text not null,
  lang      text not null check (lang in ('en','pt')),
  text      text not null,
  is_alias  boolean not null default false
);

create unique index labels_canonical_uniq
  on labels (entity, entity_id, lang) where is_alias = false;
create index labels_lookup on labels (lower(text));
create index labels_entity on labels (entity, entity_id);

-- Boundaries live here so changing your mind is a row update, not a release.
-- Seeded with Samsung Health's values (derived from a 177 bpm max), which the
-- watch design adopted so both screens agree.
create table hr_zones (
  idx     smallint primary key check (idx between 1 and 5),
  min_bpm smallint not null,
  max_bpm smallint not null,
  colour  text not null
);

-- ---------------------------------------------------------------------------
-- Written by the WATCH (via the phone). Objective, automatic.
-- ---------------------------------------------------------------------------

create table sessions (
  id              uuid primary key default uuid_generate_v4(),
  started_at      timestamptz not null,
  ended_at        timestamptz,
  gym_id          text not null references gyms(id),
  workout_type_id text not null references workout_types(id),

  duration_ms     bigint,
  avg_hr          smallint,
  max_hr          smallint,
  calories_kcal   integer,

  -- Downsampled to one sample every 5s: [[offset_ms, bpm], ...]
  -- ~900 numbers for a 75-minute session. For charts and the Health Connect write;
  -- never queried beat by beat.
  hr_series       jsonb,
  -- Milliseconds per zone, precomputed on the watch: {"1": 960000, "2": 1980000, ...}
  zone_ms         jsonb,

  device          text,
  testing         boolean not null default false,
  created_at      timestamptz not null default now(),

  constraint sessions_ends_after_start check (ended_at is null or ended_at >= started_at)
);

create index sessions_started on sessions (started_at desc);
create index sessions_gym on sessions (gym_id, started_at desc);

create table segments (
  id           bigserial primary key,
  session_id   uuid not null references sessions(id) on delete cascade,

  -- ANONYMOUS. Segment 4 is "the fourth block of time", nothing more.
  ordinal      integer not null,
  kind         text not null default 'strength'
    check (kind in ('strength','core','aerobic')),

  started_at   timestamptz not null,
  ended_at     timestamptz,
  duration_ms  bigint,
  -- Long-press Next reopens the previous segment, so a segment can span visits.
  visit_count  smallint not null default 1,

  avg_hr       smallint,
  max_hr       smallint,
  min_hr       smallint,

  unique (session_id, ordinal)
);

create index segments_session on segments (session_id, ordinal);

-- ---------------------------------------------------------------------------
-- Written by CLAUDE from chat. Subjective, after the fact.
-- ---------------------------------------------------------------------------

create table segment_exercises (
  segment_id  bigint not null references segments(id) on delete cascade,
  exercise_id text not null references exercises(id),
  position    smallint not null default 1,       -- 2 = the paired/antagonist movement
  primary key (segment_id, exercise_id)
);

create table sets (
  id          bigserial primary key,
  segment_id  bigint not null references segments(id) on delete cascade,
  exercise_id text not null references exercises(id),
  set_index   smallint not null,
  load        numeric(6,2),
  load_type   text
    check (load_type is null or load_type in
      ('plate_per_side','stack','dumbbell','barbell','bodyweight','other')),
  reps        smallint,
  rpe         numeric(3,1),
  note        text,
  unique (segment_id, exercise_id, set_index)
);

create index sets_exercise on sets (exercise_id);

create table session_notes (
  session_id uuid primary key references sessions(id) on delete cascade,
  body       text not null,
  written_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Views — what Claude actually reads
--
-- Every view sets security_invoker = on. Without it a Postgres view runs with
-- the *creator's* privileges and quietly bypasses RLS on the tables beneath it,
-- which makes the views a hole straight through everything in the RLS section
-- below. Do not remove this from any view added later.
-- ---------------------------------------------------------------------------

-- One row per session, in whatever language you are speaking.
create view v_sessions_en with (security_invoker = on) as
select s.id, s.started_at, s.ended_at,
       wl.text as workout, gl.text as gym,
       round(s.duration_ms / 60000.0)::int as minutes,
       s.avg_hr, s.max_hr, s.calories_kcal,
       (select count(*) from segments g where g.session_id = s.id) as segments,
       s.testing
from sessions s
  join gyms gy on gy.id = s.gym_id
  left join labels gl on gl.entity = 'gym'  and gl.entity_id = s.gym_id
       and gl.lang = 'en' and gl.is_alias = false
  left join labels wl on wl.entity = 'workout_type' and wl.entity_id = s.workout_type_id
       and wl.lang = 'en' and wl.is_alias = false;

-- The useful habit: sessions the watch recorded that were never described.
create view v_unannotated_sessions with (security_invoker = on) as
select s.id, s.started_at, s.workout_type_id, s.gym_id,
       count(g.id) as strength_segments,
       round(max(g.duration_ms) / 60000.0, 1) as longest_segment_min
from sessions s
  join segments g on g.session_id = s.id and g.kind = 'strength'
  left join segment_exercises se on se.segment_id = g.id
where se.segment_id is null and s.testing = false
group by s.id, s.started_at, s.workout_type_id, s.gym_id
order by s.started_at desc;

-- Load history for one exercise at one gym — the question asked most often.
create view v_load_history with (security_invoker = on) as
select st.exercise_id, s.gym_id, s.started_at,
       st.set_index, st.load, st.load_type, st.reps, st.note
from sets st
  join segments g on g.id = st.segment_id
  join sessions s on s.id = g.session_id
where s.testing = false
order by s.started_at desc, st.set_index;

-- ---------------------------------------------------------------------------
-- Row level security
--
-- Single-user project. Everything requires an authenticated session; sign-ups
-- are disabled in the dashboard so exactly one user can ever exist. The phone
-- app signs in once with the publishable key and holds a refresh token.
-- The Claude connector authenticates as you (project owner) and is unaffected.
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'gyms','workout_types','exercises','labels','hr_zones',
    'sessions','segments','segment_exercises','sets','session_notes'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format(
      'create policy %I on %I for all to authenticated using (true) with check (true)',
      t || '_authenticated', t);
  end loop;
end $$;

-- Supabase grants `anon` broad access to the public schema by default. RLS
-- neutralises that for tables, but the app always signs in, so `anon` has no
-- legitimate use here at all. Revoke it outright rather than relying on policy
-- coverage — including for tables added later.
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;

-- >>>>>>>>>>>>>>>>>>>> 03_history.sql >>>>>>>>>>>>>>>>>>>>

-- ============================================================================
-- Fit AI Monitor — set history that predates the app
-- Run after 01_schema.sql and 02_seed.sql. Safe to re-run.
--
-- The original schema hung every set off a segment, and every segment off a
-- session the watch recorded. That is right for anything trained from now on,
-- but it has no room for the years already written down in the memory files:
-- "40kg → 50kg em pirâmide, academia X, 2026-01-15" has no session, no segment
-- and no heart rate, and inventing them to satisfy a foreign key would put
-- fabricated sessions in the same table as real ones.
--
-- So a set now carries its own date and gym, and the links to a segment and a
-- session become optional. A set from the watch has all four; an imported one
-- has the two that are true.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Make the session link optional, and let a set stand on its own
-- ---------------------------------------------------------------------------

alter table sets alter column segment_id drop not null;

alter table sets
  add column if not exists session_id   uuid references sessions(id) on delete cascade,
  add column if not exists gym_id       text references gyms(id),
  add column if not exists performed_at timestamptz,
  add column if not exists raw          text,
  add column if not exists source       text not null default 'session';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sets_source_check') then
    alter table sets add constraint sets_source_check
      check (source in ('session', 'imported', 'chat'));
  end if;
end $$;

comment on column sets.raw is
  'Exactly as it was written down: "40kg → 50kg em pirâmide". The parsed number '
  'goes in load; this is what survives a bad parse.';
comment on column sets.source is
  'session = logged against a watch session; chat = added in conversation with '
  'no session; imported = migrated from the markdown memory files.';

-- Backfill anything already recorded, then make the two facts mandatory.
update sets st
set performed_at = coalesce(st.performed_at, s.started_at),
    gym_id       = coalesce(st.gym_id, s.gym_id),
    session_id   = coalesce(st.session_id, s.id)
from segments g join sessions s on s.id = g.session_id
where g.id = st.segment_id and st.performed_at is null;

alter table sets alter column performed_at set not null;
alter table sets alter column gym_id       set not null;

-- A set is either tied to a segment, or it is standing on its own with a
-- source that says why. This is what stops an orphan appearing by accident.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sets_linked_or_sourced') then
    alter table sets add constraint sets_linked_or_sourced
      check (segment_id is not null or source in ('imported', 'chat'));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Idempotent import
--
-- A migration of years of history WILL be run more than once - it will stop
-- half way, or a batch will be wrong and need redoing. Without a natural key
-- the second run silently doubles the history, and nothing downstream can tell
-- a duplicated load from a genuinely repeated one.
-- ---------------------------------------------------------------------------

alter table sets add column if not exists import_key text;

create unique index if not exists sets_import_key_uniq
  on sets (import_key) where import_key is not null;

comment on column sets.import_key is
  'Stable natural key for migrated rows: exercise|gym|date|raw. Re-running the '
  'import updates instead of duplicating.';

create index if not exists sets_exercise_gym_date
  on sets (exercise_id, gym_id, performed_at desc);

-- ---------------------------------------------------------------------------
-- The view rewritten against the set itself
-- ---------------------------------------------------------------------------

drop view if exists v_load_history;

create view v_load_history with (security_invoker = on) as
select st.exercise_id,
       st.gym_id,
       st.performed_at::date as performed_on,
       st.set_index,
       st.load,
       st.load_type,
       st.reps,
       st.raw,
       st.note,
       st.source,
       st.session_id is not null as from_session
from sets st
  left join sessions s on s.id = st.session_id
where coalesce(s.testing, false) = false
order by st.performed_at desc, st.set_index;

comment on view v_load_history is
  'Every set ever, imported or recorded, newest first. Always filter by gym: '
  'the same exercise does not carry the same number in two places.';

-- The last thing lifted on each exercise at each gym - the question asked most.
create or replace view v_last_load with (security_invoker = on) as
select distinct on (exercise_id, gym_id)
       exercise_id, gym_id, performed_on, load, load_type, reps, raw
from v_load_history
order by exercise_id, gym_id, performed_on desc, set_index desc;

-- ---------------------------------------------------------------------------
-- Notes
--
-- A session summary and a per-block note, both written by Claude from chat.
-- `segments.note` is safe from the watch: its upsert sends only the columns it
-- owns (timing and heart rate), so a re-sync cannot wipe what was written here.
-- ---------------------------------------------------------------------------

alter table segments add column if not exists note text;

comment on column segments.note is
  'What happened in this block, written by Claude from chat.';
comment on table session_notes is
  'One free-text summary per session, written by Claude from chat.';

-- >>>>>>>>>>>>>>>>>>>> 04_motion.sql >>>>>>>>>>>>>>>>>>>>

-- Work and rest, measured on the wrist.
--
-- Additive only: every column is nullable with a zero default, because these
-- come from the accelerometer rather than from anything the user pressed. A
-- session recorded before this existed, or on a watch whose accelerometer could
-- not be registered, reports zero rather than lying about having measured.
--
-- rest_ms + work_ms deliberately does not have to equal duration_ms: a stretch
-- shorter than the detector's dwell belongs to neither, and the difference is
-- itself a useful signal about how well the detection is working.

alter table public.sessions
  add column if not exists rest_ms bigint not null default 0,
  add column if not exists work_ms bigint not null default 0;

alter table public.segments
  add column if not exists rest_ms bigint not null default 0,
  add column if not exists work_ms bigint not null default 0,
  add column if not exists work_bouts integer not null default 0;

comment on column public.segments.rest_ms is
  'Wrist still for 20s or more. Estimated from the accelerometer, not pressed.';
comment on column public.segments.work_bouts is
  'Stretches of movement over 10s. An approximation of sets, not a count of them.';

-- Appended rather than inserted: "create or replace view" can only add columns
-- at the end, and renaming existing ones would break every query that reads it.
create or replace view public.v_sessions_en with (security_invoker = on) as
select s.id, s.started_at, s.ended_at,
       wl.text as workout, gl.text as gym,
       round(s.duration_ms / 60000.0)::int as minutes,
       s.avg_hr, s.max_hr, s.calories_kcal,
       (select count(*) from segments g where g.session_id = s.id) as segments,
       s.testing,
       round(s.rest_ms / 60000.0)::int as rest_min,
       round(s.work_ms / 60000.0)::int as work_min
from sessions s
  join gyms gy on gy.id = s.gym_id
  left join labels gl on gl.entity = 'gym'  and gl.entity_id = s.gym_id
       and gl.lang = 'en' and gl.is_alias = false
  left join labels wl on wl.entity = 'workout_type' and wl.entity_id = s.workout_type_id
       and wl.lang = 'en' and wl.is_alias = false;

-- >>>>>>>>>>>>>>>>>>>> 05_trace.sql >>>>>>>>>>>>>>>>>>>>

-- The raw sensor trace, and a column that was already live without a migration.
--
-- Run after 04_motion.sql. Safe to re-run.
--
-- ---------------------------------------------------------------------------
-- First, the drift
-- ---------------------------------------------------------------------------
--
-- sessions.motion_series exists in the live database and appears in no
-- migration in this directory: it was added by hand and the file was never
-- written. The `add column if not exists` below is a no-op there and the thing
-- that makes a fresh project match production, which is the whole job of these
-- files. Nothing is lost by re-stating it.

alter table public.sessions
  add column if not exists motion_series jsonb;

comment on column public.sessions.motion_series is
  'Work and rest as a timeline: [[offset_ms, duration_ms, kind], ...] from the '
  'session start, kind 1 = work, 0 = rest. Deliberately does not tile the '
  'session - a stretch too short for the detector to call belongs to neither '
  'state and simply has no span, so the gaps are meaningful.';

-- ---------------------------------------------------------------------------
-- The trace
-- ---------------------------------------------------------------------------
--
-- Why a blob and not a table of rows:
--
-- A row a second is roughly 4,100 rows for a seventy-minute session, and about
-- 150 KB of CSV. A Wearable Data Layer item is capped at 100 KB for the whole
-- payload, session included, so per-second rows cannot cross from the watch at
-- all without a transport of their own. Gzipped and base64'd the same trace is
-- about 25 KB and rides along beside the session.
--
-- Unpacking happens in the client, not here. Core Postgres has no gunzip -
-- pgcrypto does not provide one either - so a view that claimed to return rows
-- would have to ship an inflate implementation in plpgsql to earn the claim.
-- What the database is good for is saying which sessions carry a trace and how
-- big it is, which is what v_traces below answers; the rows themselves are
-- read by whatever is doing the analysis, which has a real gzip.

alter table public.sessions
  add column if not exists motion_trace text,
  add column if not exists motion_trace_rows integer;

comment on column public.sessions.motion_trace is
  'Per-second accelerometer and heart-rate trace, gzipped then base64. Format '
  'v1, columns t,e,es,al,bpm,hs,st,sg - see MotionTracePack.kt. Diagnostic: '
  'nothing on any screen reads it. It exists so the rest-detection thresholds '
  'can be re-cut against sessions that actually happened instead of against a '
  'guess. Null means the watch recorded no trace, which is not the same as a '
  'trace that recorded stillness.';

-- ---------------------------------------------------------------------------
-- Reading it back
-- ---------------------------------------------------------------------------

create or replace view public.v_traces with (security_invoker = on) as
select s.id,
       s.started_at,
       s.workout_type_id,
       s.gym_id,
       round(s.duration_ms / 60000.0)::int              as minutes,
       s.motion_trace is not null                       as has_trace,
       s.motion_trace_rows                              as trace_rows,
       octet_length(coalesce(s.motion_trace, ''))       as trace_bytes,
       jsonb_array_length(coalesce(s.motion_series, '[]'::jsonb)) as spans,
       round(s.rest_ms  / 1000.0)::int                  as rest_s,
       round(s.work_ms  / 1000.0)::int                  as work_s,
       -- The number that said the old detector was wrong: a session that is
       -- 99% "work" has not been measured, it has been assumed.
       case when (s.rest_ms + s.work_ms) > 0
            then round(100.0 * s.work_ms / (s.rest_ms + s.work_ms))::int
       end                                              as work_pct
from public.sessions s;

comment on view public.v_traces is
  'Which sessions carry a raw trace, and how the detector split each one. The '
  'first place to look when asking whether the rest thresholds are working.';

-- >>>>>>>>>>>>>>>>>>>> new_user_seed.sql >>>>>>>>>>>>>>>>>>>>

-- ============================================================================
-- Seed for a NEW user. Safe to re-run.
--
-- Deliberately ships no gyms except "Other": your gyms are added afterwards,
-- either by asking Claude ("add my gym: <name>, <Google Maps link>") or with the
-- template at the bottom of this file. The exercise catalogue is not seeded
-- either - Claude builds it as you describe real sessions.
-- ============================================================================

-- The unidentified-gym fallback. No coordinates on purpose: GPS never suggests it.
insert into gyms (id, name, lat, lon, notes, is_fallback) values
  ('outro', 'Other', null, null, 'unidentified gym / academia não identificada', true)
on conflict (id) do nothing;

-- The four-day cycle the watch rotates through, plus core off-cycle.
-- These ids are fixed in the app; their display names come from the app itself.
insert into workout_types (id, cycle_order) values
  ('peito',  0),   -- Chest / Peito
  ('costas', 1),   -- Back  / Costas
  ('pernas', 2),   -- Legs  / Pernas
  ('bracos', 3),   -- Arms  / Braços
  ('core',   null) -- off-cycle: chosen deliberately, never suggested
on conflict (id) do nothing;

-- Heart-rate zones for a 177 bpm maximum (Samsung Health's split). Claude can
-- recompute these from your own max HR - just ask.
insert into hr_zones (idx, min_bpm, max_bpm, colour) values
  (1,   0, 106, '#3D7DE8'),
  (2, 107, 123, '#2E9B54'),
  (3, 124, 141, '#C39312'),
  (4, 142, 159, '#D9722A'),
  (5, 160, 999, '#C63F35')
on conflict (idx) do nothing;

insert into labels (entity, entity_id, lang, text, is_alias) values
  ('workout_type','peito', 'pt','Peito',  false),
  ('workout_type','peito', 'en','Chest',  false),
  ('workout_type','costas','pt','Costas', false),
  ('workout_type','costas','en','Back',   false),
  ('workout_type','pernas','pt','Pernas', false),
  ('workout_type','pernas','en','Legs',   false),
  ('workout_type','bracos','pt','Braços', false),
  ('workout_type','bracos','en','Arms',   false),
  ('workout_type','core',  'pt','Core',   false),
  ('workout_type','core',  'en','Core',   false),
  ('workout_type','bracos','pt','bracos', true),
  ('workout_type','core',  'pt','Abdominal', true),
  ('workout_type','core',  'pt','Abdômen',   true),
  ('workout_type','core',  'pt','Abdómen',   true),

  ('hr_zone','1','en','Low intensity',  false),
  ('hr_zone','1','pt','Recuperação',    false),
  ('hr_zone','2','en','Weight control', false),
  ('hr_zone','2','pt','Leve',           false),
  ('hr_zone','3','en','Aerobic',        false),
  ('hr_zone','3','pt','Aeróbico',       false),
  ('hr_zone','4','en','Anaerobic',      false),
  ('hr_zone','4','pt','Limiar',         false),
  ('hr_zone','5','en','Maximum',        false),
  ('hr_zone','5','pt','Máximo',         false),

  ('gym','outro','pt','Outra',  false),
  ('gym','outro','en','Other',  false)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- YOUR GYMS (optional - Claude can do this for you)
--
-- Uncomment, fill in, run. Coordinates: open the gym in Google Maps, long-press
-- (phone) or right-click (computer) the building, and copy the two numbers.
-- id: short, lowercase, no spaces or accents. radius_m: 300 is a good default.
-- ---------------------------------------------------------------------------
-- insert into gyms (id, name, lat, lon, radius_m) values
--   ('smartfit_paulista', 'Smart Fit Paulista', -23.5614, -46.6559, 300),
--   ('bluefit_centro',    'Bluefit Centro',     -23.5450, -46.6380, 300)
-- on conflict (id) do update
--   set name = excluded.name, lat = excluded.lat, lon = excluded.lon,
--       radius_m = excluded.radius_m;
--
-- insert into labels (entity, entity_id, lang, text, is_alias) values
--   ('gym','smartfit_paulista','pt','Smart Fit Paulista', false),
--   ('gym','smartfit_paulista','en','Smart Fit Paulista', false),
--   ('gym','smartfit_paulista','pt','Smart',              true)
-- on conflict do nothing;
