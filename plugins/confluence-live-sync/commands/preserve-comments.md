---
description: Safeguard Confluence inline comments around a manual full-body republish (snapshot before, reconcile after)
---

# Preserve inline comments across a republish

A `contentFormat: "markdown"` full-body page replace strips Confluence's inline-comment anchor marks
from the **entire** page body — not just the paragraphs being edited, since markdown has no way to
represent an anchor mark at all. The comment **object** is untouched (same ID, `resolutionStatus`
keeps reporting `"open"`, never flips to `"dangling"`) — only the highlight/anchor in the live
content is silently gone. Confirmed on a real page (3233677317, 2026-09-14): 10 inline comments
across two markdown-push rounds went invisible with no error and no status change, unnoticed until a
human asked about them directly — which is exactly why `resolutionStatus`/comment-ID presence can't
be trusted as the detection signal (see the `KNOWN GOTCHA` note in `preserve-orphaned-comments.ps1`).
`contentFormat: "html"` pushes are round-trip safe and don't have this problem.

**As of v0.11.0, `/sync-doc` runs this automatically** around its own markdown push (snapshot before,
reconcile after) — you don't need to invoke this command by hand during a normal sync. It remains
available here as a manual command for two cases: (1) any *other* markdown-format push to this page
outside `/sync-doc` (a one-off manual edit, a different tool), or (2) re-running reconcile on demand
if you suspect comments were orphaned by something that happened outside this plugin's own flow.

## Usage

This command takes one argument: `snapshot` or `reconcile`.

### `/preserve-comments snapshot`

Run this **before** you start editing/publishing the page.

1. Read `.claude/confluence-sync-state.json` in the current working directory for `pageId`. If
   missing, stop and report: "no page linked — run `/setup-sync` first."
2. Run:
   ```powershell
   pwsh -File "<plugin dir>/scripts/preserve-orphaned-comments.ps1" -Mode Snapshot -PageId <pageId>
   ```
   (resolve `<plugin dir>` to this plugin's own installed path, not a hardcoded path)
3. Report how many inline comments were snapshotted and where the snapshot file was saved
   (`.claude/scripts/inline-comments-snapshot.json` relative to the script, by default — confirm the
   actual printed path from the script's own output).

### `/preserve-comments reconcile`

Run this **after** the publish completes.

1. Same `pageId` lookup as above.
2. Run:
   ```powershell
   pwsh -File "<plugin dir>/scripts/preserve-orphaned-comments.ps1" -Mode Reconcile -PageId <pageId>
   ```
3. The script diffs the current inline comments against the snapshot; for every comment that no
   longer resolves (orphaned by the republish), it posts a footer comment on the page preserving the
   original anchored paragraph text, the original comment body, and a note explaining why it was
   moved. Report how many were reconciled (or that none were orphaned).

If no snapshot file exists when `reconcile` is called, stop and report that `snapshot` must be run
first — do not attempt to reconcile against nothing.

## Notes

- Requires `CONFLUENCE_API_TOKEN` to be set (same resilient lookup as `/sync-doc` — check
  process/User/Machine env, in that order; never fail silently on a `setx`-not-yet-propagated token).
- Orphan detection diffs the snapshot's anchored text against the page's *current* content — not
  comment IDs, not `resolutionStatus` — because both of those keep looking fine while a comment is
  actually orphaned. See the script's own `KNOWN GOTCHA` note before changing this logic.
- Reconcile keeps a small ledger (`inline-comments-reconciled-log.json`, next to the snapshot file) so
  re-running it after a comment was already reconciled doesn't repost it a second time.
