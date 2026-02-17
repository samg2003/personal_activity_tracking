# Backlog

- [77] **Multi-session: `isContainerCompleted` ignores session count.** [AI found]
  - `isContainerCompleted` checks `logs.contains(.completed)` per child — passes if child has 1 of 3 sessions done.
  - **Impact**: Container shown as complete in streaks/analytics when multi-session children are only partially done.

- [78] **Multi-session: `containerCompletionRate` same bug as [77].** [AI found]
  - `allSatisfy` in `containerCompletionRate` uses same ANY-completion check.
  - **Impact**: Inflated container completion rates for containers with multi-session children.

- [79] **Multi-session: `completionStatus` container children counts `total += 1` ignoring sessions.** [AI found]
  - When computing day completion status for container children, each child adds 1 to total regardless of session count. A 3-session child should add 3.
  - **Impact**: Progress bar understates required work for multi-session container children.

- [80] **Multi-session: `currentStreak` uses `completedDates` Set — collapses sessions.** [AI found]
  - `Set<Date>` collapses all completion logs to 1 per day. Completing 1 of 3 sessions counts the day as fully completed for streak purposes.
  - **Impact**: Inflated current streak for multi-session activities.

- [81] **Multi-session: `longestStreak` same bug as [80].** [AI found]
  - Same `completedDates` Set pattern.
  - **Impact**: Inflated longest streak for multi-session activities.


- [63] **Dead code: `Item.swift` still in project.** [AI found]
  - File contains only a comment saying "This file is no longer used. Delete from Xcode project." (3 lines). Should be removed from the project and filesystem.
  - **Impact**: Low — cosmetic, but clutters project navigator and confuses new contributors.

- [64] **Duplicate streak logic across `AnalyticsView` and `ActivityAnalyticsView`.** [AI found]
  - `AnalyticsView.streakFor(_:)` (~90 lines) and `ActivityAnalyticsView.computeStreak()`/`computeContainerStreak()`/`longestStreak` (~100 lines) implement nearly identical streak-counting algorithms (walk backwards from today, check schedule, count consecutive completed days). Both also have their own `isContainerCompleted(_:on:)` helper with ~identical logic.
  - **Refactor**: Extract a shared `StreakCalculator` service (or add to `ScheduleEngine`) with `currentStreak(for:logs:activities:)` and `longestStreak(for:logs:activities:)`. Both views should delegate to it.
  - **Impact**: High — any future streak logic fix must be applied in 2+ places. Bug [50] already showed this fragility.

- [65] **`DashboardView.completionFraction` duplicates `ScheduleEngine.completionStatus`.** [AI found]
  - `DashboardView.completionFraction` (lines 80-116, ~37 lines) reimplements the same completion calculation that was just centralized into `ScheduleEngine.completionStatus()`. It handles containers, cumulatives, multi-session, skipped states — all of which are now in `ScheduleEngine`.
  - **Refactor**: Replace `completionFraction` body with `scheduleEngine.completionStatus(on: today, activities: todayActivities, logs: allLogs, vacationDays: vacationDays).rate`, similar to what was done for DatePickerBar.
  - **Impact**: High — this is the main progress bar. Any drift between the two implementations causes the progress bar to disagree with the date picker dots. Note it currently uses `todayActivities` (includes carry-forwards) while the shared method uses `activitiesForToday` without carry-forwards — need to decide which is correct.

- [66] **`GoalDetailView` reimplements its own completion rate logic instead of reusing `ScheduleEngine`/analytics helpers.** [AI found]
  - `activityRate(_:)` (~50 lines, lines 576-624), `containerRate(_:)` (~70 lines, lines 628-698), and `overallScore` (~22 lines) all implement their own schedule-checking, vacation-filtering, skip-handling, and completion counting. This largely duplicates `AnalyticsView.completionRate(for:)` and could be unified.
  - `dayCell(activity:date:)` (lines 424-486) also reimplements its own schedule type switch and skip/complete checking per day — could use the centralized `ScheduleEngine.completionStatus()` or a single-activity variant.
  - **Refactor**: Extract a `CompletionCalculator` or extend `ScheduleEngine` with `completionRate(for:over:logs:vacationDays:activities:)`. Both GoalDetailView and AnalyticsView should delegate.
  - **Impact**: High — 5 separate functions across 2 files all doing similar work. Bug [59] already showed how these diverge.

- [67] **Inline schedule-type switch statements scattered across 6+ files instead of using `ScheduleEngine.shouldShow`.** [AI found]
  - Files that re-implement `case .daily: / case .weekly: weekdays.contains(...) / case .monthly: monthDays.contains(...)` inline: `AnalyticsView` (streakFor, completionRate), `ActivityAnalyticsView` (computeStreak, longestStreak, computeContainerStreak), `GoalDetailView` (activityRate, containerRate, dayCell), `GoalsView`.
  - `ScheduleEngine.shouldShow(_:on:)` already handles this correctly and accounts for `createdDate`, `stoppedAt`, and snapshots.
  - **Refactor**: Replace all inline schedule switches with calls to `scheduleEngine.shouldShow()` or `activity.scheduleActive(on:).isScheduled(on:)`.
  - **Impact**: Medium-High — any new schedule type (e.g., biweekly, custom intervals) would need to be added in 6+ places. Single source of truth avoids this.

