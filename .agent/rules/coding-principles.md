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
- Make sure everything is version controlled locally, but .gitignore anything that's not relevant etc.
- If you are fixing Bugs from BUGS.MD promote your fix to human review section, also if asked to pick a bug, prioritize feeback of any pending human review ready bug before taking new bug.