# Data Format Documentation

The Daily Activity Tracker uses a JSON-based format for importing and exporting data. This document describes the structure of the JSON file so users can manually construct or modify data for import.

## Schema Overview

The root of the JSON file is an object. Version `2.0` adds workout-domain arrays (all optional for backward compat with v1.0 imports).

```json
{
  "version": "2.0",
  "timestamp": "2026-02-15T12:00:00Z",
  "categories": [ ... ],
  "activities": [ ... ],
  "logs": [ ... ],
  "vacationDays": [ ... ],
  "configSnapshots": [ ... ],
  "goals": [ ... ],
  "goalActivities": [ ... ],
  "exercises": [ ... ],
  "exerciseMuscles": [ ... ],
  "muscleGroups": [ ... ],
  "workoutPlans": [ ... ],
  "workoutPlanDays": [ ... ],
  "strengthPlanExercises": [ ... ],
  "cardioPlanExercises": [ ... ],
  "strengthSessions": [ ... ],
  "workoutSetLogs": [ ... ],
  "cardioSessions": [ ... ],
  "cardioSessionLogs": [ ... ]
}
```


---

## 1. Categories

Defines the grouping folders for activities.

```json
{
  "id": "UUID-STRING",
  "name": "Health",
  "icon": "heart.fill",
  "hexColor": "#FF0000",
  "sortOrder": 0
}
```

| Field       | Type   | Description                         |
| :---------- | :----- | :---------------------------------- |
| `id`        | UUID   | Unique identifier.                  |
| `name`      | String | Display name.                       |
| `icon`      | String | SF Symbol name (e.g., "star.fill"). |
| `hexColor`  | String | Hex color code (e.g., "#RRGGBB").   |
| `sortOrder` | Int    | Order in the list (ascending).      |

---

## 2. Activities

Defines the trackers themselves.

```json
{
  "id": "UUID-STRING",
  "name": "Drink Water",
  "icon": "drop.fill",
  "hexColor": "#0099FF",
  "typeRaw": "cumulative",
  "targetValue": 2500,
  "unit": "ml",
  "aggregationModeRaw": "sum",
  "metricKindRaw": null,
  "sortOrder": 0,
  "isArchived": false,
  "createdAt": "2026-01-01T00:00:00Z",
  "categoryID": "UUID-OF-CATEGORY",
  
  // Encoded Schedule (Daily by default if null)
  "scheduleData": "BASE64-ENCODED-JSON-STRING",
  
  // Encoded TimeWindow (Optional)
  "timeWindowData": "BASE64-ENCODED-JSON-STRING",
  
  // Encoded [TimeSlot] array for multi-session activities (Optional)
  "timeSlotsData": "BASE64-ENCODED-JSON-STRING",
  
  // Optional: date when activity was paused
  "stoppedAt": "2026-06-01T00:00:00Z",
  
  // Optional: remembers container parent when paused
  "pausedParentId": "UUID-OF-FORMER-CONTAINER",
  
  // Carry forward missed weekly/monthly occurrences (default: false, metrics default: true)
  "carryForward": true,
  
  // Optional: when true, this is a passive HK-only metric (hidden from dashboard)
  "isPassive": false,
  
  // Encoded [String] array of named photo slots (Optional, photo-metric only)
  // Default: ["Photo"] for single-slot backward compat
  "photoSlotsData": "BASE64-ENCODED-JSON-STRING"
}
```

### Key Fields

- **`typeRaw`**: One of `"checkbox"`, `"value"`, `"cumulative"`, `"container"`, `"metric"`.
- **`metricKindRaw`**: Only for `metric` type — one of `"photo"`, `"value"`, `"checkbox"`, `"notes"`.
- **`aggregationModeRaw`**: Only for `cumulative` type — `"sum"` (default) or `"average"`. Controls how multiple daily entries are aggregated.
- **`isPassive`**: When `true`, the activity is a silent HealthKit-only metric — hidden from the dashboard and daily completion %, but visible in the Activities tab "Health Metrics" section and linkable to Goals.
- **`scheduleData`** / **`timeWindowData`**: These are `Data` blobs in Swift, serialized as Base64 strings in the JSON.
    - *Note for manual editing*: It is difficult to manually construct these Base64 strings. It is recommended to create a dummy activity in the app, export it, and copy the strings if needed.

---

## 3. Logs

Records of activity completion.

