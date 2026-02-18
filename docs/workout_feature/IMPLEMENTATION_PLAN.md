# Workout Feature — Implementation Plan

> See also: [REQUIREMENTS.md](file:///Users/sambhavgupta/Desktop/daily-activity-tracker/docs/workout_feature/REQUIREMENTS.md) · [ARCHITECTURE.md](file:///Users/sambhavgupta/Desktop/daily-activity-tracker/docs/workout_feature/ARCHITECTURE.md)

---

## Existing Code Changes

| File                                                                                                                                                | Change                                     | Risk                          |
| --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ----------------------------- |
| [Activity.swift](file:///Users/sambhavgupta/Desktop/daily-activity-tracker/daily-activity-tracker/Models/Activity.swift)                            | Add `var isManagedByWorkout: Bool = false` | Low — 1 field, defaults false |
| [ContentView.swift](file:///Users/sambhavgupta/Desktop/daily-activity-tracker/daily-activity-tracker/ContentView.swift)                             | Add 5th Workout tab                        | Low                           |
| [DashboardView](file:///Users/sambhavgupta/Desktop/daily-activity-tracker/daily-activity-tracker/Views/Dashboard)                                   | Tap managed shell → Workout Tab            | Medium — cross-tab navigation |
| [ActivitiesListView](file:///Users/sambhavgupta/Desktop/daily-activity-tracker/daily-activity-tracker/Views/Activities)                             | `isManagedByWorkout` → read-only           | Low                           |
| [daily_activity_trackerApp.swift](file:///Users/sambhavgupta/Desktop/daily-activity-tracker/daily-activity-tracker/daily_activity_trackerApp.swift) | Register new models in `Schema([...])`     | Low                           |

---

## New Files

```
Models/
  MuscleGroup.swift                 — hierarchy + volume benchmarks (MEV/MAV/MRV)
  Exercise.swift                    — Exercise + ExerciseMuscle (shared model)
  WorkoutPlan.swift                 — WorkoutPlan + WorkoutPlanDay (shared plan structure)
  StrengthPlanExercise.swift        — strength plan config (targetSets, rir, supersetGroup)
  CardioPlanExercise.swift          — cardio plan config (sessionType, target, params)
  StrengthSession.swift             — StrengthSession + WorkoutSetLog
  CardioSession.swift               — CardioSession + CardioSessionLog

Types/
  CardioSessionType.swift           — enum: steadyState, hiit, tempo, intervals, free
  CardioMetric.swift                — per-exercise metric availability
  WorkoutPlanStatus.swift           — enum: draft, active, inactive
  CardioSessionParams.swift         — codable structs per session type

Services/
  WorkoutPlanManager.swift          — plan CRUD, shell sync, volume analysis, day-type detection
  StrengthSessionManager.swift      — set logging, auto-fill, auto-completion
  CardioSessionManager.swift        — HK integration, live metrics, phase timers

Views/Workout/
  WorkoutTabView.swift              — unified home (today, plans, library, history)
  StrengthPlanEditorView.swift      — Mon-Sun + exercises + volume heatmap
  CardioPlanEditorView.swift        — Mon-Sun + session type picker + multi-exercise
  StrengthSessionView.swift         — set-by-set logging, timer, pause/resume
  CardioSessionView.swift           — live metric tiles, phase UIs, progress bar
  CardioSessionPhaseView.swift      — HIIT rounds, Tempo phases, Interval reps
  ExerciseLibraryView.swift         — browse + search all exercises
  ExerciseDetailView.swift          — view/edit exercise details
  ExercisePickerView.swift          — 3-tier: search → library → create
  ExerciseCreatorView.swift         — create with muscle sliders or cardio config
  MuscleGlossaryView.swift          — hierarchical muscle browser + benchmarks
  WorkoutAnalyticsView.swift        — unified: strength + cardio sections
  SessionSummaryView.swift          — post-session stats
```

---

## Phases

### W1: Foundation + Knowledge Base

Models & types:
- [ ] `Exercise`, `ExerciseMuscle`, `MuscleGroup` models
- [ ] `WorkoutPlan`, `WorkoutPlanDay` models
- [ ] `StrengthPlanExercise`, `CardioPlanExercise` models
- [ ] `WorkoutPlanStatus` enum (draft/active/inactive)
- [ ] `CardioSessionType` enum + session param codable structs
- [ ] Register all new models in `ModelContainer.Schema`

Pre-seed data:
- [ ] Muscle glossary with hierarchy and MEV/MAV/MRV benchmarks
- [ ] ~15 strength exercises with muscle involvement scores
- [ ] ~5 cardio exercises with unit + metric config

Services:
- [ ] `WorkoutPlanManager` — CRUD, shell sync, volume analysis, day-type auto-detection

Views:
- [ ] `WorkoutTabView` — today + plans + library + glossary
- [ ] `ExerciseLibraryView` + `ExercisePickerView` + `ExerciseCreatorView`
- [ ] `ExerciseDetailView`
- [ ] `MuscleGlossaryView`
- [ ] `StrengthPlanEditorView` — Mon-Sun, color links, volume heatmap, junk alerts
- [ ] `CardioPlanEditorView` — Mon-Sun, session type picker, multi-exercise per day

Integration:
- [ ] Add `isManagedByWorkout` to `Activity.swift`
- [ ] `ActivitiesListView` read-only filter for managed shells
- [ ] `DashboardView` tap routing for managed shells → Workout Tab
- [ ] 5th tab in `ContentView`
- [ ] Global kg/lbs + per-exercise distance/pace units

### W2: Strength Session Tracking

Models:
- [ ] `StrengthSession` + `WorkoutSetLog` models

Services:
- [ ] `StrengthSessionManager` — lifecycle, set logging, auto-fill, auto-completion bridge

Views:
- [ ] `StrengthSessionView` — timer, set rows, pause/resume
- [ ] `SessionSummaryView` — post-session stats
- [ ] Today's hero card (strength) + dashboard tap → session
- [ ] Recent sessions list in `WorkoutTabView`

Edge cases:
- [ ] Session recovery (app killed → prompt resume/abandon on relaunch)
- [ ] Auto-completion with `ActivityLog(.completed)` / `ActivityLog(.skipped)`

### W3: Cardio Session Tracking + HealthKit

Models:
- [ ] `CardioSession` + `CardioSessionLog` models

Services:
- [ ] `CardioSessionManager` — `HKWorkoutSession` start/end, live HK queries, phase timers

Views:
- [ ] `CardioSessionView` — adaptive metric tiles per exercise type
- [ ] `CardioSessionPhaseView` — zone indicator, HIIT rounds, tempo phases, interval reps
- [ ] Heart rate zone chart (live + post-session, generic zone labels)
- [ ] Today's hero card (cardio) in `WorkoutTabView`

Edge cases:
- [ ] Multi-exercise cardio session flow (brick/triathlon days)
- [ ] "Import from Health" fallback for Watch-started workouts
- [ ] Session recovery
- [ ] HR zones from HealthKit with manual fallback

### W4: Analytics

- [ ] Strength: 1RM estimation, volume trends, PR detection
- [ ] Cardio: pace trends, distance/week, HR zone distribution
- [ ] Split adherence for both types
- [ ] `WorkoutAnalyticsView` — unified with strength/cardio sections

### W5: Watch Companion + Polish

- [ ] watchOS target + `WCSession` data sync
- [ ] Watch workout session UI (strength set logger + cardio live metrics)
- [ ] Progressive overload suggestions
- [ ] Plan templates (PPL, 5/3/1, Couch to 5K)
