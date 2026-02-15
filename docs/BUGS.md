# Backlog
- [9] Maybe have activites section where I can edit and update activites.. For containers, if i edit, update all children. If there is already data associated with that activity ask if user wants to delete all that data or wants to rename old activity as [Deprecated on Date] Activity, and create new activity.
- [10] Vacation analytics: daily charts should display "Vacation" label, weekly aggregation should exclude vacation days (if whole week is vacation mark as such), similarly for monthly. (Remaining portion of original bug [6] — analytics/charting vacation display still needs work)
- [11] containers should have skip section too



# Promoted for human review 
- [2] Edit/Undo past actions: Completed section now renders fully interactive rows — checkboxes can be un-checked (toggles completion), value/cumulative items have edit/clear in context menu with undo. `ActivityRowView` context menu "Undo Completion" works. `ValueInputRow` has `onRemove` with undo toast. Cumulative activities show "View Entries" in context menu at all times — opens `CumulativeLogSheet` with swipe-to-delete individual logs and single Save confirmation.
  - Human Feedback: I cant add cumulative one unless it's completed.. I want to in-general be allowed to update cumulative ones same way even when they are not completed
  - AI Reply: Fixed — removed `currentValue != nil` guard so "View Entries" is always available in context menu for cumulative activities, regardless of completion status.
  - Human feedback: I still don't know how to edit it in UI like remove old inputs for non completed cumulative actions.
- [8] Photo adding for activities: Added "View Details" to activity context menu (long-press any activity row). Navigates to `ActivityDetailView` which has camera button for photo-enabled activities, photo timeline, and recent history. Test: Long-press any activity → "View Details" → verify camera button appears for photo-enabled activities.
  - AI Reply: The photo flow already existed in `ActivityDetailView` (camera, photo timeline, `MediaService`) but was unreachable — never linked from the dashboard. Added `NavigationLink(value:)` in context menu + `navigationDestination(for: Activity.self)` to make it accessible.
  - Human feedback: There is no view detail option when I long press on any activity still. Also that sounds like a bad menthodology.. ask for cadence of photo capture for photo enabled activities during activity creation. And request user to ask for photo at that cadence, (everytime, weekly, monthly, etc. and if user hasnt provided photo within that period ask user when completing the action.). Make IT easy to add photo and part of acceptance flow naturally but only when it's behind shedule


Human Approved Bugs:
- [7] Undo toast position: Moved from bottom to top of screen so it doesn't overlap with FAB or other bottom UI. Animation updated to slide down from top. Test: Complete/uncomplete any activity → verify undo toast appears at the top.
  - AI Reply: Fixed — `UndoToastModifier` changed from `ZStack(alignment: .bottom)` to `.top` with matching slide-down animation offset.