```json
{
  "id": "UUID-STRING",
  "activityID": "UUID-OF-ACTIVITY",
  "date": "2026-02-15T00:00:00Z",
  "statusRaw": "completed",
  "value": 500,
  "completedAt": "2026-02-15T08:30:00Z",
  "photoFilename": null,
  "photoFilenamesData": null,
  "skipReason": null,
  "timeSlotRaw": "morning",
  "source": "healthkit"
}
```

| Field                | Type    | Description                                                                |
| :------------------- | :------ | :------------------------------------------------------------------------- |
| `activityID`         | UUID    | ID of the parent activity.                                                 |
| `date`               | ISO8601 | The "Day" of the log (usually 00:00:00 time).                              |
| `statusRaw`          | String  | `"completed"` or `"skipped"`.                                              |
| `value`              | Double  | (Optional) Numeric value for value/cumulative types.                       |
| `completedAt`        | ISO8601 | (Optional) Exact timestamp of completion.                                  |
| `photoFilename`      | String  | (Optional) Legacy single photo filename.                                   |
| `photoFilenamesData` | Data    | (Optional) JSON-encoded `{"slot": "filename"}` dict for multi-slot photos. |
| `timeSlotRaw`        | String  | (Optional) Session slot: `"morning"`, `"afternoon"`, `"evening"`.          |
| `source`             | String  | (Optional) `nil` = manual, `"healthkit"` = synced from Apple Health.       |

---

## 4. Vacation Days

Days where streaks are preserved.

```json
{
  "date": "2026-02-20T00:00:00Z"
}
```

---

## Workflow: Manual Data Entry

To bulk-import data from another system (like a CSV):
1.  **Export** a backup from the app to get a template.
2.  **Generate UUIDs** for your new items.
3.  **Format** your data into the JSON structure above.
4.  **Date Format**: Ensure all dates are ISO 8601 strings (e.g., `YYYY-MM-DDTHH:MM:SSZ`).
5.  **Import** the modified JSON file back into the app.

> **Warning**: The Import function creates a **Clean State** before importing. All existing data on the device will be replaced by the contents of the import file.

---

## 5. Config Snapshots

Preserves historical activity config when "Future Only" edits are made.

```json
{
  "id": "UUID-STRING",
  "activityID": "UUID-OF-ACTIVITY",
  "effectiveFrom": "2026-01-01T00:00:00Z",
  "effectiveUntil": "2026-03-14T00:00:00Z",
  "scheduleData": "BASE64-ENCODED-JSON",
  "timeWindowData": "BASE64-ENCODED-JSON",
  "timeSlotsData": "BASE64-ENCODED-JSON",
  "typeRaw": "checkbox",
  "targetValue": null,
  "unit": null,
  "parentID": "UUID-OF-CONTAINER-OR-NULL"
}
```

| Field            | Type    | Description                                                  |
| :--------------- | :------ | :----------------------------------------------------------- |
| `effectiveFrom`  | ISO8601 | Start of this config period.                                 |
| `effectiveUntil` | ISO8601 | End of this config period (day before the edit took effect). |
| `parentID`       | UUID    | (Optional) Container this activity belonged to at the time.  |

---

## 6. Goals

Defines overarching objectives that link to daily activities.

```json
{
  "id": "UUID-STRING",
  "title": "Reduce Body Fat %",
  "icon": "flame.fill",
  "hexColor": "#FF3B30",
  "deadline": "2026-06-01T00:00:00Z",
  "isArchived": false,
  "createdAt": "2026-02-15T00:00:00Z",
  "sortOrder": 0
}
```

| Field        | Type    | Description                                                                                             |
| :----------- | :------ | :------------------------------------------------------------------------------------------------------ |
| `title`      | String  | Goal name.                                                                                              |
| `icon`       | String  | SF Symbol name.                                                                                         |
| `hexColor`   | String  | Hex color code.                                                                                         |
| `deadline`   | ISO8601 | (Optional) Target completion date.                                                                      |
| `isArchived` | Bool    | Legacy field, always `false`. Goals are now auto-paused when all linked activities/metrics are stopped. |
| `sortOrder`  | Int     | Display order.                                                                                          |

---

## 7. Goal Activities (Junction)

Links goals to activities with a role (`activity` for habits, `metric` for outcome measurements). Metric-role links carry baseline/target/direction config.

