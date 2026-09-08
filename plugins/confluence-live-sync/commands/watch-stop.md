---
description: Remove the background scheduled task started by /watch-start for this folder
---

# Stop background watch for this folder

1. Recompute the same task name `/watch-start` would use: current working directory's absolute path,
   sanitized (non-alphanumeric/dash/underscore characters stripped/replaced), prefixed
   `ConfluenceLiveSync_`. Call this `$TaskName`.
2. Run (via the PowerShell tool, from this plugin's `scripts/` directory):
   ```
   ./unregister-task.ps1 -TaskName "$TaskName"
   ```
3. Report the result: task removed, or "no task was registered for this folder" (the script handles
   the not-found case itself and exits cleanly either way).
