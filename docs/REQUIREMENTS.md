# Product Requirements: Daily Activity Tracker (v6 — Final Draft)

## Vision
The goto "Life OS" — one place for every habit, health metric, appointment, and routine. Dark mode only, local-first, private, deeply customizable.

---

## 1. Activity Types & Inputs

| Type | Behavior | Multi-log/day? |
|------|----------|----------------|
| **Checkbox** | Tap to complete | No |
| **Value** | Number + unit (once) | No |
| **Cumulative** | Incremental logs summing to target | **Yes** |
| **Container** | Derived from children | N/A |

**Composable Attachments** (any non-Container): 📸 Photo (ghost overlay), 📝 Notes.

**HealthKit Linkage**: Any Value/Cumulative can optionally link to a HealthKit type (Read / Write / Both).

---

## 2. Hierarchy

```
Category (pre-filled + fully customizable)
  └── Activity / Container
        └── Sub-Activity (any type, own schedule)
```

**Pre-filled Categories**: Workout, Supplement, Hygiene, Medical Appointments, Skills, Tracking.

**Partial Completion**: Score = `Σ(child_completion × weight) / Σ(weight)`. Default equal weights.

**Day-Variant Routines**: Sub-tasks have own schedules. Parent shows only today's applicable children. No applicable children → auto-complete.

---

## 3. Scheduling

| Schedule | Behavior |
|----------|----------|
| Daily | Every day |
| Weekly | Selected days |
| Monthly | Selected dates |
| Sticky | Persists until done (Backlog) |
| Ad-hoc | Specific date, one-off |

**Time Windows**: 🌅 Morning / ☀️ Afternoon / 🌙 Evening / custom range.

**Dependency Ordering**: "After X", "Before Y" hints → auto-sort within windows.

**Semi-Collapse**: Future windows collapsed, current/overdue expanded, done items collapse.

**Vacation Mode**: Quick toggle from **main page** ("Mark today as vacation") or date-range in Settings. Vacation days excluded entirely from all analytics.

---

## 4. Dashboard (Today View)

```
┌─────────────────────────────────┐
│  ◯ Daily Progress Ring          │
│  💬 Encouragement Bar           │
├─────────────────────────────────┤
│ 🔄 ALL DAY                     │  ← Cumulative items (always visible)
│ ┌──────────┐ ┌──────────┐      │
│ │ ◯ Steps  │ │ ◯ Water  │      │
│ └──────────┘ └──────────┘      │
├─────────────────────────────────┤
│ 🌅 MORNING (expanded)          │
│ ☑ Brush Teeth                  │
│ ▷ Morning Routine [2/3]        │
├─────────────────────────────────┤
│ ☀️ AFTERNOON (collapsed ▸)     │
├─────────────────────────────────┤
│ 📌 BACKLOG                     │
├─────────────────────────────────┤
│ ✅ COMPLETED (collapsed ▸)     │
└─────────────────────────────────┘
```

**Easy-Complete UX**:
- Tap: Complete Checkbox / Input Value / Expand Container.
- Swipe Right: Quick-complete.
- Swipe Left: Unplanned Skip (with reason).
- Container header tap: "Mark all done" shortcut.
- Floating "+" for Cumulative quick-add.
- Undo toast after every action.

---

## 5. Unplanned Skip

For when task is scheduled but circumstances prevent it (injury, weather, sick, etc.).

- Prompts for **reason** (preset chips + free text).
- **Excluded from scoring**: Day's heatmap and completion % are calculated **only from non-skipped activities**. Skip does not overwrite or reset the overall score — it simply removes that activity from the denominator.
- Not shown on heatmap at all (transparent / not counted).

---

## 6. Photo Capture & Review

- **Ghost Overlay**: Previous photo at ~30% opacity + grid lines.
- **Photo Timeline**: Scrollable strip with scrub slider for smooth transitions.

---

## 7. Past-Day Browser

- Navigate to **any past date** (no limit).
- View all activities with status.
- **Fully editable**: Update values, add photos, mark complete retroactively.

---

## 8. Smart Notifications (Presets)

- 🔔 **"Remind at [time]"** — fixed.
- ⏰ **"Morning nudge"** — 8 AM if not started.
- 🌙 **"Evening check-in"** — 8 PM if < 50%.
- 🔁 **"Periodic"** — Every N hrs if behind.
- 🔕 **"Don't remind"** — **default**.

---

## 9. Encouragement Bar

Always-present, data-driven banner at the top of the dashboard. Uses **recent** data (not strictly weekly).

**Content**:
- **Highlights most improved areas**: *"Your Hygiene consistency is up 20% this week! 🎉"*
- **Gentle nudges**: *"Supplements has been tough — maybe focus there today?"*
- **Goal suggestions**: If consistently missing a target, suggest adjustment: *"Water target of 2000ml seems hard. Try 1500ml?"*
- Tap to expand for full insights.

**Appointment Flow**: Complete scheduling task → prompt for date/time → creates Ad-hoc task + **Calendar event** (EventKit). Tapping opens Calendar for location/notes.

---

## 10. Analytics

### Per-Activity
- **Streak**: Current + longest 🔥.
- **Heatmap**: 🟩 Dark green (100%) → 🟢 Light green (partial) → ⬜ Gray (missed). Skipped days not shown/counted.
- **Value Chart**: Apple Health-style — **Daily / Weekly / Monthly** range toggle with smooth graphs.
- **Photo Gallery** + **Log History**.

### Global
- **Category Scorecards** (7/30/90 days).
- **"Doing Well" / "Needs Attention"** rankings.
- **Overall Heatmap**.

---

## 11. Editing & Undo

- **Everything editable** — values, status, skip reasons, past entries, activity config.
- **Undo toast** after every action.

---

## 12. Technical

- Dark mode only. SwiftData (iOS 17+) + CloudKit. Photos in Documents dir.
- EventKit for calendar events. HealthKit read/write. Haptic feedback.

---

## 13. Future Scope

- Workout detail (Sets/Reps/Rest, cardio metrics).
- iOS Widgets.
- Siri Shortcuts.
- Import/Export.
- Templates / Packs.
- Onboarding wizard.
- Streak celebrations & milestones.
- Apple Watch companion.