- [68] **`scoreColor(_:)` utility function duplicated in `GoalDetailView` and `GoalsView`.** [AI found]
  - Both files define identical `scoreColor(_ score: Double) -> Color` functions (`>= 0.8 green, >= 0.5 orange, else red`).
  - **Refactor**: Move to a shared extension on `Color` or a `Utils/` helper.
  - **Impact**: Low — cosmetic duplication, but easy to consolidate.

- [69] **`DashboardView.swift` is 973 lines — should be decomposed.** [AI found]
  - Contains UI layout, all completion/skip/session logic, all action handlers (complete, skip, unskip, log value, remove value, add cumulative, HealthKit sync, photo prompt), and the FAB. This makes it fragile and hard to navigate.
  - **Refactor**: Extract action handlers into a `DashboardActions` helper or a ViewModel. Move completion logic (isFullyCompleted, isSkipped, isSessionCompleted, isSessionSkipped, cumulativeValue) into a shared service or model extension. The view should primarily handle layout and delegate business logic.
  - **Impact**: Medium — maintainability improvement. Currently every new feature (photo flow, vacation, undo) adds more lines to this monolith.

- [70] **`ActivityDetailView.currentStreak` is a 4th streak implementation — ignores schedule entirely.** [AI found]
  - Lines 181-192. Naively walks backward counting consecutive days with a `.completed` log. Does not check if the activity was scheduled on each day, doesn't handle skipped/vacation days, doesn't handle containers or multi-session. Shows misleading streak counts for weekly/monthly activities.
  - **Files**: `ActivityDetailView.swift` (lines 181-192)
  - **Refactor**: Replace with call to the shared `StreakCalculator` once bug [64] is addressed.
  - **Impact**: Medium — users see different streak numbers on the detail page vs the analytics page.

- [71] **`GoalsView.consistencyScore(for:)` duplicates `GoalDetailView.overallScore`.** [AI found]
  - Both compute a 14-day weighted average of per-activity completion rates, with identical inline schedule switches, vacation filtering, and skip handling. ~60 lines each.
  - **Files**: `GoalsView.swift` (lines 142-201), `GoalDetailView.swift` (lines 554-575)
  - **Refactor**: Extract a shared `consistencyScore(for:logs:vacationDays:activities:)` utility. Both views call it.
  - **Impact**: Medium — any fix to scoring logic must be applied in both files.

- [72] **`skipReasons` array hardcoded identically in 4 separate views.** [AI found]
  - `["Injury", "Weather", "Sick", "Gym Closed", "Other"]` appears (with minor variation — `ContainerRowView` has "Not Feeling Well" instead of "Gym Closed") as a `private static let` in:
    - `ContainerRowView.swift` (line 18)
    - `CumulativeRingView.swift` (line 12)
    - `ValueInputRow.swift` (line 17)
    - `DashboardView.swift` (skip sheet inline)
  - **Refactor**: Move to a shared constant (e.g., `SkipReasons.defaults` or on the model layer). The inconsistency between "Gym Closed" vs "Not Feeling Well" may be a bug itself.
  - **Impact**: Low-Medium — adding/changing skip reasons requires editing 4 files.

- [73] **`formatValue(_:)` helper duplicated identically across multiple component files.** [AI found]
  - Same implementation (`truncatingRemainder(dividingBy: 1) == 0` → `%.0f` else `%.1f`) exists in:
    - `CumulativeRingView.swift` (line 131)
    - `ValueInputRow.swift` (line 143)
    - `DashboardView.swift` (formatQuickAddCurrent uses similar logic)
  - **Refactor**: Move to a shared `Double` extension (e.g., `Double.cleanString`).
  - **Impact**: Low — cosmetic duplication, easy to consolidate.

- [74] **`AddActivityView.swift` is 853 lines with ~70 lines of inline icon data arrays.** [AI found]
  - The `iconCategories` property (lines 57-119) defines 7 icon category groups with ~80 SF Symbol names as string literals inline in the view. This makes the view file very long and mixes data with presentation.
  - **Refactor**: Extract icon data to a separate `IconCatalog` enum/struct. This also makes it testable and reusable if other parts of the app need the icon list (e.g., future icon search). The view handles type selection, schedule configuration, HealthKit config, edit mode, and snapshot creation — consider splitting into smaller sub-views.
  - **Impact**: Medium — maintainability improvement for a frequently edited file.

