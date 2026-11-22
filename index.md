---
title: Fit AI Monitor — setup guide
lang: en
---

**English** · [Português (Brasil)](pt-br.html)

# Fit AI Monitor — setup guide

Record your gym sessions on a Galaxy Watch, see them in Samsung Health, and talk
to Claude about what you lifted.

- **Watch** — tap *Next* between exercises. It records time and heart rate for
  each block, and works with the phone in a locker.
- **Phone** — receives each session, writes it to Health Connect (so Samsung
  Health shows it) and to **your own** Supabase database.
- **Claude** — you tell it what each block was ("bench 4×8 at 60 kg…"), and
  later ask "what did I do on leg press last time?".

Your data lives in a free Supabase project that **you** own. Nobody else,
including whoever shared this app with you, can see it.

Setup takes about **30 minutes**, once.

---

## What you need

| | |
|---|---|
| Phone | Android 14 or newer (Samsung recommended) |
| Watch | Galaxy Watch4 or newer, up to date (Wear OS 5) |
| Apps on the phone | **Samsung Health** and **Health Connect** (built in on Android 14+) |
| Accounts | A free [Supabase](https://supabase.com) account · a [Claude](https://claude.ai) account with connectors and skills |
| For the watch install | A computer with Android platform-tools, **or** a sideloading app on the phone (step 4) |

## Downloads

| File | What it is |
|---|---|
| [fit-ai-monitor-phone.apk](downloads/fit-ai-monitor-phone.apk) | Phone app |
| [fit-ai-monitor-watch.apk](downloads/fit-ai-monitor-watch.apk) | Watch app |
| [setup.sql](https://github.com/marcelocmathias/fit-ai-monitor/blob/main/setup.sql) | Database setup (step 1) |
| [fit-ai-monitor-skill.zip](downloads/fit-ai-monitor-skill.zip) | Claude skill (step 6) |

---

## 1. Create your database (Supabase)

1. Sign in at [supabase.com](https://supabase.com) → **New project**.
   - Name: anything, e.g. `fitaimonitor`
   - Region: the one closest to you
   - Database password: click *Generate* and save it in your password manager
     (you will almost never need it)
   - Plan: **Free**
2. Wait for the project to finish starting (~2 minutes).
3. Open **SQL Editor** → **New query**. Open
   [setup.sql](https://github.com/marcelocmathias/fit-ai-monitor/blob/main/setup.sql),
   click the **Copy raw file** button, paste everything into the editor and press **Run**.
   You should see *Success. No rows returned*.
4. Check it worked — run this in a new query:

   ```sql
   select count(*) from workout_types;   -- should be 5
   ```

## 2. Create your login and lock the door

The phone app signs in as **one** user: you. Then you switch off sign-ups so no
one else can ever create an account in your project.

1. **Authentication → Users → Add user → Create new user**. Your email and a
   strong password. Tick **Auto Confirm User**.
2. **Authentication → Sign In / Providers** → turn **off** *Allow new users to
   sign up* → Save.

## 3. Copy two values for the phone

Open **Project Settings → API Keys** (or the **Connect** button at the top).

| Value | Looks like |
|---|---|
| **Project URL** | `https://abcdefgh.supabase.co` |
| **Publishable key** | `sb_publishable_...` (create one if the list is empty) |

Never use the **secret** key in the app. Send both values to your phone (e.g.
email them to yourself) — you will paste them in step 5.

**Optional, recommended:** free projects pause after a week without activity.
To prevent that: **Database → Extensions** → enable `pg_cron`, then run in the
SQL Editor:

```sql
select cron.schedule('keepalive', '0 6 * * 1', $$ select 1 $$);
```

## 4. Install the apps

### Phone

1. On the phone, open the [phone APK link](downloads/fit-ai-monitor-phone.apk).
2. Allow your browser to *install unknown apps* when asked.
3. If Play Protect warns that the app is unknown → **More details → Install anyway**.

### Watch

The watch has no browser, so the APK is sent to it from a computer or the phone.

**On the watch first:** Settings → About watch → Software → tap *Software
version* 5 times (developer mode). Then Settings → **Developer options** → turn
on **ADB debugging** and **Wireless debugging**. Keep the watch on the same
Wi-Fi as the computer/phone.

**Option A — from a computer** (Windows/Mac/Linux, with
[platform-tools](https://developer.android.com/tools/releases/platform-tools)):

1. On the watch, in *Wireless debugging*, tap **Pair new device**. Note the IP,
   port and the 6-digit code.
2. On the computer:

   ```
   adb pair 192.168.1.50:41234       (type the code when asked)
   adb connect 192.168.1.50:5555     (IP and port shown on the main Wireless debugging screen)
   adb install fit-ai-monitor-watch.apk
   ```

**Option B — from the phone, no computer:** install a Wear OS sideloading app
from the Play Store (for example *Wear Installer 2* or *Bugjaeger*), and follow
its pairing steps with the watch APK you downloaded.

When it's installed, turn **ADB debugging off** again on the watch (it saves battery).

## 5. Set up the phone app

Open **Fit AI Monitor** on the phone → **Settings** tab.

1. **Supabase** → paste the **Project URL** and **Publishable key** → *Save
   project*. Then sign in with the email and password from step 2.
2. **Health Connect** → *Grant permissions* → allow everything listed.
3. **Language** — System, PT-PT, PT-BR or English.

### Samsung Health

Samsung Health reads your workouts from Health Connect:

1. Samsung Health → **⋮ → Settings → Health Connect** → open the permissions
   and allow Samsung Health to **read Exercise, Heart rate and Calories burned**.
   (Read and write are separate switches.)
2. Samsung Health → Settings → **Consents** (or *Data permissions*) → allow
   processing of health data, if it is off.

Workouts appear in Samsung Health as **"Weight machines"** with their heart-rate
curve and calories. They show up a little after the phone receives them.

### Watch

Open Fit AI Monitor on the watch and accept every permission (heart rate,
physical activity, location, notifications). Location is only used to suggest
which gym you are at.

## 6. Connect Claude

1. claude.ai → **Settings → Connectors** → add **Supabase** → authorise it with
   your Supabase account.
2. claude.ai → **Settings → Capabilities → Skills** → **Upload skill** → choose
   [fit-ai-monitor-skill.zip](downloads/fit-ai-monitor-skill.zip)
   and make sure it is switched on.
3. Start a new chat and say:

   > Help me set up Fit AI Monitor. My gyms are …

   Claude checks the database, then adds your gyms. For each gym give it the
   name and a **Google Maps link** (or the coordinates: long-press the building
   in Google Maps). You can also give your age or max heart rate to tune the
   heart-rate zones.
4. Open the phone app and **pull down on the Workouts list** — this sends your
   gyms to the watch. Reopen the watch app: your gyms are now in *Which gym?*.

## 7. Using it

1. **At the gym:** open the app on the watch (or the tile) → pick the gym →
   pick the workout → **tap Next each time you change exercise**. Finish → Save.
2. **Afterwards:** the session reaches the phone on its own when the two are
   near each other. Tell Claude what you did:

   > Today: bench press 4 sets, 60 kg × 10, 8, 8, 6. Then incline dumbbell 22 kg each…

3. **Later:** ask anything — *"what did I do on leg press last time?"*, *"how
   has my squat gone this month?"*.

The watch rotates **Chest → Back → Legs → Arms**, plus **Core** off-cycle, and
pre-selects the next one. If you train a different split, just pick the closest —
what you actually did is what you tell Claude.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Session on the watch but not on the phone | Keep both close, Bluetooth on; open the phone app and pull down on the list. |
| Not in Supabase | Settings → Supabase must say *signed in*. The **Logs** tab shows every step. |
| Not in Samsung Health | Check the Samsung Health → Health Connect read permissions; then Settings → *Send what is missing* in the phone app. |
| My gym isn't offered on the watch | It needs coordinates. Ask Claude to check the gym, pull down in the phone app, reopen the watch app. *Other* is always available. |
| Watch app won't install: "signatures don't match" | Uninstall the old watch app first. Phone and watch apps must come from the same release. |
| Sign-in refused | Check the project shown under Supabase in Settings is yours, and that the user exists in Authentication → Users. *Use a different project* lets you re-enter URL and key. |

## Privacy

- Everything is stored in **your** Supabase project and on your devices.
- The publishable key opens nothing on its own: every table requires the
  signed-in user, and sign-ups are off.
- Claude only sees your data in chats where you use the Supabase connector.
