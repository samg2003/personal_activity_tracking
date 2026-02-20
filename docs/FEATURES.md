# List of features: (do not look into this!)
- App logo in initial app loading time
- more so a bug, but in activity analytics view the chart with daily weekly monthly is not generalized for all activities, and also doesnt aggregate anything. 
- notification system revamp. Sleep time (no notifications then), morning afternoon and evening set automatically. 30 mins before sleep notification. Morning notification. etc.
- Crazy alarm system
- Have sticky notes + history of notes along with each activity (embdedded links, resources, things to note etc.) + journalling for each day.. to look back in time and see. 
- Ability to edit exercises, and add notes at individual workout level, exercise level, etc. 
- Currently everything gets deleted when i delete curr data. Ensure deleting importing, exporting, ensures default categories, exercises, muscle groups, etc. is not impacted. 
- Goal needs to have metric for it to be active. If it's checkbox activity as metric it should show (expected consistency (user set, defaul is 80%), and actual consistency since goal started or last 365 days whichever is sooner)
- Biggest win logic is fucked -50k steps is shown as biggest win, i guess it doesnt know if things need to go up or down, maybe do only if it's guranteed, it should also show bunch of biggest wins, not just 1. Maybe for unknowns it can add as biggest changes?, but think of this logic extensively. IF we need go up or go down or stay close to goal, is better for value or metric, cumulative, etc. use the predictor from keywords as we used everywhere for this, but allow user to set it in advanced. These needs to be added in main dashboard too along with progress ring.
- do not leg user log weights in exercises if it's 0. Improve weights entry. Make strength training, exercises have time based embedded in it. Exclude separate timed exercises.. for those re-think UI everywhere.. all touch points. It impacts, analytics, look deeply what analytics it impacts, it also impacts UI. Look for entry method for this. For analytics of volume and stuff ... Weight * Set * Time / Avg rep time (maybe?). Also include exercises with body weight only, for those set weight automatically (add body weight factor for these exercises), and multiply body weight asked in settings with this (add body weight in settings and default to 150lbs)
- Actually read apple health for all activities link to health, for checkbox just look for completion, for value look for first value of linked thing for today, for cumulative look for some smart way to do it but in view entries you should see apple health vs manually entered values clearly, and for metric follow same thing for value and checkbox. 

- Value Input Requires Alert Dialog (Not Inline) For value-type activities and the FAB cumulative quick-add, the app uses Alert with a TextField. Alerts are modal, tiny, and iOS doesn't always surface the keyboard reliably. Every value entry = 1 tap to open alert + type + tap "Add". Fix: Use a bottom sheet or inline expandable input that appears with the keyboard pre-focused. Look at how Apple Health's "Add Data" works — an inline number pad that's always ready. A .sheet with a large number pad would be much faster.




ritical: No Progressive Overload Tracking
This is the single most important thing missing. The WorkoutSetLog stores reps and weight, and there's an autoFillSuggestion that pre-fills from history — but there's no visibility into progression. When you're in a session, you see your current sets but you have zero context about what you did last time for this exact exercise.

In every serious gym app (Strong, Hevy, JEFIT), the #1 most used feature is: "Last time you did 3×10 @ 60kg". Without this, the user is flying blind.

Impact: You can't intelligently decide reps/weight. The entire point of logging strength training is tracking progression over time.

🔴 Critical: Weight Input via +/- Steppers Is Painfully Slow
The newSetInput function uses +2.5 / -2.5 stepper buttons (lines 273-293). To go from 0 to 80kg, you'd need to tap the plus button 32 times. This is the most common interaction in a workout session — you do it for every exercise, potentially 15-20+ times per session.

Every other gym app uses either:

Direct number entry (tap the weight, keyboard appears)
A scrollable number wheel
Or at minimum, variable step sizes (hold to accelerate)
Impact: This alone could make the app unusable for serious lifters. It's the single biggest UX friction point.

🟡 Serious: No Rest Timer Between Sets
After logging a set, there's no rest timer countdown. Rest periods are critical for strength training — most people rest 2-3 min between heavy compounds, 60-90s for accessories. The session has a global elapsed timer but no per-set rest timer.

Impact: Users will need a separate timer app, which defeats the purpose of an integrated workout tracker.

🟡 Serious: Exercise Order Is Fixed to Plan — No Reordering During Session
StrengthSessionView.exerciseList (line 128) iterates planDay.sortedStrengthExercises — the order is locked to the plan's sortOrder. In reality, equipment availability changes constantly in a gym. If the bench is taken, you want to move to the next exercise and come back later. There's no way to reorder, skip, or mark an exercise "come back later" during a live session.

Impact: Makes the app feel rigid. Users will abandon the session flow and log freestyle if they can't adapt.

🟡 Serious: No Superset Execution Support
StrengthPlanExercise has a supersetGroup field (line 11 in the model), but StrengthSessionView doesn't use it at all — exercises render as individual cards in order. There's no visual grouping of supersetted exercises, no alternating set logging flow, and no way to log A1→B1→A2→B2 efficiently.

Impact: Supersets are extremely common. The model supports it but the UI doesn't — dead code essentially.

🟡 Plan Creation: 7-Day Week is Too Rigid
WorkoutPlan creates 7 WorkoutPlanDay objects, one per weekday. But many programs follow a rotation (Push/Pull/Legs repeating) that doesn't align to calendar days — Day 1 might be Monday this week but Tuesday next week. The current model forces you to assign specific weekdays, which doesn't match how most intermediate/advanced lifters program.

Impact: Forces users into a weekly schedule when many programs are rotational.

🟢 Minor but Notable Issues
No exercise notes during session — You can add notes to an Exercise and to a StrengthSession, but there's no per-set note (e.g., "felt a twinge in left shoulder"). WorkoutSetLog has no notes field.
No way to add unplanned exercises mid-session — The exercise list comes from session.planDay.sortedStrengthExercises. If you want to add a bonus exercise not in the plan, you can't.
ExerciseCreatorView requires equipment — Save is disabled when equipment.isEmpty (line 166). But bodyweight exercises (pull-ups, push-ups, dips) don't have equipment. The user would need to type "Bodyweight" which feels awkward.
No warmup set progression — Warmup button exists but there's no suggested warmup ramp (e.g., bar → 60% → 80% → working weight). Just a single "W" button.
Weight is always in kg — Hardcoded "kg" in setRow (line 201). No unit preference setting for lbs users.