- [75] **`AnalyticsView.completionRate(for:)` (~80 lines) duplicates core logic with 3 other files.** [AI found]
  - This function at lines 144-223 implements schedule-aware 7-day completion calculation. Nearly identical logic exists in:
    - `GoalDetailView.activityRate`/`containerRate` (14-day window)
    - `GoalsView.consistencyScore` (14-day window)
    - `ScheduleEngine.completionStatus` (single day)
  - All four re-implement schedule-type switching, vacation filtering, skip handling, container child traversal, and multi-session counting.
  - **Refactor**: Build a general-purpose `completionRate(for:over:logs:vacationDays:activities:)` method on `ScheduleEngine` that accepts a date range. All three call sites simply pass different ranges (1 day, 7 days, 14 days). This would reduce ~300 lines of duplicated code to ~3 call sites.
  - **Impact**: High — this is the most impactful consolidation opportunity in the codebase.

- [76] **`ActivitiesListView` container removal/archive logic duplicates snapshot creation patterns.** [AI found]
  - Lines 170-196 in `ActivitiesListView.swift` contain "Future Only" and "Remove Everywhere" dialog handlers that create `ActivityConfigSnapshot` objects and manage parent/child relationships. Similar snapshot creation code exists in `AddActivityView.swift` for schedule changes.
  - **Refactor**: Extract snapshot creation into a service method (e.g., `ScheduleEngine.createSnapshot(for:changes:)`) so both views delegate.
  - **Impact**: Low-Medium — reduces risk of snapshot creation inconsistencies.

# Promoted for human review 

- [77-81] **Multi-session bugs: activities repeated multiple times per day (morning/afternoon/evening) incorrectly counted.** [AI found]
  - 5 bugs in `ScheduleEngine.swift` where multi-session activities were treated as single-session:
    - [77] `isContainerCompleted` passed if child had 1 of N sessions done
    - [78] `containerCompletionRate` same pattern
    - [79] `completionStatus` container children counted `total += 1` instead of `total += sessions`
    - [80] `currentStreak` used `Set<Date>` which collapsed all sessions to 1 per day
    - [81] `longestStreak` same issue
  - AI Reply: Fixed all 5 — container child checks now count completed logs vs `child.sessionsPerDay(on:)`. Streak logic replaced `completedDates` Set with new `isActivityDayCompleted` helper that compares completed log count against `sessionsPerDay(on:)`. Non-container `completionRate` and `completionStatus` were already correct.

- [82-87] **Multi-session skip, streak pass-through, carry-forward, and sticky bugs.** [AI found]
  - 6 more bugs from deeper audit of multi-session skip/carry-forward logic:
    - [82] `completionStatus` container child skip: partial skip (1/3 skipped, 2/3 completed) treated entire child as skipped — 2 completions lost
    - [83-84] `currentStreak`/`longestStreak` skip pass-through: `skippedDates` Set let partially-done days pass through as "excused"
    - [85] `containerStreak` skip: coarse `skippedDates` Set from any child skip let partially-done container days pass through
    - [86] `carriedForwardDate`: ANY completion/skip dismissed carry-forward, even if only 1/3 sessions done (weekly multi-session)
    - [87] `shouldShow` sticky: ANY completion hid sticky activity, even if only 1/3 sessions done
  - AI Reply: Fixed all 6 — (82) container child skip now checks `childCompleted == 0` before skipping. (83-84) Streak skip replaced with `isActivityDayFullySkipped` (skip && no completions). (85) Container streak replaced with `isContainerDayFullySkipped` (all children skipped, none completed). (86) Carry-forward now counts completions vs `sessionsPerDay`. (87) Sticky counts completed vs `sessionsPerDay`.

- [88] **DashboardView: multi-session only worked for checkbox/metric, not value type.** [AI found]
  - `isFullyCompleted` had multi-session check inside the checkbox/metric switch case only — value type checked ANY completion log.
  - `activityView` rendered `.value` as a single row with no slot awareness.
  - `logValue`/`removeValueLog`/`latestValue` had no slot parameter — couldn't distinguish per-session logs.
  - Result: logging one value session marked ALL sessions complete in the UI.
  - AI Reply: Fixed — unified `isFullyCompleted` multi-session check before type switch (applies to all types). Value type now renders per-slot with slot-aware `logValue(slot:)`, `removeValueLog(slot:)`, `latestValue(slot:)`. Cumulative is all-day, doesn't apply.

- [46] **Export/Import loses `aggregationModeRaw`** [AI found]
  - AI Reply: Fixed — added `aggregationModeRaw` to `ActivityDTO`: field, both initializers, custom decoder, export mapping, and import mapping. Older export files without this field gracefully decode as `nil` (defaults to `.sum`). No breaking changes.

- [47] **HealthKit sync overwrites ALL manual cumulative logs.** [AI found]
  - AI Reply: Fixed — changed from delete-all-and-replace to upsert strategy: finds existing "Synced from HealthKit"-tagged log and updates its value, or inserts a new one. Manual logs are never touched. Also fixed comparison to check against HK-tagged log value (not full cumulative total) to avoid false diffs on activities with both manual and HK entries.

- [48] **HealthKit unit mapping hardcoded to only `ml` and `count`.** [AI found]
  - AI Reply: Fixed — added `HealthKitService.unitFor(type:)` that looks up the correct HKUnit from `commonTypes` (steps→count, heart rate→bpm, weight→kg, etc.). Both `syncHealthKit()` and `writeToHealthKit()` now use this instead of hardcoded ml/count.

