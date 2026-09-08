---
description: Bidirectional sync between this folder and its linked Confluence page
---

# Sync this folder with its linked Confluence page

This may run **unattended** (a scheduled task invokes it with no human watching). Be conservative
and deterministic: never guess at an ambiguous match, skip and report instead of improvising.

## 0. Load config and state

1. Read `.claude/confluence-sync-config.json` (relative to the current working directory). If
   missing, stop and report: "no config for this folder — run `/setup-sync` first." Do not attempt
   to synthesize settings from anything else.
2. Read (or default) `.claude/confluence-sync-state.json`. Shape:
   ```json
   { "jiraKey": "ABC-123", "pageId": "123456", "lastSyncUtc": "1970-01-01T00:00:00Z", "lastConfluenceVersion": 0, "conflictRemoteVersion": null }
   ```
   If missing entirely, treat as all-zero/epoch/null defaults — this is the first run.
   `conflictRemoteVersion` is null except while a mirror conflict is sitting unresolved in
   `Confluence Sync.md` — see step 3.
3. Record the run-start timestamp in UTC (ISO 8601). Call this `$runStart` — captured now, *before*
   scanning, so files created mid-run aren't missed next time.

## 1. Resolve this folder to a Jira issue

Take the current working directory's own folder name (final path component only) as `$folderName`.

Run this JQL via `searchJiraIssuesUsingJql` (cloudId from config), requesting fields
`["summary", "<linkedPageField from config>", "status"]`:

```
project = <jira.projectKey> AND issuetype = <jira.issueTypeId> AND <jira.extraJql, if non-empty> ORDER BY updated DESC
```

**Always use the configured numeric `issueTypeId`, never a display-name filter** — issue types get
renamed and a name-based filter can silently return zero results.

Match `$folderName` against each result's `summary` by **exact string equality** (trim whitespace).
- **Zero matches** → stop and report: no issue in `<projectKey>` with summary exactly
  `"<folderName>"`. Do not touch the state file.
- **More than one match** → stop and report the ambiguity, listing every matching key. Do not touch
  the state file.
- **Exactly one match** → this is the linked issue. Continue with its key, `status.name`, and the
  configured linked-page field's value.

## 2. Frozen and linked-page checks

- If the linked-page field is empty, stop and report "sin página vinculada en `<KEY>`." Do not touch
  the state file.
- **Frozen status check**: if `status.name` is in `jira.frozenStatuses` (config), stop and report
  "congelado (`<status>`) — la página se considera final, no se sincroniza." Do not touch the state
  file.
- Otherwise extract the Confluence page ID from the URL (`/pages/(\d+)/` → numeric ID, or
  `/wiki/x/([A-Za-z0-9]+)` → that code as `pageId`).
- **Live-doc guard: this plugin only supports classic Confluence pages, never Live Docs** — same
  restriction `pickit-sync-kickoff` already lives with, adopted deliberately rather than tested,
  since a Live Doc write may land in a checkpoint/version-history layer that never reaches the
  actual rendered page, and that risk isn't worth taking for something that can run unattended. Check
  the page's metadata (from the `getConfluencePage` response, or a CQL search if the signal isn't in
  that response) for `subType: "live"` / `iconCssClass: "aui-icon content-type-live-page"`. If
  detected, **stop the entire run here** — neither step 3 (mirror sync) nor steps 4-5 (notes push)
  run — and report: "documento Live de Confluence — conversión manual a página clásica requerida
  (`•••` → `Convertir a página`) antes de poder sincronizar." Do not touch the state file.

## 3. Bidirectional mirror sync: `Confluence Sync.md` ↔ the page

`Confluence Sync.md` is a **live, editable working copy** of the page, not a read-only snapshot.
Edits made to it locally get pushed back; edits made on the page get pulled down. When both sides
changed since the last sync, this does a real three-way merge and only ever asks a human to resolve
an actual overlapping conflict — it never silently picks a winner.

