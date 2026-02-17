# Data Format Documentation

The Daily Activity Tracker uses a JSON-based format for importing and exporting data. This document describes the structure of the JSON file so users can manually construct or modify data for import.

## Schema Overview

The root of the JSON file is an object containing arrays for `categories`, `activities`, `logs`, `vacationDays`, `configSnapshots`, `goals`, `goalActivities`, and `goalMeasurements`.

```json
{
  "version": "1.0",
  "timestamp": "2026-02-15T12:00:00Z",
  "categories": [ ... ],
  "activities": [ ... ],
  "logs": [ ... ],
  "vacationDays": [ ... ],
  "configSnapshots": [ ... ],
  "goals": [ ... ],
  "goalActivities": [ ... ],
  "goalMeasurements": [ ... ]
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
  "pausedParentId": "UUID-OF-FORMER-CONTAINER"
}
```

### Key Fields

- **`typeRaw`**: One of `"checkbox"`, `"value"`, `"cumulative"`, `"container"`, `"metric"`.
- **`metricKindRaw`**: Only for `metric` type — one of `"photo"`, `"value"`, `"checkbox"`, `"notes"`.
- **`aggregationModeRaw`**: Only for `cumulative` type — `"sum"` (default) or `"average"`. Controls how multiple daily entries are aggregated.
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
  "skipReason": null,
  "timeSlotRaw": "morning"
}
```

| Field         | Type    | Description                                                       |
| :------------ | :------ | :---------------------------------------------------------------- |
| `activityID`  | UUID    | ID of the parent activity.                                        |
| `date`        | ISO8601 | The "Day" of the log (usually 00:00:00 time).                     |
| `statusRaw`   | String  | `"completed"` or `"skipped"`.                                     |
| `value`       | Double  | (Optional) Numeric value for value/cumulative types.              |
| `completedAt` | ISO8601 | (Optional) Exact timestamp of completion.                         |
| `timeSlotRaw` | String  | (Optional) Session slot: `"morning"`, `"afternoon"`, `"evening"`. |

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

| Field        | Type    | Description                        |
| :----------- | :------ | :--------------------------------- |
| `title`      | String  | Goal name.                         |
| `icon`       | String  | SF Symbol name.                    |
| `hexColor`   | String  | Hex color code.                    |
| `deadline`   | ISO8601 | (Optional) Target completion date. |
| `isArchived` | Bool    | Whether goal is archived.          |
| `sortOrder`  | Int     | Display order.                     |

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