- [49] **Container analytics use live `activity.children` — retroactive mutation.** [AI found]
  - AI Reply: Fixed across 4 views (AnalyticsView, ActivityAnalyticsView, GoalDetailView, DashboardView vacation skip). All now use `historicalChildren(on:from:)`. Also enhanced the Activity model helper to filter by `createdDate`/`stoppedAt`—children that didn't exist or were stopped on a historical date are excluded.

- [50] **`streakFor` uses live children for container streak.** [AI found]
  - AI Reply: Fixed — `containerChildLogs` now uses `historicalChildren(on: log.date.startOfDay, ...)` per log date.

- [51] **`completionRate` for cumulative activities.** [AI found]
  - AI Reply: Re-examined — **NOT a real bug**. `min(dayCompleted, sessions)` caps at 1 for cumulative activities (sessionsPerDay = 1). Multiple log entries don't inflate the count. No change needed.

- [52] **`biggestWins` doesn't respect `aggregateDayValue` for cumulative activities.** [AI found]
  - AI Reply: Fixed — cumulative activities now use `aggregateMultiDayValue` (groups by day first, sums/averages daily values, then averages across days) instead of naive per-entry averaging.

- [53] **Vacation skip uses live `activity.children`.** [AI found]
  - AI Reply: Fixed — `createVacationSkipLogs` now uses `historicalChildren(on: date, from: allActivities)`.

- [54] **`ActivityAnalyticsView.effectiveLogs` uses live children.** [AI found]
  - AI Reply: Fixed — removed `!$0.isArchived` filter so archived children's historical logs are included for accuracy. `isContainerCompleted` and `valueForDay` both use `historicalChildren`.

- [55] **`ActivityAnalyticsView.valueForDay` uses live children.** [AI found]
  - AI Reply: Fixed — see [54], both addressed together.

- [56] **`completionFraction` counts no-target cumulatives (always incomplete).** [AI found]
  - AI Reply: Fixed — no-target cumulative activities are now excluded from the progress bar calculation (`targetValue == nil || targetValue == 0` → skip). They have no completion concept and shouldn't drag down progress.

- [57] **`allDone` doesn't account for all-day cumulative activities.** [AI found]
  - AI Reply: Re-examined — **NOT a real bug**. `allDone` checks `pendingTimed.isEmpty` which correctly excludes cumulative all-day activities. The "All done! 🎉" message correctly triggers when all timed/sticky activities are complete. No change needed.

- [58] **Carry-forward uses current schedule for lookback.** [AI found]
  - AI Reply: Fixed — each historical day in the lookback loop now resolves its own `scheduleActive(on: checkDate)` instead of reusing the reference date's schedule. Consequence check: verified that `scheduleActive` correctly falls back to current schedule when no snapshot exists, so no regression for activities without snapshots.

- [59] **`GoalDetailView.containerRate` inflates score on days with 0 scheduled children.** [AI found]
  - AI Reply: Fixed — days with no scheduled children now `continue` (skip) instead of incrementing `fullyCompleted`. Also fixed children to be resolved per-day inside the loop.

- [60] **`pendingTimedIncludingPartial` dead code.** [AI found]
  - AI Reply: Fixed — removed the dead computed property (identical to `pendingTimed`, never referenced).

- [61] **Label says "7 days" but code uses 14 days.** [AI found]
  - AI Reply: Fixed — label updated to "Activity Consistency (14 days)" to match the `1..<15` range in `activityRate`.

- [62] **Photo metric thumbnails show placeholders instead of actual photos.** [AI found]
  - AI Reply: Fixed — thumbnails now load actual images via `MediaService.shared.loadPhoto(filename:)` with fallback to the previous placeholder icon when photo file is missing.
# Promoted for human review 
- [45] **App crashes at `getValue(forKey: \.createdAt)` when opening Goals.** `createdAt` was declared non-optional (`Date = Date()`) but SwiftData stores it as nullable in SQLite. Records created before the column was added have NULL, causing a fault crash. [User reported]
  - AI Reply: Fixed — made `createdAt` optional (`Date?`) in both Activity and Goal models. Added `createdDate` computed property (`createdAt ?? Date.distantPast`) as safe accessor. Updated all ~22 callsites across 8 files. Also added startup migration to clean orphaned GoalActivity links.
- [39] `streakFor` always reports 0 for container activities. [AI found]
  - AI Reply: Fixed — added container branch that checks all children's completion per day via new `isContainerCompleted` helper. Schedule-aware, vacation-aware.
- [40] `mostImproved` always reports 0 for containers. [AI found]
  - AI Reply: Fixed — container branch aggregates children's logs (by child IDs) for both this-week and last-week counts.
