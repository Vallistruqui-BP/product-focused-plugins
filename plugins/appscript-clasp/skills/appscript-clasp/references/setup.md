# Setup: installing and authenticating clasp

## Check what's already there

```
node --version      # clasp requires Node.js (LTS is fine)
clasp --version      # the CLI itself
```

If `clasp --version` fails with "command not found", it isn't installed. If it succeeds but a
later command fails with an auth/401-style error, it's installed but not logged in (or the login
expired) — skip to **Log in** below.

## Install

```
npm install -g @google/clasp
```

This requires npm (ships with Node.js). If the user doesn't have Node.js at all, point them to
https://nodejs.org — don't attempt to install Node itself via this skill.

## Enable the Apps Script API (one-time, per Google account)

clasp needs the Apps Script API enabled for the account it will log in as. Tell the user to visit
https://script.google.com/home/usersettings and turn on "Google Apps Script API". This is a
manual toggle on a page they need to be logged into with the right account — Claude cannot do this
for them.

## Log in

```
clasp login
```

This opens a browser window for Google's normal OAuth consent screen. The user signs in and
approves the requested scopes themselves; clasp then stores a token locally
(`~/.clasprc.json` — or `.clasprc.json` in the project folder if `clasp login --creds` was used
with a custom OAuth client). This step is interactive and happens in the user's browser — Claude
only runs the command and waits for it to complete.

**Never** ask the user to paste the contents of `~/.clasprc.json`, an access token, refresh token,
or OAuth client secret into chat, and never read that file's contents yourself. If a command needs
re-authentication, just re-run `clasp login`.

To confirm login worked: `clasp login --status` (newer clasp versions) or simply run `clasp list`
— if it returns a project list (even empty) instead of an auth error, login succeeded.

## Common setup failures

- **"Apps Script API has not been used"** — the per-account API toggle above wasn't enabled, or
  was enabled after the token was issued; re-run `clasp login` after enabling it.
- **Wrong Google account** — `clasp login` uses whichever account the browser session picks; if
  the user has multiple accounts, tell them to check which one the consent screen showed, or run
  `clasp logout` first to force the account chooser.
- **Corporate/Workspace account restrictions** — some Workspace admins block third-party API
  access org-wide; if login consistently fails at the consent screen with an admin-blocked
  message, that's an admin policy issue outside clasp's or Claude's control — tell the user to
  check with their Workspace admin.
