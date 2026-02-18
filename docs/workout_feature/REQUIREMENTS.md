# Workout Feature — Requirements (v2)

## Vision

Turn the activity tracker into a serious workout companion — plan splits, log sets in real-time, track cardio with HealthKit, and get meaningful analytics (1RM, volume, PRs, pace trends). Workouts are a **domain layer that controls a subset of activities**, keeping the dashboard clean.

---

## 1. Core Principles

- **1 active plan per type** (max 1 strength + 1 cardio). Plans exist in states: `draft → active → inactive`
- Activating a new plan auto-deactivates the current one of same type
- Draft plans are editable but don't create shell activities or appear on dashboard
- Plan deactivation → shell activities paused → disappear from dashboard. Container + history preserved
- Exercises are **NOT activities** — they exist only in the workout domain
- **Shared infrastructure, separated specializations** — strength and cardio share plan structure but have distinct data models and session views

---

## 2. Dashboard Integration

**Shell activities** represent workout days on the main dashboard:

- Naming: `"{PlanName} – {DayLabel}"` (e.g. "PPL – Push", "Cardio – Run")
- Placed in **All Day** section as checkbox rows
- Tap → navigates to **Workout Tab** (session view for that day)
- Long-press → standard Skip flow (reason picker)
- Rest days → auto-complete the shell activity
- Shells use `isManagedByWorkout` flag (internal, user never sees/sets it)

### Dashboard Appearance

```
ALL DAY
  ☐ 💪 PPL – Push         →  tap opens Workout Tab
  ☐ 🏃 Cardio – Run       →  tap opens Workout Tab
  ━━━━━━━━━━━━━━━━━━━━━━
MORNING
  ☑ 🧘 Morning Meditation
  ...
```

---

## 3. Exercise Library

- Naming: `"{Name} – {Equipment}"` (e.g. "Bench Press – Barbell", "Lateral Raise – Cable")
- **Aliases**: same exercise can have multiple names; aliases appear as **separate searchable entries** in the library
- **Muscle involvement scores** (0.0–1.0) per muscle for strength exercises
- **Cardio-specific fields**: distance unit, pace unit, available HealthKit metrics
- Each exercise: name, equipment, type (`strength | cardio | timed`), aliases, notes, video URL
- **Pre-seed** ~15 strength + ~5 cardio exercises; user can add more
- **3-tier picker**: inline search → library browser → create new
- Exercise Creator: name + equipment + muscle involvement sliders (strength) or cardio config

---

## 4. Muscle Glossary

Hierarchical anatomy with bodybuilding-relevant sub-groups:

```
Chest                      Shoulders              Core
├─ Upper Chest             ├─ Front Delts          ├─ Upper Abs
└─ Lower Chest             ├─ Side Delts           ├─ Lower Abs
                           └─ Rear Delts           ├─ Obliques
Back                                               └─ Transverse Abdominis
├─ Lats                    Triceps
├─ Upper Back / Traps      ├─ Long Head            Quads
├─ Rhomboids               ├─ Lateral Head         ├─ Vastus Lateralis
└─ Lower Back / Erectors   └─ Medial Head          ├─ Vastus Medialis
                                                    └─ Rectus Femoris
Biceps (flat)              Forearms
                           ├─ Extensors            Calves
Hamstrings (flat)          └─ Flexors              ├─ Gastrocnemius
                                                    └─ Soleus
Glutes
├─ Glute Max
└─ Glute Med
```

Volume benchmarks per parent muscle:
- **MEV** (Minimum Effective Volume): 6–10 sets/week
- **MAV** (Maximum Adaptive Volume): 12–20 sets/week
- **MRV** (Maximum Recoverable Volume): 20–25 sets/week

---

## 5. Strength Plan Editor

- Mon–Sun calendar columns — add exercises to each day
- Per exercise: **target sets** + **RIR** (default 2). No target reps/weight — learned from session history
- Exercises displayed compactly: `(4) Bench – BB`
- **Day types** (Push/Pull/Legs/Upper/Lower/Full Body) auto-detected from dominant muscle coverage (>60%), tappable to override
- **Rainbow color linking**: day dots 🔴🟠🟡🟢🔵🟣⚪ — same color = linked
  - **Only empty days can be linked** — if day has exercises, prompt "Clear this day to link?"
  - Linked days share exercises: add/edit/remove on one propagates to all with same color
  - Unlinking: tap color dot to cycle to unique color

### Volume Heatmap (below calendar)

- Effective sets per muscle = `sets × involvement_score`
- Color coded: 🟢 in MAV / 🟡 near MEV / 🔴 below MEV or above MRV
- **Simple/Advanced toggle**: simple = parent muscles, advanced = sub-group breakdown
- **Junk volume alerts**: flags any day × muscle exceeding MRV

### Plan Editor Wireframe