```json
{
  "id": "UUID-STRING",
  "goalID": "UUID-OF-GOAL",
  "activityID": "UUID-OF-ACTIVITY",
  "roleRaw": "metric",
  "weight": 1.0,
  "metricBaseline": 25.0,
  "metricTarget": 18.0,
  "metricDirectionRaw": "decrease"
}
```

| Field                | Type   | Description                                    |
| :------------------- | :----- | :--------------------------------------------- |
| `goalID`             | UUID   | References a Goal.                             |
| `activityID`         | UUID   | References an Activity.                        |
| `roleRaw`            | String | `"activity"` or `"metric"`.                    |
| `weight`             | Double | Importance weight for scoring (default 1.0).   |
| `metricBaseline`     | Double | (Optional) Starting value for metric tracking. |
| `metricTarget`       | Double | (Optional) Target value for metric tracking.   |
| `metricDirectionRaw` | String | (Optional) `"increase"` or `"decrease"`.       |

> [!NOTE]
> GoalMeasurement was removed in the metrics-as-activities redesign. Outcome metrics are now tracked via standard ActivityLog entries on metric-role activities.

---

## 8. Exercises (v2.0)

```json
{
  "id": "UUID-STRING",
  "name": "Bench Press",
  "equipment": "Barbell",
  "exerciseTypeRaw": "strength",
  "aliasesData": null,
  "videoURLsData": null,
  "notes": null,
  "distanceUnit": null,
  "paceUnit": null,
  "availableMetricsData": null,
  "isPreSeeded": false,
  "createdAt": "2026-01-01T00:00:00Z"
}
```

| Field             | Type   | Description                                     |
| :---------------- | :----- | :---------------------------------------------- |
| `exerciseTypeRaw` | String | `"strength"`, `"cardio"`, or `"timed"`.         |
| `equipment`       | String | Equipment name (e.g., "Barbell", "Bodyweight"). |
| `distanceUnit`    | String | (Optional) For cardio: `"km"`, `"mi"`.          |
| `paceUnit`        | String | (Optional) For cardio: `"/km"`, `"/mi"`.        |

---

## 9. Exercise Muscles (v2.0)

Junction linking exercises to muscle groups.

| Field              | Type   | Description                            |
| :----------------- | :----- | :------------------------------------- |
| `exerciseID`       | UUID   | References an Exercise.                |
| `muscleGroupID`    | UUID   | (Optional) References a MuscleGroup.   |
| `involvementScore` | Double | 0.0–1.0 indicating muscle involvement. |

---

## 10. Muscle Groups (v2.0)

| Field         | Type   | Description                           |
| :------------ | :----- | :------------------------------------ |
| `name`        | String | Muscle group name.                    |
| `parentID`    | UUID   | (Optional) Parent muscle group ID.    |
| `mevSets`     | Int    | Minimum Effective Volume (sets/week). |
| `mavSets`     | Int    | Maximum Adaptive Volume.              |
| `mrvSets`     | Int    | Maximum Recoverable Volume.           |
| `isPreSeeded` | Bool   | Whether pre-seeded by the app.        |

---

## 11. Workout Plans (v2.0)

| Field                 | Type   | Description                              |
| :-------------------- | :----- | :--------------------------------------- |
| `name`                | String | Plan name (e.g., "Push Pull Legs").      |
| `planTypeRaw`         | String | `"strength"`, `"cardio"`, or `"timed"`.  |
| `statusRaw`           | String | `"active"`, `"paused"`, `"deactivated"`. |
| `containerActivityID` | UUID   | (Optional) Linked container Activity.    |

---

## 12. Workout Plan Days (v2.0)

| Field               | Type   | Description                             |
| :------------------ | :----- | :-------------------------------------- |
| `weekday`           | Int    | 1=Mon … 7=Sun.                          |
| `dayLabel`          | String | Display label (e.g., "Push A", "Rest"). |
| `isLabelOverridden` | Bool   | Whether the label was manually set.     |
| `isRest`            | Bool   | Whether this is a rest day.             |
| `colorGroup`        | Int    | Color group index for UI.               |
| `planID`            | UUID   | References a WorkoutPlan.               |

---

## 13. Strength Plan Exercises (v2.0)

| Field           | Type   | Description                        |
| :-------------- | :----- | :--------------------------------- |
| `targetSets`    | Int    | Number of target sets.             |
| `rir`           | Int    | Reps In Reserve.                   |
| `sortOrder`     | Int    | Display order within the day.      |
| `supersetGroup` | String | (Optional) Group ID for superset.  |
| `exerciseID`    | UUID   | (Optional) References an Exercise. |
| `planDayID`     | UUID   | References a WorkoutPlanDay.       |