- [41] AnalyticsView `completionRate` uses live `activity.children` — retroactive mutation issue. [AI found]
  - AI Reply: Fixed — `completionRate` for containers now does per-day iteration using `isContainerCompleted` helper (checks children's logs per day) instead of aggregating live children's individual rates.
- [43] Container archive doesn't cascade to children. [AI found]
  - AI Reply: Fixed — `archiveActivity` now cascades `isArchived = true` to all children when archiving a container.
- [44] `isFullyCompleted` returns `true` for empty containers. [AI found]
  - AI Reply: Fixed — empty/childless containers now return `false` instead of `true`, preventing them from appearing in Completed section.

- [24] `streakFor` doesn't respect activity schedule. [AI found]
  - AI Reply: Fixed — `streakFor` now checks `scheduleActive(on:)` for each day and skips non-scheduled days without breaking streak. Also added `createdAt` bounds check.
- [25] Appearance auto-suggest doesn't re-fire on type/metricKind change. [AI found]
  - AI Reply: Fixed — added `.onChange(of: selectedType)` and `.onChange(of: selectedMetricKind)` triggers that re-call `ActivityAppearance.suggest()` when `appearanceAutoSet` is true.
- [26] Container shows in slot even when all children in that slot are completed. [AI found]
  - AI Reply: Fixed — `groupedBySlot` now checks both slot membership AND pending status (not completed/skipped) before including container in a slot.
- [27] `completionFraction` doesn't account for container slot expansion. [AI found]
  - AI Reply: Fixed — containers now count their applicable children count instead of 1. Multi-session activities count their slot count. Progress bar reflects actual work items.
- [28] `containerRate` in GoalDetailView ignores individual child schedules. [AI found]
  - AI Reply: Fixed — `containerRate` now intersects container schedule with each child's `scheduleActive(on:)`, only checking children scheduled on each specific day.
- [29] GoalDetailView `dayCell` doesn't handle containers. [AI found]
  - AI Reply: Fixed — `dayCell` now checks if all non-archived children are completed on that date for container-type activities.
- [30] Notification permission not requested on first toggle. [AI found]
  - AI Reply: Fixed — `rescheduleAll()` now calls `requestAuthorization()` before scheduling when any reminder is enabled.
- [31] Can link both container AND its child to same goal (double-counting). [AI found]
  - AI Reply: Fixed — unlinked activities list now filters out children whose parent container is already linked.
- [32] AnalyticsView `overallScore` ignores per-day schedules. [AI found]
  - AI Reply: Fixed — `overallScore` now filters `topLevelActivities` by schedule for each day. Containers check children's completion instead of their own logs.
- [33] Container `isSkipped` doesn't handle completed+skipped mix. [AI found]
  - AI Reply: Fixed — `isSkipped` now filters out completed children first, then checks if all remaining are skipped. Prevents containers falling through the cracks.
- [34] Multi-session child inside container doesn't track per-slot completion. [AI found]
  - AI Reply: Fixed — `childCompletion` now checks per-slot completion for multi-session children, using `slotFilter` when available.
- [35] "Mark All Done" only marks checkbox children. [AI found]
  - AI Reply: Fixed — filter changed from `$0.type == .checkbox` to `$0.type != .container`, including all completable types.
- [36] `removeLastCumulativeLog` takes first instead of last. [AI found]
  - AI Reply: Fixed — changed `.first(where:)` to `.last(where:)`.
- [37] AnalyticsView `completionRate` reports 0% for containers. [AI found]
  - AI Reply: Fixed — `completionRate` now aggregates children's completion rates for container-type activities.
- [38] Multi-session `isSkipped` doesn't account for completed sessions. [AI found]
  - AI Reply: Fixed — `isSkipped` for multi-session now filters out completed sessions first, then checks if remaining are all skipped.
- [23] Big change, Not sure how to handle this... but right now changing container or any activity changes past records. That should not happen always.. if i change who are container sub-children, it shouldnt change past records.. analytics wont change too much either anyways here. For activity maybe include stop doing it thingy.. but even edit of cadence etc.. shouldnt always change past records.. maybe make these changes like google calendar (ask for future changes only, all changes).. but then if it does change past values.. data needs to be preserved so take smart actions and you might have to restrict what can be changed for past ones exclusively, etc.
  - AI Reply: Implemented via Config Snapshots (ADR-7). New `ActivityConfigSnapshot` model stores time-bounded structural config (schedule, type, time window, target, parent). When editing structural fields of an activity with existing logs, a dialog asks "Future Only" or "All Changes". "Future Only" saves old config as a snapshot, then mutates — analytics uses the snapshot for historical dates. Added `stoppedAt: Date?` on Activity for Stop/Resume tracking. `ScheduleEngine`, `AnalyticsView.completionRate`, and `streakFor` all use version-appropriate config. Stop/Resume buttons in editor + context menus. Stopped badge in activities list. Export/import includes snapshots. Docs updated.
  - Human Feedback: Past view still updating with Future Only. Archive renames item (bad). New sub-activities appear in past. Remove from container needs dialog. Structural/cosmetic detection fragile.
  - AI Reply: 5 fixes: (1) `ScheduleEngine.shouldShow` now uses `scheduleActive(on: date)` (snapshot-aware) instead of `activity.schedule` (current). (2) Simplified edit dialog — always asks "Future Only / All Changes" when activity has logs (removed brittle `hasStructuralChanges`). (3) `createdAt` check in `shouldShow` — new sub-activities don't appear on past dates. (4) "Remove from Container" now shows dialog: "Future Only" (snapshot old parent + archive) vs "Remove Everywhere" (delete). (5) Archived section enhanced with Unarchive + Delete Permanently context menu. Archive does NOT rename — it sets `isArchived = true` and moves to archived section.
- [12] Photo cadence: New `PhotoCadence` enum (everyTime/weekly/monthly/never). `Activity.photoCadence` field added. `AddActivityView` shows cadence picker when photo tracking is enabled (defaults to Weekly). Dashboard completion flow calls `isPhotoDue(for:)` — checks last photo date vs cadence — and shows camera sheet via `CameraView` if behind schedule. User can skip or take photo. Photos saved via `MediaService`.
  - AI Reply: Created `PhotoCadence.swift`, added `photoCadenceRaw` to `Activity` model, integrated picker into `AddActivityView`, added `isPhotoDue(for:)` helper and `photoPromptActivity` sheet to `DashboardView.completeCheckbox`. Full flow: toggle photo → pick cadence → complete activity → camera prompt if overdue → save or skip.
  - Human Feedback: Not seeing this still. Also, have soft way of adding photo always, so like for checkbox, have prompt depending on schedule, for value during value creation have extra button "add photo", if behind still have explicit prompt after entering value, for cumulative you can assume photo won't exist (remove it from the activity creation flow too).
  - AI Reply: Reworked per-type: (1) Cumulative activities — photo toggle now hidden in `AddActivityView` (also resets when switching to cumulative). (2) Value activities — `ValueInputRow` now has `onTakePhoto` callback: inline camera icon button + "Add Photo" in context menu; after `logValue`, if behind on cadence, auto-triggers photo prompt sheet. (3) Checkbox — keeps existing cadence-based prompt after completion. Shared `triggerPhotoPrompt(for:log:)` helper used across both flows.
- [11] Container skip section: `ContainerRowView` header now has context menu with "Complete All", "Skip All Pending" (with reason dialog), and "Undo All" actions. This restores interaction that was lost when the outer dashboard context menu was removed in [14].
  - AI Reply: Added `.contextMenu` to `ContainerRowView`'s header `Button` with Complete All (checkbox children), Skip All Pending (with `confirmationDialog` for reason), and Undo All (when fully completed). Uses existing `pendingChildren`/`completedChildren` computed properties.
  - Human feedback: skipped system is still fucked, now every tag says skip all, complete all. Containers should have that, others should have skip, complete, etc. Also once skipped i can't undo it past the temporary undo period, maybe include skipped section at very bottom. just like completed, and allow things to unskip there. Another bug is once I skip in container, it still has "mark all as done" maybe remove that too.
  - AI Reply: Three fixes: (1) Added **Skipped section** to `DashboardView` below Completed — `DisclosureGroup` with orange styling, skip reason capsules, and **Unskip** button per activity (deletes the skip log). (2) Container `ContainerRowView` — changed "Mark All Done" condition from `doneCount < todayChildren.count` to `!pendingChildren.isEmpty` so it hides when only skipped children remain. (3) Context menu now uses `!pendingChildren.isEmpty` and `!completedChildren.isEmpty` independently so Complete All + Undo All can both appear when some are completed and some are pending. Non-container `ActivityRowView` already had correct individual Skip/Complete menu — verified no leaking.
  - Human feedback: Container skip is not going to skipped section after skip all.
  - AI Reply: Root cause was `isSkipped` only checked direct skip logs — containers don't get their own skip log, children do. Fixed `isSkipped` to be container-aware (all today-applicable children skipped → container is skipped). Also fixed `unskipActivity` to unskip all children for containers, and `skipReason` to return first child's reason. Unskip button now says "Unskip All" for containers.
- [19] Same activity should be allowed to be done multiple times in a day specifically Morning, afternoon, and evening.. this might not be a simple change look into it carefully
  - AI Reply: Implemented multi-session support. New `timeSlotsData` on Activity stores `[TimeSlot]` array. New `timeSlotRaw` on ActivityLog disambiguates which session was completed/skipped. Dashboard expands multi-session activities into one row per time slot, each independently completable. `AddActivityView` has "Repeat across time periods" toggle with Morning/Afternoon/Evening checkboxes. `completionFraction` and analytics `completionRate` count per-session. Export/import DTOs updated. Fully backward compatible — existing activities work unchanged.
- [20] let's revamp activities page. Goal here is to make it really easy to edit, add and organize activites. Have easy way to create dummy containers, and activities. Organizing sub-actions in containers ... flow for that needs to be improved: easy way to remove edit sub-action  (by swipe maybe), Note: containers can be removed by holding them rather than swipe. right now containers are first class as actions in view kinda.. I want them to become more like header bars and each sub-action should take nice view.. 
  - AI Reply: Redesigned `ActivitiesListView`: containers now render as **section headers** (colored accent bar, icon, name, child count badge, expand/collapse chevron) with context menu (Edit Container, Apply Style, Archive, Delete). Sub-activities are full rows with **swipe actions** (Edit, Delete) and context menu (Edit, Remove from Container, Archive, Delete). Added **quick-add `+` button** on container headers → opens `AddActivityView` pre-configured with that container as parent via new `presetParent` parameter. Enriched `infoTags`: time slot, multi-session (N× Daily), photo cadence, notes enabled. Also addresses [9] feedback.
- [89] ContainerRowView `childCompletion` for `.value` type ignores multi-session — only checks any completed log, not per-slot. [AI found]
  - AI Reply: Fixed — `.value` case now checks per-slot completion for multi-session children, using `slotFilter` when available and fractional scoring (done/total) otherwise.
- [90] ContainerRowView `isChildSkipped` ignores multi-session — reports skipped if ANY skip log exists. [AI found]
  - AI Reply: Fixed — multi-session children now check all non-completed sessions are skipped before marking child as skipped.
- [91] ActivityAnalyticsView `valueForDay` for `.value`/`.metric` uses `.last` instead of averaging multi-session values. [AI found]
  - AI Reply: Fixed — `.value` and `.metric` cases now average all completed values for the day instead of using `.last`.
- [92] ActivityAnalyticsView `valueForDay` for `.container` uses boolean `.contains` per child, not session-aware. [AI found]
  - AI Reply: Fixed — container completion now uses fractional scoring per child (`done/sessionsPerDay`) instead of boolean complete/not-complete.
- [93] ValueChartView `dailyPoints` uses `.last?.value` for non-cumulative activities. [AI found]
  - AI Reply: Fixed — now averages all values for the day via `compactMap(\.value)` + `reduce(0, +) / count`.
- [94] DashboardView `createVacationSkipLogs` creates one skip log for multi-session activities instead of per-slot. [AI found]
  - AI Reply: Fixed — multi-session activities now get per-slot skip logs with `timeSlotRaw` set, matching `isSkipped` per-slot checking.
- [95] `completionStatus` treats partially-skipped multi-session as fully skipped. [AI found]
  - AI Reply: Fixed — refactored into shared `processActivitySlots` helper using `timeSlotsActive(on:)` for snapshot-aware per-slot counting. Skipped sessions deducted from denominator.
- [96] `completionStatus` container children: can't resolve children when called with `activities: [container]` for per-activity heatmap. [AI found]
  - AI Reply: Fixed — added `allActivities` param to `completionStatus`. Container branch uses `historicalChildren(from: allActivities)`.
- [97] `completionRate` uses `activity.timeSlots` (current) not snapshot-aware slots. [AI found]
  - AI Reply: Fixed — now uses `timeSlotsActive(on: day)` for historical accuracy.
- [98] Completed/Skipped sections only show multi-session activities when ALL sessions are done/skipped. [User reported]
  - AI Reply: Fixed — `completed` now includes activities with ANY completed session. `skippedActivities` includes activities with ANY skipped session. Per-slot rendering shows individual sessions in each section.
- [99] Per-activity heatmap returns .noData for child activities — `activitiesForToday` filters `parent == nil`. [AI found]
  - AI Reply: Fixed — single-activity mode in `completionStatus` bypasses `activitiesForToday` and checks `shouldShow` directly.
- [100] `activity.timeSlots` vs `sessionsPerDay(on:)` snapshot mismatch in per-slot iteration. [AI found]
  - AI Reply: Fixed — added `Activity.timeSlotsActive(on:)` and `isMultiSession(on:)` for snapshot-aware slot iteration. Used throughout ScheduleEngine.
- [101] `completionFraction` in DashboardView treated entire multi-session as skipped/not-skipped instead of per-slot. [AI found]
  - AI Reply: Fixed — per-slot counting with skipped sessions deducted from denominator, matching ScheduleEngine logic.
- [102] ContainerRowView `onCompleteChild`/`onSkipChild` callbacks don't pass TimeSlot — multi-session children completed/skipped as single-session. [AI found]
  - AI Reply: Fixed — callbacks changed to `(Activity, TimeSlot?) -> Void` and `(Activity, String, TimeSlot?) -> Void`. `childRow` passes `slotFilter`. DashboardView caller updated to pipe slot to `completeCheckbox`/`skipActivity`.
- [103] ContainerRowView `completedChildren`/`skippedChildren` require ALL sessions done/skipped for multi-session children — partial completions stuck in pending. [AI found]
  - AI Reply: Fixed — buckets now use per-slot checks: ANY completed session → `completedChildren`, ANY skipped session → `skippedChildren`, ANY pending session → `pendingChildren`.
- [104] ContainerRowView `doneCount` counts fully-completed children, not sessions — shows incorrect progress for multi-session. [AI found]
  - AI Reply: Fixed — `doneCount` and `totalCount` now count individual sessions for multi-session children, respecting `slotFilter`.


# Human Approved Bugs:
- [7] Undo toast position: Moved from bottom to top of screen so it doesn't overlap with FAB or other bottom UI. Animation updated to slide down from top. Test: Complete/uncomplete any activity → verify undo toast appears at the top.
  - AI Reply: Fixed — `UndoToastModifier` changed from `ZStack(alignment: .bottom)` to `.top` with matching slide-down animation offset.
- [2] Edit/Undo past actions: Cumulative activities now have "View Entries" in context menu everywhere (both ALL DAY rings and time-slot rows). Long-press a cumulative ring → "View Entries" → opens `CumulativeLogSheet` with swipe-to-delete individual logs and Save confirmation. Works for both completed and non-completed cumulative activities.
  - Human Feedback: I cant add cumulative one unless it's completed.. I want to in-general be allowed to update cumulative ones same way even when they are not completed
  - AI Reply: Fixed — removed `currentValue != nil` guard so "View Entries" is always available in context menu for cumulative activities, regardless of completion status.
  - Human feedback: I still don't know how to edit it in UI like remove old inputs for non completed cumulative actions.
  - AI Reply: Root cause found — cumulative activities show in the ALL DAY section via `CumulativeRingView` which had no context menu (only tap-to-add). Added context menu with "Add Entry" and "View Entries" to `CumulativeRingView`, wired through `AllDaySection` to open `CumulativeLogSheet`. Long-press the ring circle → "View Entries" to manage individual logs.
- [13] Flat progress bars for ALL DAY + master bar: `CumulativeRingView` redesigned from 60x60 circular ring to flat horizontal row. Master `ProgressRingView` also flattened from 100px circle to thick 14px gradient progress bar with percentage label.
  - AI Reply: Both rings converted to flat bars. `CumulativeRingView` is now a compact row (icon + name + 6px bar + value + plus button). `ProgressRingView` is a 14px thick rounded gradient bar with "Today's Progress" label and percentage — ~54px total vs 110px. `AllDaySection` changed from horizontal ScrollView to vertical stacking.
  - Human feedback: Do this for Whole day completion ring too → Done (see above).
- [14] Context menu standardization: Removed Edit/Delete/View Details from dashboard context menus — dashboard is now action-only (Skip, Complete, Undo, Add Entry, View Entries). Edit/Delete/Archive moved to new Activities management tab.
  - AI Reply: Removed outer `.contextMenu` from `DashboardView.activityView(for:)` and `detailActivity` state/sheet. Each row type already has its own action-oriented context menu. Management operations now live in `ActivitiesListView` (Activities tab).

- [10] Vacation analytics: `completionRate(for:)` now excludes vacation days from denominator — previously divided by 7.0 which penalized activities during vacation. `HeatmapView` already displays vacation cells (blue + ✈️ icon) and tooltip. `streakFor`, `mostImproved`, `overallScore` all already handled vacations. `ValueChartView` naturally excludes vacations (data-point driven).
  - AI Reply: The only remaining gap was `completionRate` which divided by 7.0 regardless of vacation days. Now counts only non-vacation eligible days and excludes vacation-day completions from numerator.

- [8] Photo adding for activities: "View Details" context menu now works (fixed broken `NavigationLink` — replaced with `Button` + `.sheet`). Long-press any activity → "View Details" → `ActivityDetailView` with camera for photo-enabled activities.
  - Human feedback: There is no view detail option when I long press on any activity still. Also that sounds like a bad menthodology.. ask for cadence of photo capture for photo enabled activities during activity creation. And request user to ask for photo at that cadence, (everytime, weekly, monthly, etc. and if user hasnt provided photo within that period ask user when completing the action.). Make IT easy to add photo and part of acceptance flow naturally but only when it's behind shedule
  - AI Reply: Fixed "View Details" — `NavigationLink` doesn't work inside `.contextMenu` in SwiftUI, replaced with `Button` + `.sheet(item:)` for reliable navigation. Photo cadence redesign (prompt during completion flow based on schedule) moved to new bug [12] in backlog — this is a significant design change requiring new model fields, UI in `AddActivityView`, and integration into the completion flow.
  - Human Feedback: I still don't see any option to view details when I long press on any activity. IGNORE THIS FOR NOW, KEEP THIS PENDING, AND WE WILL REVISIT. 

- [9] Activities management tab: Collapsible container children (DisclosureGroup-style with dropdown arrow) + richer info tags (type, schedule, target/unit, HealthKit, photo+cadence, weight). Container children are indented with colored bar and display their own tags.
  - AI Reply: Refactored `activityRow` to `activityRowContent` + expandable children section. Added `FlowLayout` for tag wrapping. Tags show: type badge, schedule, target/unit, HealthKit status, photo cadence, weight (if ≠1). `expandedContainers` state tracks open containers.
  - Human Feedback: I cant see child activites right now, i thought they will be collapsbale somehow.. maybe add dropdown arrow to show them on containers. Also add more relevant things in the tags to know if health kit is enabled, is photo enabled, what's target, everything kinda, you know?
  - AI Reply: Addressed via [20] revamp. Containers now have clear expand/collapse chevron. Children are collapsible rows with full info tags (type, schedule, time slot, multi-session, target, HealthKit, photo+cadence, notes, weight). Swipe-to-edit/delete children added.