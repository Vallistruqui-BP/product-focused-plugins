---
name: appscript-clasp
description: Develop Google Apps Script projects locally using clasp -- create or clone a project, write .gs/.js and appsscript.json, push/pull changes, run functions, tail logs, and manage deployments (including web apps). Use when the user wants to build, automate, or edit an Apps Script project, or mentions "clasp", "Apps Script", or a Sheets/Docs/Forms script/add-on.
when_to_use: Triggered when the user asks to create, clone, edit, push, deploy, or debug a Google Apps Script project, or wants a Sheets/Docs/Forms add-on, custom menu, trigger, or Apps Script web app.
allowed-tools: Read Write Edit Bash Glob Grep AskUserQuestion
---

# Apps Script via clasp

Runs Google Apps Script development locally: Claude edits real `.gs`/`.js` files and
`appsscript.json` in a normal project folder, and `clasp` (Google's official CLI) handles
create/clone/push/pull/run/deploy against the actual Apps Script project. Reference files hold the
deep detail — read them on demand.

- [`references/setup.md`](references/setup.md) — checking/installing `clasp`, logging in, and what
  never to do with credentials. **Read this before the first clasp command in a session, or
  whenever a command fails with an auth error.**
- [`references/manifest-syntax.md`](references/manifest-syntax.md) — `appsscript.json` fields:
  timezone, runtime version, OAuth scopes, advanced services, dependencies. **Read before adding a
  scope or enabling an advanced service.**
- [`references/deployment-and-webapps.md`](references/deployment-and-webapps.md) — versions vs.
  deployments, `doGet`/`doPost`, executable APIs, access-level choices. **Read before any `clasp
  deploy` or web app work.**
- [`references/container-bound.md`](references/container-bound.md) — binding to a new vs. existing
  Sheet/Doc/Form, custom menus, simple/installable triggers. **Read before container-bound project
  work.**

## Workflow

1. **Confirm clasp is ready.** Run `clasp --version`. If missing or not logged in, follow
   `setup.md` before doing anything else — don't attempt any project command against an
   unauthenticated clasp.

2. **Establish the project.** Ask (if not already clear from context) whether this is:
   - a **new** project — standalone, or bound to a new Sheet/Doc/Form/Slides via
     `clasp create --type <type> --title "<title>"`;
   - an **existing** project — `clasp clone <scriptId>` (get the scriptId from the user, or from
     Extensions → Apps Script → Project Settings on the target file — see `container-bound.md` for
     binding to an *existing* container, which `clasp create` cannot do).

   Do this once per project, not on every request in an ongoing session.

3. **Write code** as normal file edits in the cloned/created local folder — `.gs` or `.js` source
   files plus `appsscript.json`. Follow the user's existing code style if editing an established
   project; for new code, keep functions small and named for what they do (Apps Script has no
   compiler to catch dead code, so unused functions accumulate silently — don't leave any).

4. **Push after edits**: `clasp push`. **Before any `clasp pull`**, check for uncommitted local
   changes and warn the user — pull overwrites local files with the server copy, so a pull right
   after unsaved edits loses them.

5. **Run and debug** on request: `clasp run <functionName>` to execute a function directly,
   `clasp logs` (or `clasp logs --watch` to tail) to see `Logger.log`/`console.log` output and
   errors. Don't run functions with side effects (sending email, modifying Sheets/Docs data)
   without the user's go-ahead — treat `clasp run` like executing code against production data,
   because for a real Apps Script project it usually is.

6. **Deploy only when asked**, not automatically after every push — a deployment is a released
   version, not a save point. Follow `deployment-and-webapps.md` for the version/deploy flow and,
   for web apps, the access-level decision (who can access) — that's a real security choice the
   user must make explicitly, never default it silently.

7. **Iterate.** On follow-up requests, edit the existing local files and `clasp push` again rather
   than recreating the project. If the user mentions editing in the web-based Apps Script editor,
   don't assume your local copy is still current — offer to `clasp pull` (after the uncommitted-
   changes check in step 4) rather than blindly overwriting their remote edits with a stale push.

## Scope boundaries

- This is a clasp/local-dev workflow wrapper around Apps Script projects, not a general Google
  Workspace API client — Claude doesn't call Sheets/Docs/Drive/Gmail APIs directly outside of what
  the Apps Script code itself does when run or deployed.
- Never ask the user to paste an OAuth client secret, access token, or the contents of
  `~/.clasprc.json` into chat. `clasp login` handles auth entirely through the browser — see
  `setup.md`.
