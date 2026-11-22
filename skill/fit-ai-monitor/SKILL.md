---
name: fit-ai-monitor
description: Gym training log recorded by the Fit AI Monitor watch app and stored in the user's own Supabase project. Use whenever the user mentions a workout, training session, exercise, load, set, reps, their gym, heart rate during training, or asks what they lifted last time — in English or Portuguese (treino, academia, exercício, carga, série, repetições, "quanto peguei da última vez"). Also use for first-time setup: adding gyms, setting heart-rate zones, checking the database is ready. Reads and writes through the Supabase connector.
---

# Fit AI Monitor — training log

The user records workouts on a Galaxy Watch with the Fit AI Monitor app. The
watch captures **time and heart rate only**: it splits a session into anonymous
blocks ("segments") as the user taps *Next* between exercises. The phone app
uploads those sessions to the user's **own Supabase project** and writes them to
Health Connect, which Samsung Health imports.

Your job is the other half: what each block actually was, and what was on the
bar. You write it into the same database, through the **Supabase connector**.
The two halves meet on `(session_id, ordinal)`.

## Language — English and Português (Brasil)

**Answer in the language the user writes in.** If they write Portuguese, use
Brazilian Portuguese (academia, celular, série, carga, "anilha", "placa"/"carga
na máquina", "halter", "barra"). Exercise and gym names resolve through the
`labels` table, which stores a canonical name per language (`en`, `pt`) plus any
number of aliases — so "incline press", "supino inclinado" and "supino inclinado
máquina" all land on one id.

## Finding the project

Use the Supabase connector. If the user has more than one project, list them and
ask which one holds Fit AI Monitor (it has the tables `sessions`, `segments`,
`gyms`, `labels`). Remember the project id for the rest of the conversation.

---

## First-time setup (onboarding)

Run this when the user says they just installed the app, asks for help setting
up, or when you notice the database has no gyms besides `outro`. Go one step at
a time and confirm each before moving on.

### 1. Check the database is ready

```sql
select
  (select count(*) from gyms)          as gyms,
  (select count(*) from workout_types) as workout_types,
  (select count(*) from hr_zones)      as hr_zones,
  (select count(*) from sessions)      as sessions;
```

- **Error "relation does not exist"** → the setup SQL was never run. Tell the
  user to open Supabase → SQL Editor → New query, paste the whole of
  `supabase/setup.sql` from the guide, and press Run. Do not try to recreate the
  schema yourself from memory — the app depends on exact column names.
- `workout_types = 5`, `hr_zones = 5`, `gyms >= 1` → ready.

Also confirm the account side, which only the user can see in the dashboard:
Authentication → **one user exists** (the email they sign in with on the phone),
and **"Allow new users to sign up" is off**. Ask; don't assume.

### 2. Add their gyms

The watch suggests the nearest gym by GPS, so each gym needs coordinates. Ask for
each gym's **name** and either a **Google Maps link**, an **address**, or the
**coordinates** (long-press the building in Google Maps, the numbers appear at
the top). From a Maps link like `.../@-23.5614,-46.6559,17z` the coordinates are
the two numbers after `@`. If you only have an address and cannot resolve it
precisely, ask for the coordinates — a gym placed in the wrong spot is worse than
none, because GPS will suggest it.

Write the gym **and** its labels together:

```sql
insert into gyms (id, name, lat, lon, radius_m) values
  ('smartfit_paulista', 'Smart Fit Paulista', -23.5614, -46.6559, 300)
on conflict (id) do update
  set name = excluded.name, lat = excluded.lat, lon = excluded.lon,
      radius_m = excluded.radius_m, active = true;

insert into labels (entity, entity_id, lang, text, is_alias) values
  ('gym','smartfit_paulista','pt','Smart Fit Paulista', false),
  ('gym','smartfit_paulista','en','Smart Fit Paulista', false),
  ('gym','smartfit_paulista','pt','Smart',              true)
on conflict do nothing;
```

- `id`: lowercase, no accents, no spaces, specific (`smartfit_paulista`, not `smartfit`).
- `radius_m`: 300 by default. If two of their gyms are less than ~600 m apart,
  keep 300 — the app already refuses to guess between gyms it cannot separate.
- Add the aliases they actually use ("a Smart", "academia do prédio").
- Never delete a gym that has sessions; set `active = false` instead.

Then tell them: **open the phone app and pull down on the Workouts list** (or
just reopen it). The phone sends the gym list to the watch; the next time they
open the watch app the gyms appear in "Which gym?". The `outro` / "Other" entry
is always there for anywhere else.

### 3. Heart-rate zones (optional)

The seed uses zones for a 177 bpm maximum. If the user knows their max HR, or
gives their age (estimate `208 − 0.7 × age`), recompute with Samsung Health's
split — upper bounds at 60%, 70%, 80%, 90% of max:

```sql
-- example for max 190
update hr_zones set min_bpm = 0,   max_bpm = 113 where idx = 1;
update hr_zones set min_bpm = 114, max_bpm = 132 where idx = 2;
update hr_zones set min_bpm = 133, max_bpm = 151 where idx = 3;
update hr_zones set min_bpm = 152, max_bpm = 170 where idx = 4;
update hr_zones set min_bpm = 171, max_bpm = 999 where idx = 5;
```

Say plainly that this changes how *you* report zones; the zone colours on the
watch's own summary screen are fixed in this version of the app.

### 4. The workout cycle

The watch rotates through four fixed workout types and pre-selects the next one:
**Chest (peito) → Back (costas) → Legs (pernas) → Arms (braços)**, plus **Core**
off-cycle. These ids are built into the app and cannot be renamed. If the user
trains a different split (push/pull/legs, upper/lower, full body), suggest they
just pick the closest type on the watch — what they actually did is recorded in
the sets you write, which is what matters for every question afterwards.

### 5. Done

Summarise what is set up, and explain the daily loop in two lines: record on the
watch → tell you what each block was → ask you anything later.

---

## Schema

```
gyms(id, name, lat, lon, radius_m, notes, is_fallback, active)
workout_types(id, cycle_order)        peito=0 costas=1 pernas=2 bracos=3 core=null
exercises(id, load_type, muscle_group, active)
labels(entity, entity_id, lang, text, is_alias)     lang in ('en','pt')
hr_zones(idx, min_bpm, max_bpm, colour)

-- written by the watch (via the phone), never by you
sessions(id uuid, started_at, ended_at, gym_id, workout_type_id, duration_ms,
         avg_hr, max_hr, calories_kcal, hr_series jsonb, zone_ms jsonb,
         device, testing, rest_ms, work_ms, motion_series)
segments(id, session_id, ordinal, kind, started_at, ended_at, duration_ms,
         visit_count, avg_hr, max_hr, min_hr, rest_ms, work_ms, work_bouts)
         kind in ('strength','core','aerobic')
         ordinal is ANONYMOUS — "the 4th block of time", not an exercise

-- written by you
segment_exercises(segment_id, exercise_id, position)   position 2 = paired movement
sets(id, segment_id?, session_id?, exercise_id, gym_id, performed_at,
     set_index, load, load_type, reps, rpe, note, raw, source, import_key)
     source in ('session','chat','imported')
segments.note                                          per-block note
session_notes(session_id, body, written_at)            one summary per session
```

`rest_ms` / `work_ms` / `work_bouts` are **estimates from the wrist
accelerometer**, not something the user pressed. Treat them as approximate and
say so when quoting them. They are blind to exercises where the watch arm barely
moves (leg extension, leg curl, leg press), so those blocks read as rest. Zero
means "not measured", never "no rest taken".

`load_type`: `plate_per_side` (anilha por lado) · `stack` (placa / carga da
máquina) · `dumbbell` (halter) · `barbell` (barra) · `bodyweight` (peso corporal)
· `other`. **It changes what the number means, so it travels with every set.** A
stack number is only comparable on the same machine at the same gym. When the
user doesn't say, ask once per exercise and remember the answer via the
exercise's `load_type`.

## Views to prefer over raw joins

- `v_last_load` — last thing lifted per exercise per gym. The most common question.
- `v_load_history` — every set, newest first.
- `v_unannotated_sessions` — sessions the watch recorded that were never described.
- `v_sessions_en` — one row per session, readable.

## Rules

- **Always scope loads by gym.** The same exercise does not carry the same number
  in two places. Never present a load without naming the gym. `outro` ("Other")
  loads are real but not comparable — never offer one as "last load".
- **Never invent an exercise id.** Resolve through `labels` first. If nothing
  matches, say so and ask, then insert the exercise *and* its labels in both
  languages before any set references it.
- **Exclude test data.** `sessions.testing = true` rows are fixtures. The views
  filter them; raw queries must too.
- **Segments have no identity.** The watch never knew segment 4 was incline
  press. You assign meaning, and only because the user told you.
- **Core/aerobic blocks are their own log** — don't merge them into the day's
  strength table.
- **Never write to `sessions` or `segments`** (except `segments.note`). Inventing
  one puts fabricated heart-rate data next to real measurements.

## Workflow: after a workout

1. Check `v_unannotated_sessions`. Open with what's missing, concretely:
   *"Tuesday's session has 7 blocks, the longest was 11 minutes. What were they?"*
   / *"O treino de terça tem 7 blocos, o maior de 11 minutos. O que foi cada um?"*
2. The user describes the session in prose, in either language, often out of
   order. Match blocks by order and duration; ask when it's ambiguous.
3. Resolve every exercise name through `labels`.
4. Write `segment_exercises` and `sets`. For each set:
   - `segment_id` and `session_id` from the segment
   - `gym_id` and `performed_at` copied from the session (denormalised on purpose)
   - `source = 'session'`
   - `raw` = exactly what the user wrote, before you parsed it
5. **Write the notes**:
   - `segments.note` — what happened in that block (a substitution, a machine
     taken, how it felt). One or two sentences, or null if nothing to say.
   - `session_notes.body` — two or three sentences about the whole session.
     Never a list of loads; those are already in `sets`.
6. Read back what you wrote and show a short table. Don't assume it landed.

No session recorded (watch flat, forgot to start it)? Write the sets with
`source = 'chat'`, `segment_id` and `session_id` null, and the date they give.

## Resolving and adding exercises

```sql
select entity_id, text, lang, is_alias
from labels
where entity = 'exercise' and lower(text) like lower('%supino inclinado%');
```

New exercise — all in one go:

```sql
insert into exercises (id, load_type, muscle_group)
values ('remada_cavalinho', 'plate_per_side', 'costas');

insert into labels (entity, entity_id, lang, text, is_alias) values
  ('exercise','remada_cavalinho','pt','Remada cavalinho', false),
  ('exercise','remada_cavalinho','en','T-bar row',        false),
  ('exercise','remada_cavalinho','pt','cavalinho',        true),
  ('exercise','remada_cavalinho','en','t bar row',        true);
```

Ids are snake_case, unaccented, specific: `supino_inclinado_maquina`, not
`supino_inclinado`. A new database starts with **no exercises** — the catalogue
grows as the user describes real sessions. That is expected, not an error.

## Worked query

*"What did I last do on incline press at Smart Fit Paulista?"*

```sql
select performed_on, load, load_type, reps, raw
from v_load_history
where exercise_id = 'supino_inclinado_maquina'
  and gym_id = 'smartfit_paulista'
order by performed_on desc
limit 5;
```

Answer with the gym named and the load type plain — "66 on the stack" /
"66 na placa", not a bare "66".

## Troubleshooting the user may ask about

- **Session on the watch but not in the database** → open the phone app, pull
  down on Workouts. Check Settings → Supabase shows "signed in". The Logs tab
  shows each hop.
- **Not in Samsung Health** → Samsung Health → Settings → Health Connect → allow
  it to read Exercise and Heart rate; then in the phone app Settings → "Send
  what's missing".
- **Gym not offered on the watch** → the gym needs `lat`/`lon` and `active =
  true`; then reopen the phone app so it re-sends the list, then reopen the watch app.

## What never happens here

- No training programme is stored, prescribed or assumed.
- No unsolicited coaching, comparisons or encouragement about the numbers.
