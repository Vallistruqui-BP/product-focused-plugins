---
description: Register a background Windows scheduled task that keeps this folder synced with its Confluence page
---

# Start background watch for this folder

## 1. Preconditions

Verify `.claude/confluence-sync-config.json` exists in the current working directory. If not, stop
and tell the user to run `/setup-sync` first — don't try to guess settings.

## 2. Warn and confirm before registering anything

This is the consequential step — say this plainly to the user and get explicit confirmation before
running the script in step 4:

> This will register a Windows Scheduled Task that runs, on its own, every `<pollIntervalMinutes>`
> minutes, indefinitely, until you run `/watch-stop`:
> `claude -p "/sync-doc" --dangerously-skip-permissions`
> in this folder. **`--dangerously-skip-permissions` means every scheduled run executes with all
> tool-permission checks bypassed** — reading/writing files in this folder and calling the Atlassian
> (Jira/Confluence) tools, with no human approving anything, every cycle.
>
> This includes `Confluence Sync.md`, which is a **live, editable mirror** — any local edit you make
> to that file gets pushed back to the Confluence page on the next scheduled run, unattended. If both
> the file and the page changed since the last sync, it attempts an automatic three-way merge
> (via `git merge-file`) and pushes the merged result straight to the page with no review, as long as
> the merge is clean; only a genuine overlapping conflict pauses it. Only proceed if you trust this
> automation to read, write, and merge unattended against this folder and this Confluence page.

Do not proceed to step 3/4 without an explicit go-ahead in this conversation.

## 3. Resolve parameters

1. Current working directory's absolute path → `$ProjectPath`.
2. Task name: sanitize `$ProjectPath` into a safe scheduled-task name (strip characters other than
   alphanumerics/dash/underscore, e.g. replace `:\` and `\` with `_`) and prefix it
   `ConfluenceLiveSync_` so it's identifiable and collision-free even if two folders share a base
   name. Call this `$TaskName`.
3. `pollIntervalMinutes` from the config file (default `15` if absent).

## 4. Register the task

Run (via the PowerShell tool, from this plugin's `scripts/` directory):

```
./register-task.ps1 -ProjectPath "$ProjectPath" -TaskName "$TaskName" -IntervalMinutes <pollIntervalMinutes>
```

Let it resolve the `claude` executable itself (no `-ClaudeExePath` needed unless it fails to find
one on PATH, in which case ask the user for the full path and retry).

## 5. Report

On success: report the task name, the interval, and how to check on it later
(`Get-ScheduledTask -TaskName "<TaskName>"`, `Get-ScheduledTaskInfo -TaskName "<TaskName>"` for last
run time/result) or stop it (`/watch-stop`).

On failure (e.g. `claude` not resolvable, insufficient privileges to register a task): report the
exact error and do not claim the watch is active.
