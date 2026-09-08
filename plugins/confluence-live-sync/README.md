# confluence-live-sync

Keeps a Confluence page in sync with a local project folder — bidirectionally, and optionally in the
background — where the folder is linked to a Jira issue whose summary matches the folder's name, and
that issue points at the Confluence page via a custom field. Generic and config-driven: unlike
Pickit's internal `pickit-sync-kickoff` plugin, nothing here is hardcoded to a specific Jira project,
template, or custom field ID.

## How it finds your page

There's no shared mapping file. `/setup-sync` asks you for your site, Jira project, issue type, the
custom field that holds the linked Confluence page, and writes it all to
`.claude/confluence-sync-config.json` in the current folder — validating it against a real Jira/
Confluence lookup before saving. From then on, `/sync-doc` takes the **name of the folder Claude Code
is running in** and looks for exactly one Jira issue (matching your configured project/type/filters)
whose **summary is exactly that folder name**. Zero or multiple matches stop the run with an
explanation rather than guessing.

## Setup

1. `/setup-sync` — one-time, per folder. Answer its questions about your Atlassian site, Jira
   project/issue type, the linked-page custom field, and (optionally) frozen statuses and file
   patterns.
2. `/sync-doc` — run it manually any time to sync right now.
3. `/watch-start` — optional. Registers a Windows Scheduled Task that runs `/sync-doc` automatically
   on an interval, unattended. Read the warning below before using this.

## Prerequisites

- Claude Code with the **Atlassian MCP connector** configured and authenticated for your site.
- The **Google Drive MCP connector**, only if your notes are Google Docs (`.gdoc` shortcut files)
  rather than local `.md` files.
- Windows, for `/watch-start`/`/watch-stop` (`Register-ScheduledTask`/`Unregister-ScheduledTask`).
- **Git, on PATH**, for automatic conflict merging (`git merge-file`) when both `Confluence Sync.md`
  and the page changed since the last sync. Without it, that specific situation falls back to writing
  the page's current content to `Confluence Sync (remote).md` alongside your edited file, for you to
  reconcile by hand, instead of merging automatically.
- `$env:CONFLUENCE_API_TOKEN` and **Node.js/npm on PATH**, only if your folder has `.mmd`
  flowcharts — used to render them to PNG (`@mermaid-js/mermaid-cli`) and attach them via the
  Confluence REST API. See "Known limitations" below for the fallback when either is missing.

## What a sync does

**`Confluence Sync.md` is a live, editable mirror — genuinely bidirectional, not read-only.** Every
`/sync-doc` run compares three things: the page's current content, the file's current content, and
the content both matched as of the last successful sync (the "baseline," kept in
`.claude/confluence-mirror-baseline.md`). That gives four outcomes:

- Neither side changed → nothing happens.
- Only the page changed → pulled down, overwriting `Confluence Sync.md`.
- Only the file changed → pushed up to Confluence.
- **Both changed** → an automatic three-way merge via `git merge-file`. If the two changes don't
  overlap, the merge is pushed to Confluence with no human involved. If they genuinely overlap (the
  same passage edited differently on both sides), nothing gets pushed anywhere — instead, standard
  `<<<<<<< / ||||||| / ======= / >>>>>>>` conflict markers are written into `Confluence Sync.md`
  itself, the same convention a `git merge` conflict uses (the `|||||||` section shows the pre-edit
  baseline text for context). Edit the file to resolve it (remove the markers, keep
  what you want); the next sync detects the resolution and pushes it. Until then, every sync leaves
  that file alone and just reports the conflict is still open.

**Separately, new `.md`/`.gdoc`/`.mmd` files** (anything other than `Confluence Sync.md` itself)
get merged into the page as one-way "notes push": if a file's own top heading matches an existing
page heading, its content is integrated into that section (rewritten as a single coherent statement,
not just appended); otherwise it's appended as a dated entry under a `## Sync updates` section. This
plugin doesn't assume any specific page template, so the changelog append is the safe fallback when
there's nowhere obvious to integrate. This direction is unaffected by whatever's happening with the
mirror file above — a pending mirror conflict doesn't block new notes from being merged in.

## ⚠️ `/watch-start` runs Claude unattended, with permission checks off — and can auto-merge live

The scheduled task it registers runs `claude -p "/sync-doc" --dangerously-skip-permissions` on a
timer, indefinitely, until you run `/watch-stop`. That flag means **every scheduled run executes with
all tool-permission prompts bypassed** — no human approves the Confluence writes, Jira reads, or
local file changes each cycle. That now includes pushing your local edits to `Confluence Sync.md`
back to the page, and — when both sides changed — pushing an **automatically merged** result with no
review, as long as the merge is clean (only a genuine overlapping conflict pauses it). Only use this
against a folder and Confluence page you're comfortable handing that level of unattended trust to.
Check on it any time with `Get-ScheduledTask -TaskName "ConfluenceLiveSync_<...>"` /
`Get-ScheduledTaskInfo`, and remove it with `/watch-stop` whenever you want it to stop.

## Known limitations

- **Classic Confluence pages only — no Live Docs.** Same restriction `pickit-sync-kickoff` already
  lives with, adopted deliberately rather than tested: a Live Doc write may land in a
  checkpoint/version-history layer that never reaches the actual rendered page, and that risk isn't
  worth taking for something that can run unattended. `/setup-sync` and `/sync-doc` both detect a Live
  Doc and stop with instructions to convert it first (Confluence's own `•••` → `Convertir a página`).
- **Exact-match only**, same as `pickit-sync-kickoff` — if the folder name and the Jira summary drift
  apart, the next sync stops with "no match" instead of guessing.
- **The mirror is Markdown, and pushing Markdown back to Confluence is lossy by design** — this was a
  deliberate tradeoff (Markdown is easy to hand-edit; the alternative was an HTML mirror). Confluence
  panels, status badges, layout columns, macros, and mentions have no Markdown representation, so if
  the page uses any of those, editing and pushing `Confluence Sync.md` will strip them the first time
  it's pushed. Fine for prose/table-heavy pages, not for heavily macro'd ones.
- **No compare-and-swap on push** — there's a small window between fetching the page for comparison
  and writing back where someone else's edit could land in between; the tool surface available here
  doesn't expose a "only write if version is still N" option, so this is an accepted, unmitigated race
  window, not something the merge logic can close.
- **`.mmd` flowcharts need `$env:CONFLUENCE_API_TOKEN` (an Atlassian API token) and Node/npm on
  PATH** to be rendered to PNG (`mmdc`) and attached via the Confluence REST API — without either,
  the sync falls back to extracting and describing the diagram's labels as text instead of showing
  the picture. Raw Mermaid code is never pasted onto the page directly, since most Confluence sites
  have no Mermaid-rendering app installed and it would only show as unrendered text.
- **Notes-push merge is changelog-style** for any content that doesn't heading-match an existing
  section — expect a growing "Sync updates" section unless your page's headings already line up with
  your local files' own headings.
- **Windows-only** for the watch feature — no macOS/Linux background scheduling in this version.
