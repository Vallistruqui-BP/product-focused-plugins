---
description: Safeguard Confluence inline comments around a manual full-body republish (snapshot before, reconcile after)
---

# Preserve inline comments across a republish

A full-body page replace (the markdown-push + HTML-patch two-pass workflow `/sync-doc` uses) can
delete-and-recreate the content node an inline comment is anchored to, **orphaning** the comment —
it still exists on the page, but loses its highlighted anchor. Footer/page-level comments are never
affected and need no handling.

This command is a manual, explicit safeguard — it does **not** run automatically as part of
`/sync-doc`. Run it yourself around a publish when you want the guarantee.

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
- This is a **manual** safeguard by design: it adds two extra API round-trips and isn't needed for
  small in-place edits, only for full-body replaces where you specifically care about not losing
  inline review comments.
