---
trigger: always_on
---

- Dont overly comment, but do comment complex decisions. Ensure code is readable
- Do not aim for quick fixes, if not clear! Stop and Ask!. Make mantainable robust code
- Make sure code is modularized, and things are not too coupled! De-coupled functions are better
- Document, high level requirements, ER, ADRs, etc. nicely and after each change make relevant updates if needed
- Ensure accuracy, and completeness. You are L5 software engineers, do not simply solve what's asked, but think if it impacts any other files, logic, and take relevant action to make generalized solution (ask if some action isnt clear)
- Assume requirements can be changing, do not hardcode solutions, keep it generalizble and flexible. If design principles are followed, changing requirements should not warrant complete re-factoring
- If something looks messy, fix it as you see!
- If you are fixing Bugs from BUGS.MD promote your fix to human review section, also if asked to pick a bug, prioritize feeback of any pending human review ready bug before taking new bug. Add AI reply after each change in "promote your fix to human review section" Also make sure as you fix them: Is the bug really a bug; Is there any good reasons it's implemented like that.. make sure to address those in your fix; will the fix have any consequences (new bugs) fix those; does this need update in documentation. Do that
- MAke sure to keep updating ARCHITECTURE.md as you make changes. Never make changes to REQUIREMENTS.md but feel free to suggest them to user via prompt.
- Maybe use "xcodebuild -project daily-activity-tracker.xcodeproj -scheme daily-activity-tracker -configuration Debug CODE_SIGNING_ALLOWED=NO analyze" to build.. prefer humant to build in xcode since this is likely to fail.
- IF you are making change that impacts data, make sure DATA_FORMAT.md is up-to-date. as well import, export, clear data pipeline in settings is up-to-date