1. Fetch the page via `getConfluencePage` (`contentFormat: "markdown"`). Call its body
   `$remoteMarkdown` and its `version.number` `$remoteVersion`.
2. Read the current contents of `Confluence Sync.md` (empty string if it doesn't exist yet) as
   `$localMarkdown`.
3. Read the current contents of `.claude/confluence-mirror-baseline.md` (empty string if it doesn't
   exist yet) as `$baseline` — this is the 3-way merge's common ancestor: whatever was true at the
   end of the last successful mirror sync.

**Conflict guard, checked before anything else below**: if `$localMarkdown` contains a line starting
with `<<<<<<<`, a previous conflict was written here and hasn't been resolved yet. Skip this entire
section — no pull, no push, no baseline/state changes for the mirror — and note in the report:
"conflicto sin resolver en `Confluence Sync.md`: editá el archivo, quitá los marcadores `<<<<<<<` /
`|||||||` / `=======` / `>>>>>>>`, y el próximo sync lo va a levantar." Continue on to step 4 (notes push) below
regardless — only the mirror is paused.

**Conflict-resolution guard, checked next**: if `state.conflictRemoteVersion` is set (non-null) and
`$localMarkdown` has **no** conflict markers, a previous conflict was just resolved by hand. **Do
not** re-run a fresh three-way merge against the original inputs — a hand-resolved text will almost
never match either original side verbatim, and re-diffing it against the stale base/remote will
manufacture a brand new conflict out of a file a human already reconciled, trapping them in a loop
that never actually resolves. Instead:
- If `$remoteVersion` still equals `state.conflictRemoteVersion` (nobody else touched the page since
  the conflict was written): treat the resolved `$localMarkdown` as authoritative and push it exactly
  like the "local changed only" case below — `updateConfluencePage`, then update the baseline and
  `state.lastConfluenceVersion` from the result, and clear `state.conflictRemoteVersion` back to
  null. Report it as a resolved conflict that's now been pushed, not as a plain push.
- If `$remoteVersion` has moved past `state.conflictRemoteVersion` (someone else edited the page
  again while the conflict sat unresolved): the old resolution can't safely assume anything about
  that newer content. Clear `state.conflictRemoteVersion` to null and fall through to the normal
  four-case logic below, which will correctly attempt a fresh merge against the current remote and
  the (still pre-conflict) baseline — a second conflict here is possible and correct, not a bug.

Otherwise (no pending conflict at all — the common case), compute:
- `localChanged = ($localMarkdown != $baseline)`
- `remoteChanged = ($remoteMarkdown != $baseline)`

And handle whichever case applies:

- **Neither changed** → nothing to do. Report "mirror sin cambios."
- **Remote changed only** → pull: overwrite `Confluence Sync.md` with `$remoteMarkdown`, write the
  same content to `.claude/confluence-mirror-baseline.md`, remember `$remoteVersion` for step 6.
  Report "mirror actualizado desde Confluence (v`$remoteVersion`)."
- **Local changed only** → push: call `updateConfluencePage` (`contentFormat: "markdown"`, body =
  `$localMarkdown`, `versionMessage: "Sync: cambios locales en Confluence Sync.md"`). On success,
  write `$localMarkdown` to the baseline file and remember the response's new version number for
  step 6. Report "cambios locales enviados a Confluence."
- **Both changed** → three-way merge:
  1. Check whether `git` is resolvable (e.g. `Get-Command git`). **If not found**: do not attempt to
     merge or push anything. Write `$remoteMarkdown` to a new file, `Confluence Sync (remote).md`,
     at the folder root — never touch `Confluence Sync.md` itself. Leave the baseline file and
     `state.lastConfluenceVersion` untouched. Report that both a local and a remote change exist and
     need manual reconciliation since Git isn't available for an automatic merge.
  2. **If `git` is available**: write `$localMarkdown`, `$baseline`, and `$remoteMarkdown` to three
     temp files (use the scratchpad/temp directory, not the project folder) and run:
     ```
     git merge-file --diff3 -L "local" -L "base (última sincronización)" -L "confluence (remoto, v<remoteVersion>)" <ours> <base> <theirs>
     ```
     This mutates `<ours>` in place with either the clean merge result or embedded conflict markers.
     Exit code `0` means a clean merge (the two sides touched different, non-overlapping parts of the
     text); a nonzero exit code is the count of real overlapping conflicts.
  3. **Exit code 0**: read the merged `<ours>` file, write it to `Confluence Sync.md`, push it via
     `updateConfluencePage` (`contentFormat: "markdown"`,
     `versionMessage: "Sync: merge automático (cambios locales + remotos sin solapamiento)"`), then
     write the same merged content to the baseline file and remember the new version number for
     step 6. Report it explicitly as an automatic merge, not a plain push.
  4. **Exit code > 0**: read the conflict-marked `<ours>` file and write it directly into
     `Confluence Sync.md` as-is (the familiar `<<<<<<< / ||||||| / ======= / >>>>>>>` convention,
     with the `|||||||` section showing the pre-edit baseline text for context). Do **not**
     call `updateConfluencePage`, do **not** touch the baseline file, do **not** update
     `state.lastConfluenceVersion`. **Do** set `state.conflictRemoteVersion = $remoteVersion` — this
     is what lets the conflict-resolution guard above recognize a later hand-resolved file instead of
     re-merging it against these same stale inputs. Report the conflict plainly — both sides changed
     in a way that couldn't be merged automatically, resolve by editing the file, next sync will pick
     it up.

**Defense in depth**: regardless of which branch above ran, never call `updateConfluencePage` with a
body that contains a `<<<<<<<`/`|||||||`/`=======`/`>>>>>>>` marker line — treat that as an unresolved conflict
and refuse the push, in case the file and the state/baseline ever fall out of step with each other.

## 4. Notes push: find new local files

Recursively list files in the current working directory matching `sync.localFilePatterns` from
config — **excluding** `Confluence Sync.md`, `Confluence Sync (remote).md`, and anything under
`.claude/` (which now also holds `confluence-mirror-baseline.md`).

(A `.drawio` file next to an `.mmd` one is the flowchart-builder plugin's generated free-hand-editing
copy — it's the sync source of truth's sibling, not a second diagram to process; ignore `.drawio`
files here entirely, only `.mmd`.)

**Duplicate `.gdoc` handling** (only if `sync.dedupeGdocCopies` is true, and only for `.gdoc` files —
`.md`/`.mmd` don't get this Drive-sync duplication behavior):

1. Compute each `.gdoc` file's base name: strip a leading `"Copia de "` / `"Copy of "` and a trailing
   `" (<digits>)"` immediately before `.gdoc`.
2. Group by base name. Groups of 1 need no further work. For groups of 2+, treat as **candidates**
   only:
   a. **Size check** via `get_file_metadata` — if sizes differ by more than ~20%, not confirmed
      duplicates, process independently.
   b. **Content check** for candidates that pass size — fetch via `read_file_content`, compare a
      short excerpt. Same content → confirmed duplicate.
3. For each **confirmed** group: keep one canonical file (prefer the one without the
   "Copia de"/"Copy of" prefix; otherwise earliest creation time). Call the Google Drive connector's
   `trash_file` on every other member's `doc_id` (reversible — moves to Drive Trash, never a
   permanent delete). Log every trashed file in the final report.
4. Only the canonical file per confirmed group (plus files that failed grouping/verification)
   continues below.

**Watermark filter**: for `.gdoc` and `.md`, only files whose filesystem **creation** time is after
`state.lastSyncUtc` count as new. For `.mmd`, use **modification** time instead — diagrams are
typically edited in place rather than recreated.

If zero new eligible files, skip step 5 (no Confluence edit) — report "sin archivos nuevos" for the
notes-push direction, and continue on to step 6.

## 5. Extract and merge new files into the page

**Extraction**, same as `pickit-sync-kickoff`:
- **`.gdoc`**: read the local shortcut file as JSON, take `doc_id` (fallback `resource_id`), fetch
  real content via the Drive connector's `read_file_content`. Never treat the raw shortcut JSON as
  content.
- **`.md`**: read directly with the `Read` tool.
- **`.mmd`**: Mermaid flowchart source (flowchart-builder plugin's format), not prose. **Render it to
  a real image and attach it to the page** — a script-based render + REST-API upload, no browser
  automation:

  1. **Render to PNG** via the `@mermaid-js/mermaid-cli` npm package (command `mmdc`; bundles its own
     headless Chromium via Puppeteer — no desktop app, no admin rights). Check with `mmdc -V`; if
     missing, `npm install --global @mermaid-js/mermaid-cli` (needs Node/npm on PATH — check for a
     portable Node install already present on the machine before assuming Node needs installing):
     ```
     mmdc -i "<dir>/<basename>.mmd" -o "<dir>/<basename>.png" -b transparent
     ```
     One `.mmd` file is one diagram — no multi-page splitting concern.
  2. **Upload the PNG as a page attachment via the Confluence REST API** (v1 — the v2 API has no
     write endpoint for attachments), authenticated with an Atlassian API token retrieved via
     `Get-ConfluenceApiToken` (defined below) — never a bare `$env:CONFLUENCE_API_TOKEN` check, and
     never commit the token or print it in a report:
     ```powershell
     function Get-ConfluenceApiToken {
         $raw = $env:CONFLUENCE_API_TOKEN
         if (-not $raw) { $raw = [Environment]::GetEnvironmentVariable("CONFLUENCE_API_TOKEN", "User") }
         if (-not $raw) { $raw = [Environment]::GetEnvironmentVariable("CONFLUENCE_API_TOKEN", "Machine") }
         if ($raw) { return $raw.Trim() }
         return $null
     }
     $token = Get-ConfluenceApiToken
     $authPair = "<account email>:$token"
     $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($authPair))
     Invoke-RestMethod -Uri "https://$($config.cloudId)/wiki/rest/api/content/$pageId/child/attachment" `
       -Method Post -Headers @{Authorization="Basic $auth"; "X-Atlassian-Token"="no-check"} `
       -Form @{file=Get-Item "<dir>/<basename>.png"}
     ```
     **Why the helper, not a bare `$env:` check**: a token set via `setx` (the normal setup path)
     only updates the registry — it does not propagate into a Claude Code session or terminal that
     was already running when `setx` ran, so `$env:CONFLUENCE_API_TOKEN` alone reads empty right
     after setup even though the token genuinely exists (confirmed: this exact false-negative
     happened on a real run and nearly triggered an unnecessary "recreate your token" round-trip).
     The helper checks the fast path (already-inherited process env) first, then falls back to
     reading the registry directly (User, then Machine scope), which works regardless of when the
     current process started. **It also always `.Trim()`s the result** — a token set from a
     piped/pasted value can pick up a trailing newline or space (a real case: a trailing `\n`
     produced `401`/`403` on *every* Atlassian endpoint, Jira included — indistinguishable from
     "wrong credentials" until you check for stray whitespace in the stored value).
     Re-uploading a same-named file to the same page creates a new attachment version automatically
     — no need to delete the old one first.
     **If this returns `403` with `"Current user not permitted to use Confluence"`**, don't jump
     straight to a scope diagnosis — check for token whitespace corruption first (previous
     paragraph's note; a real case had a token that was already classic/unscoped and still failed
     on *every* Atlassian endpoint until a trailing newline was trimmed). Only if the token is
     confirmed clean (control test: the *same* token succeeds against Jira's
     `GET /rest/api/3/myself` but fails on Confluence) is this a genuine *token scope* problem — a
     scoped API token created without Confluence access. Then point the user to
     `id.atlassian.com/manage-profile/security/api-tokens` to recreate it as a classic (unscoped)
     token, or add scopes `read:page:confluence`, `write:page:confluence`,
     `write:attachment:confluence` to the scoped one.
  3. **Fetch the uploaded attachment's Media Services IDs — do not skip this.** The upload response
     from step 2 does **not** carry the IDs this HTML format needs to render the image; a follow-up
     `GET` with `expand=extensions` does:
     ```powershell
     $meta = Invoke-RestMethod -Uri "https://$($config.cloudId)/wiki/rest/api/content/$pageId/child/attachment?filename=<basename>.png&expand=extensions" -Headers @{Authorization="Basic $auth"}
     $fileId = $meta.results[0].extensions.fileId
     $collection = $meta.results[0].extensions.collectionName   # normally "contentId-<pageId>"
     ```
     **Do not use `<ac:image><ri:attachment ri:filename="..." /></ac:image>`** — that is classic
     Confluence storage-format XML, which this HTML content format explicitly does not support
     (its own format guide says storage-format macros "will render as raw text if converted").
     **Also do not use an external `<img src="...">` pointing at the attachment's download URL** —
     confirmed on a real page: Confluence's converter treats a same-site authenticated URL as an
     unresolvable link/smart-card, rendering a generic "i" placeholder icon, not the image, no
     matter how the URL is shaped (`/rest/api/...` and `/wiki/download/attachments/...` both fail
     the same way).
  4. **Reference the uploaded attachment in the page body** in the merge below using the real media
     node syntax, with the `fileId`/`collection` from step 3 — insert this at the point in the
     merged HTML where the diagram belongs, not as a separate edit:
     ```html
     <figure data-type="media-single" data-layout="center" data-width="80">
       <div data-type="media" data-media-type="file" data-id="<fileId>" data-collection="<collection>" data-alt="<basename>.png"></div>
     </figure>
     ```
     Confirmed working end-to-end this way on a real page — this is the only syntax in this HTML
     format that renders a real inline image from a REST-API-uploaded attachment.
  5. **If `Get-ConfluenceApiToken` returns nothing from any of the three lookups**, don't fail the
     run — extract every `value="..."` label from the diagram's sibling `.drawio` copy if one
     exists (HTML-entity decoded) as a last-resort label-list fallback, and note in the report that
     the token is missing so the PNG couldn't be rendered/attached.

  Never paste the raw Mermaid text as a code block on the live page instead of rendering it — a site
  with no Mermaid-rendering marketplace app installed will only show it as plain/unrendered text or
  "Error al cargar la extensión," never an actual diagram (confirmed on `pickit.atlassian.net`,
  2026-09-03 — don't assume every Confluence site this plugin targets has one installed either,
  since this plugin isn't Pickit-specific).

If a file can't be read this way, skip it and note it as unreadable — don't fail the whole run.

**Merge into the page** (fetch first via `getConfluencePage`, `contentFormat: "html"` — the Live-doc
guard already ran in step 2, so this run is known to be against a classic page; apply the same
oversized-page guard `pickit-sync-kickoff` uses: if the page is oversized, re-read via
`contentFormat: "adf"` and consider splitting into child pages rather than giving up):

Since this plugin has no fixed target template to work against (unlike Pickit's Anexo A-F kickoff
doc), use this rule for each new file's content:

1. Look at the page's existing top-level headings. If a new file's own first heading text-matches an
   existing page heading (case-insensitive, ignoring punctuation), **integrate** into that section:
   read the section's current text, understand what it claims, and rewrite it as a single coherent,
   up-to-date statement — weaving in the new information rather than appending a dated paragraph. No
   date-stamping or meeting-attribution inside that prose ("Actualización 21/08", "en la reunión se
   decidió..." — state facts as facts, not as dated events).
2. Otherwise, append a new entry under a `## Sync updates` section at the end of the page (create
   that section if it doesn't exist yet) as `**<date>** — <filename>: <one/two sentence summary of
   what it adds>.` This changelog-style append is the safe default when there's no known place to
   integrate content — never invent a new top-level section elsewhere on the page to "make it fit."
3. Multiple new files can be merged into one `updateConfluencePage` call — don't call it once per
   file.
4. Never delete or shorten existing content unless a new file explicitly supersedes it.
5. **Never put Markdown emphasis syntax (`**bold**`, `*italic*`) inside an HTML `<pre><code>` block**
   — Confluence code blocks display their content literally, so `**Dado que**` renders as the literal
   asterisks, not bold text (this actually happened here: Gherkin-style acceptance criteria had been
   written as `<pre><code>**Dado que** ...</code></pre>` and showed broken). If a Gherkin/step-style
   block needs bold keywords, write one `<p><strong>Keyword</strong> rest of the line</p>` per line
   instead of a single code block.
6. Call `updateConfluencePage` with `contentFormat: "html"`, a `versionMessage` like `Sync automático:
   <n> archivo(s) nuevo(s) (<nombres>)`. Note the resulting `version.number` — this run's notes push
   can itself move the page ahead of what `Confluence Sync.md` currently reflects, which step 6
   below reconciles.

## 6. Final mirror refresh

If step 5 actually ran an edit (new files were merged into the page), the mirror written in step 3 is
now stale — it reflects the page as it stood *before* that edit. Re-fetch the page one more time
(`getConfluencePage`, `contentFormat: "markdown"`). If its `version.number` is now ahead of whatever
is currently in `.claude/confluence-mirror-baseline.md`'s corresponding sync, overwrite both
`Confluence Sync.md` and the baseline file with this latest content — this is a plain pull, never a
conflict, since nothing local changed between step 3 and now. Skip this step entirely if step 5 made
no edit, or if step 3 ended in an unresolved-conflict state (don't touch the mirror while a conflict
is pending).

## 7. Update state

If step 1 resolved to exactly one non-frozen issue with a linked page (i.e. this run got at least to
step 3), write `.claude/confluence-sync-state.json`:
```json
{ "jiraKey": "ABC-123", "pageId": "123456", "lastSyncUtc": "...", "lastConfluenceVersion": 42, "conflictRemoteVersion": null }
```
- `jiraKey`, `pageId` — from this run's resolution.
- `lastSyncUtc` — `$runStart`.
- `lastConfluenceVersion` — the page's version number as of the very last write this run touched
  (step 6's refresh if it ran, else step 5's edit if it ran, else step 3's push/merge if that's as
  far as the mirror got, else the version simply read in step 3 if nothing changed).
- `conflictRemoteVersion` — whatever step 3 left it as: set to `$remoteVersion` if step 3 just wrote
  a fresh conflict, cleared to `null` if step 3 resolved one (or never had one). Never touch this
  field anywhere else.

Write this regardless of whether step 4/5 found new files — the watermark still needs to advance so
next run doesn't rescan everything. If resolution failed at step 1 or 2, do not write state at all.

## 8. Report

Print a concise summary covering both directions:
- Which issue/page this folder resolved to (or why resolution failed/was ambiguous/frozen).
- Mirror sync (step 3): no-op / pulled (to which version) / pushed / auto-merged cleanly / **conflict
  written to `Confluence Sync.md` and unresolved** / Git unavailable, wrote
  `Confluence Sync (remote).md` instead — be explicit about which one happened, this is the part most
  likely to need the user's attention.
- Notes push (steps 4-5): files merged (noting which were integrated into an existing section vs
  appended under "Sync updates," and for `.mmd` files whether the diagram was rendered and
  attached as a PNG or only had its labels extracted as a fallback — and if only labels, why: the
  API token was missing, or PNG rendering was otherwise unavailable), duplicate `.gdoc`
  files trashed, unreadable files skipped, or "sin archivos nuevos" if none.
- Final mirror refresh (step 6): whether it fired and updated the mirror again after notes push.
