---
name: connect-botmaker
description: Set up Botmaker integration in the current project -- BM-CLI for developing Client Actions locally, and/or a Python client for Botmaker's REST API v2.0 (read bot data: templates, channels, messages, sessions). Use whenever the user wants to connect to Botmaker, develop Client Actions locally, or query the Botmaker API from Claude Code.
---

# Connect to Botmaker (BM-CLI + REST API v2.0)

Botmaker integration has two independent parts -- set up only the one(s)
the user actually needs.

## Which part does the user need?

Ask if unclear:
- **BM-CLI** -- writing/iterating on Client Actions (custom bot logic)
  locally in an IDE instead of in-platform.
- **REST API** -- reading bot data (WhatsApp templates, channels, messages,
  sessions) from a script.

They're unrelated capabilities that happen to share a vendor; a user asking
for one usually doesn't need the other.

## Part A -- BM-CLI (Client Actions local dev)

1. Confirm Node.js is installed (`node --version`); install it first if
   missing.
2. `npm i -g @botmaker.org/botmaker-cli`
3. Run `bmc` in the console and follow its own interactive setup/login --
   this is Botmaker's login flow, nothing this skill stores or manages.
4. `bmc -help` to see available commands.

Windows-specific gotchas (from Botmaker's own docs):
- Native module build errors: `npm install --global windows-build-tools`
  (admin PowerShell) and set the `PYTHON` environment variable to a
  Python 2.7 install.
- Script execution blocked: run PowerShell as admin,
  `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`.

## Part B -- REST API v2.0

### Step 1 -- gather info

Ask the user (skip whichever they've already stated):
1. **Workspace name** -- used to namespace the credentials file locally
   (e.g. "pickit" or a client name).
2. Whether they already have API credentials generated, or need to
   generate them.

### Step 2 -- generate credentials (if needed)

In the Botmaker dashboard: **Configuration > Integrations > API >
Credentials tab**. Three values are shown: access token, secret ID,
refresh token.

### Step 3 -- scaffold the client

Copy `botmaker_client.py.template` (in this skill's folder) into the
target project as `botmaker_client.py`, then fill in:

- `CREDENTIALS_PATH` -- see the note in the template; must be **outside
  any cloud-synced folder**, e.g.
  `Path.home() / ".botmaker" / "<workspace>_credentials.json"`.

Do not modify `call()`'s retry/backoff or the `access-token` header logic
-- these mirror a real, already-working Botmaker integration (see "Where
this came from" below), not a guess.

### Step 4 -- save credentials and verify

```
python botmaker_client.py --setup
```

Paste the three dashboard values when prompted (secret ID / refresh token
can be left blank if the user only has the access token). Then:

```
python botmaker_client.py
```

Confirm it prints `OK -- N active WhatsApp channel(s) found.` before
considering setup done.

### Step 5 -- standing conventions going forward

- **No automatic token refresh.** If a call raises `BotmakerAuthError`
  (HTTP 401/403), the token is dead -- regenerate it at Configuration >
  Integrations > API and re-run Step 4's `--setup`. Don't try to build a
  refresh flow; nothing confirms one exists.
- **Read-only by default.** Only the four GET wrappers
  (`get_whatsapp_templates`, `get_channels`, `get_messages`,
  `get_sessions`) are provided. Don't add a send-message/POST call
  without the user explicitly asking for it -- it reaches real end users.
  If they do ask, check the swagger at `go.botmaker.com/apidocs/`
  (requires a Botmaker login) for the exact payload shape rather than
  guessing one, and confirm with the user before ever actually calling it.
- **Unknown endpoint?** Use the generic
  `call(method, path, params=..., json_body=...)` helper, but verify the
  payload shape against the swagger first -- don't invent a request body.

## Querying gotchas (verified against the real API, 2026-09-17)

- **`/sessions` filters don't work.** `from`/`to`, `contact-id`,
  `contact-name`, `chat-id`, `session-id` are all silently ignored --
  `get_sessions()` always returns the same fixed set of the most recent
  sessions (~1000-1100 total) no matter what params you pass. To find a
  specific contact/date, paginate all of it and filter client-side, or
  switch to `/messages` instead (see below).
- **`/messages` filters DO work, but need the right params.** Requires
  `contact-id` (international format, e.g. `"5491134230676"` -- no `+`,
  no leading `0`) and `channel-id` (from `get_channels()`). Date range is
  `from`/`to` (NOT `from-date`/`to-date`), max 1 month per call. To go
  back further than ~90 days, add `long-term-search=true` -- the 1-month
  cap still applies per call, so a wide historical search means looping
  month-by-month across the range and across every channel-id.
- Practical recipe for "find this contact's conversation(s)": get all
  `channel-id`s via `get_channels()`, then call `get_messages()` per
  channel with `contact-id` + a `from`/`to` window, moving the window
  back a month at a time (adding `long-term-search=true` once you're past
  ~90 days) until you hit results or give up.

## Where this came from

The base URL, `access-token` header, retry/backoff policy (exponential,
only on 429/5xx, never on 401/403), pagination via `nextPage`, and the
four wrapped endpoints all come from a real, already-working Botmaker
integration (a WhatsApp template-message delivery-status reporting
project), not from guessing at Botmaker's swagger. If you need an
endpoint not covered here, treat the swagger as the source of truth and
this pattern as the auth/retry scaffold to reuse around it.