---

## 14. Cardio Plan Exercises (v2.0)

| Field               | Type   | Description                                |
| :------------------ | :----- | :----------------------------------------- |
| `sessionTypeRaw`    | String | `"steadyState"`, `"hiit"`, `"tempo"`, etc. |
| `targetDistance`    | Double | (Optional) Target distance.                |
| `targetDurationMin` | Int    | (Optional) Target duration in minutes.     |
| `sessionParamsData` | Data   | (Optional) Encoded session parameters.     |
| `exerciseID`        | UUID   | (Optional) References an Exercise.         |
| `planDayID`         | UUID   | References a WorkoutPlanDay.               |

---

## 15. Strength Sessions (v2.0)

Logs a completed strength workout. Stores snapshot data so the session is self-contained even if the plan changes.

| Field                    | Type    | Description                             |
| :----------------------- | :------ | :-------------------------------------- |
| `planName`               | String  | Snapshot of plan name.                  |
| `dayLabel`               | String  | Snapshot of day label.                  |
| `weekday`                | Int     | Day of week (1=Mon).                    |
| `date`                   | ISO8601 | Session date.                           |
| `startedAt`              | ISO8601 | When the session started.               |
| `endedAt`                | ISO8601 | (Optional) When the session ended.      |
| `totalPausedSeconds`     | Double  | Total paused time.                      |
| `statusRaw`              | String  | `"inProgress"`, `"completed"`, etc.     |
| `resumedAtSetCount`      | Int     | Set count when resumed.                 |
| `resumedAtPausedSeconds` | Double  | Paused seconds when resumed.            |
| `planDayID`              | UUID    | (Optional) References a WorkoutPlanDay. |

---

## 16. Workout Set Logs (v2.0)

Individual set records within a strength session.

| Field             | Type    | Description                        |
| :---------------- | :------ | :--------------------------------- |
| `setNumber`       | Int     | Set number within the exercise.    |
| `reps`            | Int     | Number of reps completed.          |
| `weight`          | Double  | Weight used.                       |
| `durationSeconds` | Int     | (Optional) For timed sets.         |
| `isWarmup`        | Bool    | Whether this was a warmup set.     |
| `completedAt`     | ISO8601 | Timestamp of set completion.       |
| `exerciseID`      | UUID    | (Optional) References an Exercise. |
| `sessionID`       | UUID    | References a StrengthSession.      |

---

## 17. Cardio Sessions (v2.0)

| Field            | Type    | Description                             |
| :--------------- | :------ | :-------------------------------------- |
| `planName`       | String  | Snapshot of plan name.                  |
| `dayLabel`       | String  | Snapshot of day label.                  |
| `weekday`        | Int     | Day of week.                            |
| `date`           | ISO8601 | Session date.                           |
| `startedAt`      | ISO8601 | When the session started.               |
| `endedAt`        | ISO8601 | (Optional) When the session ended.      |
| `statusRaw`      | String  | Session status.                         |
| `sessionTypeRaw` | String  | `"steadyState"`, `"hiit"`, etc.         |
| `hkWorkoutID`    | String  | (Optional) HealthKit workout reference. |
| `planDayID`      | UUID    | (Optional) References a WorkoutPlanDay. |

---

## 18. Cardio Session Logs (v2.0)

Per-exercise log entries within a cardio session.

| Field                | Type   | Description                        |
| :------------------- | :----- | :--------------------------------- |
| `distance`           | Double | (Optional) Distance covered.       |
| `durationSeconds`    | Int    | Duration in seconds.               |
| `avgPace`            | Double | (Optional) Average pace.           |
| `avgSpeed`           | Double | (Optional) Average speed.          |
| `calories`           | Double | (Optional) Calories burned.        |
| `elevationGain`      | Double | (Optional) Elevation gain.         |
| `avgHeartRate`       | Int    | (Optional) Average heart rate.     |
| `maxHeartRate`       | Int    | (Optional) Maximum heart rate.     |
| `heartRateZonesData` | Data   | (Optional) Encoded HR zone data.   |
| `exerciseID`         | UUID   | (Optional) References an Exercise. |
| `sessionID`          | UUID   | References a CardioSession.        |