```
┌──────────────────────────────────────────────────────────┐
│  ← PPL Split          Container: [Strength Training ▼]  │
│──────────────────────────────────────────────────────────│
│       Mon      Tue      Wed    Thu    Fri      Sat  Sun  │
│       🔴       🟠       🟡     ⚪     🔴       🟠   🟡   │
│       Push     Pull     Legs   Rest   Push     Pull Legs │
│       ┌───┐    ┌───┐    ┌───┐  ┌──┐  ┌───┐    ... ...   │
│       │(4)│    │(3)│    │(5)│  │🛌│  │(4)│              │
│       │BB │    │Row│    │Sq │  │  │  │BB │              │
│       │Ben│    │   │    │   │  │  │  │Ben│              │
│       │(3)│    │(3)│    │(3)│  │  │  │(3)│              │
│       │DB │    │PU │    │LP │  │  │  │DB │              │
│       │Inc│    │   │    │   │  │  │  │Inc│              │
│       │[+]│    │[+]│    │[+]│  │  │  │[+]│              │
│       └───┘    └───┘    └───┘  └──┘  └───┘              │
│       12s      14s      16s          12s                 │
│──────────────────────────────────────────────────────────│
│  WEEKLY VOLUME            [Simple ▼ / Advanced]          │
│  Chest 16 ████████ ✅   Triceps 8 ████ ⚠️               │
│  Back  14 ███████  ✅   Biceps  6 ███  🔴               │
│──────────────────────────────────────────────────────────│
│  ⚠️ Quads Wed: 18 eff. sets (MRV=20)                    │
│                 [ Save Plan ]                            │
└──────────────────────────────────────────────────────────┘
```

Mon 🔴 and Fri 🔴 are linked — edit Mon's exercises, Fri auto-updates.

---

## 6. Cardio Plan Editor

Same Mon–Sun layout. Each day: **one or more cardio exercises** (supports brick/triathlon training), each with:
- Exercise (Run/Swim/Cycle/Row) + **session type** + **one target** (distance OR duration, not both)
- **Exercise-specific units**: km/miles for run, meters/yards for swim, km/miles for cycle, meters for row
- Day linking (rainbow colors) — same rules as strength (only empty days)

### Session Types

| Type             | Config Parameters                              | Auto-generates              |
| ---------------- | ---------------------------------------------- | --------------------------- |
| **Steady State** | HR zone (generic Z1-Z5) + distance or duration | "Stay in zone"              |
| **Tempo**        | warmup min + tempo min + cooldown min + zone   | 3-phase guided session      |
| **HIIT**         | rounds + work sec + rest sec                   | Round-by-round timer        |
| **Intervals**    | reps + distance + rest sec                     | Rep-by-rep + rest countdown |
| **Free**         | optional target                                | Just track                  |

### Cardio Plan Wireframe

```
┌──────────────────────────────────────────────────────────┐
│  ← Cardio Plan        Container: [Cardio ▼]             │
│──────────────────────────────────────────────────────────│
│       Mon      Tue    Wed      Thu    Fri      Sat  Sun  │
│       🔴       ⚪     🟠       ⚪     🔴       ⚪   🟡   │
│       ┌───┐    ┌──┐   ┌───┐   ┌──┐   ┌───┐    ┌──┐ ... │
│       │Run│    │🛌│   │Swim│   │🛌│   │Run│    │🛌│     │
│       │Z2 │    │  │   │Int │   │  │   │HIIT│   │  │     │
│       │5km│    │  │   │10× │   │  │   │8rnd│   │  │     │
│       │   │    │  │   │100m│   │  │   │Row │   │  │     │
│       │   │    │  │   │    │   │  │   │Free│   │  │     │
│       │   │    │  │   │    │   │  │   │20m │   │  │     │
│       │[+]│    │  │   │[+] │   │  │   │[+] │   │  │     │
│       └───┘    └──┘   └───┘   └──┘   └───┘    └──┘     │
│──────────────────────────────────────────────────────────│
│  WEEKLY LOAD: 3 sessions · ~120 min · ~18 km             │
│                 [ Save Plan ]                            │
└──────────────────────────────────────────────────────────┘
```

### Per-Day Exercise Config

```
┌─────────────────────────────────────┐
│  Monday — Exercise 1               │
│  Exercise: [ 🏃 Running        ▼] │
│  Session:  [ Zone 2 (Steady)   ▼] │
│  Target:   [ Distance ▼] [ 5  km] │
│  Zone 2 params:                    │
│  HR Zone: [ Zone 2 ▼]             │
│─────────────────────────────────────│
│  [+ Add Another Exercise]          │
└─────────────────────────────────────┘
```

---

## 7. Strength Session Tracking

- Start/pause/resume/end from Workout Tab
- Shows all exercises for today's plan day with expandable set rows
- Log per set: **reps + weight** (or duration for timed exercises like deadhang/plank)
- Timer: total session duration (excluding paused time)
- Auto-fill from most recent session for same exercise (same reps/weight)
- **Auto-completion**: ≥80% planned sets logged → mark shell complete, <80% → mark skipped with reason ("Incomplete: X/Y sets")

---

## 8. Cardio Session Tracking + HealthKit

- Tap "Start" → starts `HKWorkoutSession` on iPhone with correct `HKWorkoutActivityType`
- **Live HealthKit metrics** per exercise type:

| Metric     | 🏃 Run    | 🏊 Swim    | 🚴 Cycle | 🚣 Row     |
| ---------- | -------- | --------- | ------- | --------- |
| Duration   | ✅        | ✅         | ✅       | ✅         |
| Distance   | ✅        | ✅         | ✅       | ✅         |
| Pace       | ✅ min/km | ✅ /100m   | —       | —         |
| Speed      | —        | —         | ✅ km/h  | —         |
| Heart rate | ✅ ~5s    | ✅ per lap | ✅ ~5s   | ✅ ~5s     |
| HR zones   | ✅        | ✅         | ✅       | ✅         |
| Calories   | ✅        | ✅         | ✅       | ✅         |
| Cadence    | ✅ spm    | —         | ✅ RPM   | ✅ str/min |
| Strokes    | —        | ✅         | —       | ✅         |
| SWOLF      | —        | ✅         | —       | —         |
| Laps       | —        | ✅         | —       | —         |
| Elevation  | ✅        | —         | ✅       | —         |

- **Adaptive metric tiles** — shows only available metrics; missing = hidden
- **Phase-specific UIs**: Zone indicator (steady state), HIIT round timer, Tempo 3-phase bar, Interval rep tracker
- **HR zone labels**: generic "Zone 2", "Zone 3" etc. If HealthKit provides max HR → show BPM ranges. Otherwise just zone number
- **Progress bar** when target set (actual vs planned distance/duration)
- **Auto-completion**: actual ≥ 80% of target → complete, else skipped
- **"Import from Health"** fallback for Watch-started workouts
- **Heart rate zone chart** (live during session + post-session summary)

### Session View Examples

**Zone 2 Run:**
```
🏃 Zone 2 Run          ⏱ 23:45
Target: 5 km
─────────────────────────────────
  3.2 km           7:25 /km
  ❤️ 134 bpm    ✅ IN ZONE 2
  164 spm           245 cal

HR ZONES: Z1:2m Z2:18m Z3:3m
PROGRESS ██████████░░ 64%
      [ ⏸ Pause ]  [ ✅ End ]
```

**HIIT Run:**
```
🏃 HIIT Run             ⏱ 12:34
Round 5 of 8
─────────────────────────────────
  🔥 SPRINT         00:18 left
  ████████████░░░░
  Next: 🧊 Recovery (60s)
  ❤️ 168 bpm       Zone 4
  Rounds: ✅✅✅✅🔥☐☐☐
      [ ⏸ Pause ]  [ ✅ End ]
```

---

## 9. Activities View Rules

- Managed shell activities appear **only if** their plan is active (shell not stopped)
- They are **read-only** — tap shows properties for verification, cannot edit
- Changes made exclusively through Workout Plan Editor

---

## 10. Workout Analytics

### Strength
- **Estimated 1RM** per exercise (Brzycki: `weight × 36 / (37 - reps)`) — line chart
- **Volume trends** per exercise and per muscle group — bar chart
- **PR detection** — best 1RM, best total volume, most reps at weight
- **Split adherence** — completed sessions / planned sessions

### Cardio
- **Pace trends** per exercise — line chart over weeks
- **Distance/duration per week** — bar chart
- **HR zone distribution** — time spent per zone, stacked bar over sessions
- **Split adherence** — sessions completed / planned

---

## 11. Configuration

- **Global kg/lbs** — single setting for all strength exercises
- **Per-exercise distance/pace units** — km/miles, meters/yards, min/km, /100m etc.
- **HR zones**: pull from HealthKit if available, else generic zone labels (Z1–Z5, no BPM ranges)
- **5th tab** ("Workouts") in main tab bar

---

## 12. Workout Tab (5th Tab)

Home base for all workout management:

```
┌─────────────────────────────────────┐
│  🏋️ Workouts                       │
│─────────────────────────────────────│
│  TODAY                             │
│  ┌─────────────────────────────┐   │
│  │ 💪 Push                     │   │
│  │ (4) Bench-BB  (3) Inc-DB    │   │
│  │ 12 sets · ~45 min           │   │
│  │     [ Start Strength ]      │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │ 🏃 Zone 2 Run              │   │
│  │ Target: 5 km                │   │
│  │     [ Start Cardio ]        │   │
│  └─────────────────────────────┘   │
│                                     │
│  MY PLANS                          │
│  ├─ 🏋️ PPL Split (active)         │
│  ├─ 🏃 Cardio 3x (active)         │
│  └─ 📝 Full Body v2 (draft)       │
│                                     │
│  ├─ 📚 Exercise Library            │
│  ├─ 💪 Muscle Glossary             │
│  └─ 📊 Analytics                   │
│                                     │
│  RECENT                            │
│  ├─ Pull · Yesterday · 48min      │
│  └─ Run Z2 · 2d ago · 5.2km      │
└─────────────────────────────────────┘
```

---

## 13. Future Scope

- Apple Watch companion (workout session on wrist)
- Progressive overload suggestions (smart auto-fill for reps/weight)
- Plan templates (PPL, 5/3/1, Starting Strength, Couch to 5K)
- HealthKit workout write-back
- Exercise video integration
