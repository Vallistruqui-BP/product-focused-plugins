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

**Known limitation — why every markdown push snapshots comments automatically**: a full-body
`updateConfluencePage` call with `contentFormat: "markdown"` strips Confluence's inline-comment
anchor marks from the **entire** page body, not just the paragraphs actually being edited — markdown
has no representation for an anchor mark at all, so the whole body effectively gets rebuilt without
them. The comment *object* survives untouched (same ID, `resolutionStatus` still reports `"open"`,
never flips to `"dangling"`) — only the highlight/anchor in the live content is gone, silently.
Confirmed on a real page (3233677317, 2026-09-14): 10 inline comments across several rounds of
markdown pushes went invisible with no error, no status change, and nobody noticed until a human
asked about them directly. `contentFormat: "html"` pushes (step 5 below) are round-trip safe and do
**not** have this problem — only the markdown-format push in this step does. That's why steps 3.1 and
3.2 below are mandatory, not optional, and don't ask for confirmation — they're a cheap safety net
around a push mode this plugin already always uses.

### 3.1. Snapshot inline comments (before any push below)

Run, once, before evaluating any of the four cases below:
```powershell
pwsh -File "<this plugin's own installed dir>/scripts/preserve-orphaned-comments.ps1" -Mode Snapshot -PageId $pageId
```
Resolve the script path relative to this plugin's own installed location, never hardcoded. If the
script errors (e.g. missing API token), don't fail the whole run — note in the final report that
comment-preservation was skipped this run, and continue with the mirror sync itself.

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

### 3.2. Reconcile any orphaned inline comments (after the mirror sync above)

Run once, regardless of which of the four cases above fired (including "neither changed" — cheap and
harmless if nothing was orphaned):
```powershell
pwsh -File "<this plugin's own installed dir>/scripts/preserve-orphaned-comments.ps1" -Mode Reconcile -PageId $pageId
```
Capture its stdout — it reports how many comments it checked and how many (if any) it found orphaned
and reposted as footer comments. Include that count in the final report (step 8) so this is visible,
not silent. If step 3.1's snapshot was skipped (missing token, etc.), this will have nothing to
reconcile against — skip it too and note the same in the report.

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
- **`.mmd`**: Mermaid flowchart source (flowchart-builder plugin's format), not prose.

  **0. Detect native Mermaid support once per run, before processing any `.mmd` file.** Some
  Confluence instances have a Mermaid-rendering marketplace app installed (confirmed present on
  `pickit.atlassian.net` as of 2026-09-15 — corrects an earlier note in this file from 2026-09-03
  claiming none was installed; app availability can change over time, so always re-check live, never
  trust a cached yes/no from a previous run or from this file's own history). When present, embed the
  diagram as a **live native macro** instead of a rendered PNG — strictly better whenever available:
  no Chromium canvas-corruption risk, no resolution/legibility tradeoffs, no attachment-version
  churn, infinitely zoomable, always reflects the exact current `.mmd` source with zero render step.
  ```powershell
  $token = Get-ConfluenceApiToken
  $authPair = "<account email>:$token"
  $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($authPair))
  try {
    $plugins = Invoke-RestMethod -Uri "https://$($config.cloudId)/wiki/rest/plugins/1.0/" -Headers @{Authorization="Basic $auth"}
    $mermaidApp = $plugins.plugins | Where-Object { $_.key -eq "tech.labs.app.mermaid" -and $_.enabled }
    $nativeMermaidAvailable = [bool]$mermaidApp
  } catch {
    $nativeMermaidAvailable = $false   # 401/403/any failure => treat as unavailable, never block the sync on this check
  }
  ```
  This endpoint (`/wiki/rest/plugins/1.0/`) needs admin-level API-token scope to list installed
  plugins — a token without that scope will 401/403 here, which is a normal, expected configuration
  (not a bug) and must silently fall through to the PNG path below, no error surfaced to the user for
  this specific failure mode. Check once at the start of this run and reuse the result for every
  `.mmd` file processed — don't re-check per diagram.

  **Gotcha that will burn a future editor: the app key is not the macro's extension key.** The
  installed-plugins listing above reports the app under key `tech.labs.app.mermaid` — that string is
  *only* useful for the detection check above. It is **not** what goes in `data-extension-key` when
  embedding the macro; using it there produces a structurally-valid extension node that publishes
  fine but renders "Error al cargar la extensión" (confirmed by trying it directly). The actual
  extension key for embedding is **`mermaidjs`**, discovered by inserting the macro through
  Confluence's own editor UI (the "+" insert-block menu → search "mermaid" → "Mermaid for Confluence"
  → paste a diagram → Insert → publish) and reading back the real markup Confluence generated via
  `getConfluencePage`.

  **If native Mermaid is available (`$nativeMermaidAvailable = $true`), embed this node** at the
  point in the merged HTML where the diagram belongs, using the diagram's raw, unmodified `.mmd`
  content (do **not** prepend the `fontSize` init directive from the PNG path below — that directive
  exists purely to work around a fixed-pixel-display-width legibility problem that doesn't apply to a
  live-rendered vector diagram; sending it here would just permanently bake an oversized font into the
  live diagram's own definition for no reason):
  ```html
  <div data-type="extension" data-extension-key="mermaidjs" data-extension-type="com.atlassian.confluence.macro.core" data-layout="default" data-parameters="<see below>"></div>
  ```
  `data-parameters` is a **triple-encoded** string — get this wrong and the macro silently fails to
  render (structurally valid, empty/broken on screen) rather than erroring loudly, so build it
  carefully in this exact order:
  1. Start with the Mermaid source as a plain string (the `.mmd` file's raw content, verbatim).
  2. JSON-encode `{"diagramDefinition": "<that string, with real newlines escaped to literal \n and
     any \" escaped>"}` — this produces a JSON string like
     `{"diagramDefinition":"flowchart TD\n    A-->B"}`.
  3. That whole JSON string becomes the **value** of `macroParams.__bodyContent.value` inside a larger
     JSON object:
     ```json
     {
       "macroParams": {
         "fileName": {"value": "mermaid_<unique id, e.g. epoch millis>"},
         "_parentId": {"value": "<pageId, as a string>"},
         "theme": {"value": "default"},
         "version": {"value": "2"},
         "__bodyContent": {"value": "<the step-2 JSON string, itself embedded as a JSON string value>"}
       },
       "macroMetadata": {
         "macroId": {"value": "<any random v4 UUID>"},
         "schemaVersion": {"value": "1"},
         "placeholder": [{"type": "icon", "data": {"url": "https://mermaidtechlabs.herokuapp.com/images/mermaid_icon.png"}}],
         "title": "Mermaid for Confluence"
       }
     }
     ```
  4. Serialize *that* whole object to a JSON string, then HTML-entity-escape it (`"` → `&quot;`) to
     become the literal `data-parameters="..."` attribute value in the HTML you send to
     `updateConfluencePage`. `theme`/`version`/`schemaVersion`/`title`/`placeholder` are fixed
     literals — copy them as shown, no need to vary them. Only `fileName`, `_parentId`,
     `__bodyContent`, and `macroId` are per-diagram/per-page values.
  Confirmed working end-to-end this way on a real page (published via `updateConfluencePage`,
  re-fetched via `getConfluencePage` to confirm the round-trip matches, and visually confirmed in a
  real browser — the diagram rendered as actual boxes/arrows/decision-diamonds, not an error
  placeholder).

  **`fileName` must be unique across every macro instance on the page — this is a real gotcha, not
  a nice-to-have.** The app appears to key each diagram's stored definition by this value; two
  `mermaidjs` macros sharing the same `fileName` silently fail to render **both** of them (no error,
  no placeholder — just a gap between the preceding paragraph and the following content, exactly
  like the diagram was never inserted). This bit a real migration: a naive
  `int(time.time()*1000000) % 10**13` generator produced the *same* value for two diagrams rendered
  in the same script run (sub-millisecond collision), breaking both silently — only caught by
  actually opening the published page in a browser and noticing the diagram was missing, not by
  trusting the API round-trip (a structurally valid extension node with a colliding `fileName` still
  round-trips fine through `getConfluencePage`, so that check alone does **not** catch this). Use a
  generator that's guaranteed unique across a whole batch — e.g. epoch-millis plus a monotonically
  incrementing per-run counter, not epoch-micros modulo-truncated — and after publishing **always
  visually confirm each diagram actually rendered**, not just that the page saved.

  **Always keep a collapsed "Ver código Mermaid" `<details>`/`expand`-macro block with the raw
  Mermaid source immediately below the native embed, for every diagram, even though the diagram
  itself is live** — this was tried as "skip it, the diagram is self-documenting" in an earlier
  revision, but the user explicitly asked to keep the source visible underneath regardless, so it's
  not optional: build it the same way as the PNG path's source block (point 5 below produces the
  `<details><summary>Ver código Mermaid</summary><pre><code class="language-plaintext">...</code>
  </pre></details>` shape for the HTML content-format path; in raw Confluence storage format it's
  `<ac:structured-macro ac:name="expand"><ac:parameter ac:name="title">Ver código Mermaid</ac:parameter>
  <ac:rich-text-body><ac:structured-macro ac:name="code"><ac:parameter ac:name="language">text</ac:parameter>
  <ac:plain-text-body><![CDATA[<raw .mmd source>]]></ac:plain-text-body></ac:structured-macro>
  </ac:rich-text-body></ac:structured-macro>` — match whichever content format you're actually
  publishing through).

  **If native Mermaid is NOT available** (`$nativeMermaidAvailable = $false`), fall back to the full
  PNG render/upload/figure-embed pipeline below, unchanged — **render it to a real image and attach it
  to the page**, a script-based render + REST-API upload, no browser automation:

  1. **Render to PNG at an adaptive resolution** via the `@mermaid-js/mermaid-cli` npm package
     (command `mmdc`; bundles its own headless Chromium via Puppeteer — no desktop app, no admin
     rights). Check with `mmdc -V`; if missing, `npm install --global @mermaid-js/mermaid-cli`
     (needs Node/npm on PATH — check for a portable Node install already present on the machine
     before assuming Node needs installing). **Never render with a single fixed `-s` value for
     every diagram** — a flat scale factor either blurs large/dense diagrams when the viewer zooms
     in, or wastefully bloats tiny diagrams that never needed the extra pixels. Instead, size the
     scale to the diagram itself, in two passes:

     a. **Prepend a font-size init directive to a scratch copy of the `.mmd` before rendering —
        never render the checked-in file directly.** This is the primary legibility lever, and it is
        NOT the same thing as the `-s` scale factor in step (b) below — see the explainer after this
        list for why both exist and what each one actually fixes.
        ```
        %%{init: {'themeVariables': {'fontSize': '18px'}}}%%
        <...rest of the .mmd file, unchanged...>
        ```
        Write this to `<scratchpad>/<basename>.mmd` (prepend the directive, then the original file's
        full contents) and render THAT file in both the probe and final passes below — never the
        original `<dir>/<basename>.mmd`, and never edit the checked-in source file itself to add
        this line (keep the source diagrams clean/portable; the directive is a render-time-only
        concern). `18px` was confirmed on a real diagram (`flujo-chequeo-proactivo-marcado-accidental.mmd`)
        to grow node/box text noticeably without any width change (still 784px wide) — height grew
        1570px → 1678px, i.e. boxes got taller/text wrapped more to fit the bigger font in the same
        column width, which is exactly the effect wanted. Adjust the value only if a real diagram's
        rendered legibility says otherwise.
     b. **Probe pass** — render once at the `mmdc` default scale (no `-s` flag) to a scratch path,
        to measure the diagram's own natural size:
        ```
        mmdc -i "<scratchpad>/<basename>.mmd" -o "<scratchpad>/<basename>-probe.png" -b transparent
        ```
        Read the PNG's own `IHDR` chunk for its pixel width/height (bytes 16-24 of the file: two
        big-endian uint32s) — no image library needed, e.g. via a one-line Python `struct.unpack`
        or PowerShell `[System.Drawing.Image]`. Take `longEdge = max(width, height)` as the
        complexity signal (Mermaid flowcharts grow almost entirely in one axis — usually height for
        `flowchart TD` — so the long edge tracks "how much diagram there is" far better than either
        dimension alone, and far better than counting nodes in the `.mmd` source, which doesn't
        account for label length or subgraph nesting).
     c. **Compute the scale factor**: `scale = clamp(ceil(longEdge / 300), 5, 16)`, THEN clamp it a
        second time against a hard pixel-area ceiling (see the "Chromium canvas-area limit" explainer
        below) — `scale = min(scale, floor10(sqrt(240_000_000 / (probeWidth * probeHeight))))` (round
        the area-derived scale DOWN to one decimal place, not a whole number — the safety margin is
        narrow enough that whole-number rounding wastes real resolution on diagrams the area cap
        governs), with a floor of 4 on the final result so a diagram that's already huge at its
        natural size never divides down to something blurry. In practice this second clamp only ever
        bites on the tallest diagram on a page (a `flowchart TD` many thousands of px tall after the
        font-size bump in step (a)) — small and medium diagrams stay governed entirely by the
        width-based formula above, which is now the binding constraint for most diagrams on a typical
        page, not the exception.
        Calibrated against 4 real diagrams on a real page, in three rounds: round 1 (divisor 1300,
        floor 3, ceiling 6) landed a 3988px-tall diagram at scale 4 and smaller diagrams at scale 3.
        Round 2 (divisor 900, floor 4, ceiling 7) tightened that after the user asked for more
        definition. Round 3 (this one) found, by actually checking which clamp bound each diagram, that
        3 of 4 diagrams on the real page were landing on the width-formula's FLOOR (scale 4) with the
        pixel-area budget barely touched (e.g. a diagram using only ~24M of a 230M px cap) — the area
        cap was never the bottleneck for anything but the single tallest diagram, so tightening the
        area cap alone (as round 3 first tried) barely moved the needle on the user's actual complaint
        ("Flujo 3 es masivo pero le falta resolución"). The real fix was tightening the width-formula
        divisor (900→300) and floor (4→5) so diagrams that aren't anywhere near the area ceiling
        render sharper too. Verified on the real page: the tallest diagram went 7→7.4 (modest, it's
        area-capped), but the other three went 4→6, 4→7, and 4→9 respectively — a real, visible jump.
        Adjust the divisor/floor/ceiling only if a real diagram's rendered legibility says otherwise —
        don't tune this from first principles alone, and don't assume the area cap is what's limiting
        a diagram without checking which clamp actually bound its scale. **The pixel-area ceiling is a
        different, correctness-not-legibility constraint — see "Chromium canvas-area limit" below —
        and must never be removed or raised without re-verifying against that limit by direct render
        testing, not by trusting a previously-documented number.**

     **Chromium canvas-area limit — a real ceiling that WAS hit, don't re-raise scale past it.**
     `mmdc` renders via Puppeteer/Chromium, which silently corrupts (not errors) output once the
     total canvas area exceeds some threshold — it does not crop or refuse, it produces a PNG with
     random-looking overlapping/misplaced node boxes and blank pale-yellow rectangles blotting out
     content partway down the image. **The failure boundary is narrower than earlier documented here
     — re-verify by direct binary-search testing before trusting any single number in this file.**
     Round 2 estimated ~268,435,456px (16384²) from two widely-spaced test points (clean at 155.8M,
     corrupt at 432.8M) and set a 230M cap. Round 3 binary-searched with closer test points on
     `flujo-salida-pickers-lote.mmd` (same fontSize=18px directive, only `-s` varied) and found: clean
     at `-s 7.5` (5880×41408, 243.5M px, checked top/q1/mid/q3/bottom — all clean) and corrupted at
     `-s 7.6` (5958×41960, 250.0M px — same "blank yellow rectangle overlapping content" signature
     confirmed at the SAME position as the round-1 `-s 8`/277M corruption, i.e. this is one consistent
     failure mode, not two different bugs). So the true wall sits between 243.5M and 250.0M px — NOT
     268M. **Production cap is now 240,000,000px** (comfortable margin below the confirmed-clean 243.5M
     point, meaningful headroom above the old 230M cap). This was originally misreported by the user
     as "todo amarillo" / a cropping-and-merge bug — it is neither: there is no crop/merge step
     anywhere in this pipeline (single `mmdc` invocation per diagram, one screenshot, no
     tiling/stitching code exists in this plugin or the sibling `pickit-sync-kickoff`) and no
     color/classDef issue — it is Chromium's own canvas rasterizer overflowing silently on an oversized
     single screenshot, and the pale-yellow blank-rectangle artifact is that overflow's visual
     signature, not a missing `class` assignment. The fix is the pixel-area cap in step (c) above — NOT
     reverting the font-size legibility fix, NOT cropping into bands, NOT trusting the previous 268M/
     230M numbers without re-testing. Verified fix (round 3): `flujo-salida-pickers-lote.mmd` at the
     resulting `-s 7.4` (5802×40855, 237.0M px) rendered clean across 5 sampled bands (top, q1, mid,
     q3, bottom) checked directly, not just a probe.
     d. **Final pass** — render for real at the computed scale, discard the probe file:
        ```
        mmdc -i "<scratchpad>/<basename>.mmd" -o "<dir>/<basename>.png" -b transparent -s <scale>
        ```
     One `.mmd` file is one diagram — no multi-page splitting concern.

     **Why font-size (step a) and scale (step c) are different levers, and why scale alone never
     fixed the "cajas ilegibles" complaint in earlier rounds:** the page's content column has a
     fixed, genuine width (confirmed via a raw ADF probe on a real page: `layout: "wide"` normalizes
     to the exact same `680px`/`pixel` as `layout: "center"` — only `layout: "full-width"` breaks out
     wider, to `960px`, which overshoots the paragraph column and was rejected for that reason). The
     `-s` scale factor uniformly multiplies EVERY pixel in the raster — the diagram's overall pixel
     dimensions grow, but the ratio of "how much of the image's own width a box's text occupies"
     never changes, so when the browser downscales that raster back down to fit the fixed 680px
     column, the text renders at essentially the same *visual* size regardless of how high `-s` was
     pushed (scale only buys crispness/DPI for zooming or retina displays, not bigger-looking text in
     the normal inline view). The only way to make box text visually bigger at a *fixed* display
     width is to make Mermaid itself draw bigger text relative to the diagram's own layout — which is
     exactly what the `fontSize` theme variable in step (a) does (confirmed empirically: width stays
     flat, height grows, meaning text now claims more of that same fixed width). **Do not try to fix
     legibility by raising the scale ceiling — it does not work; raise the font-size instead.**

     **On cropping/merging a very tall diagram into bands (considered and rejected twice):** doesn't
     help legibility, for the same underlying reason — a cropped vertical band still renders at the
     same fixed column width as the uncropped image, so per-box text stays the same visual size. A
     genuine dimension ceiling WAS later found (see "Chromium canvas-area limit" above) — but the fix
     for that is capping `-s` via the pixel-area formula in step (c), not cropping/stitching; a
     single clean `mmdc` screenshot under the area cap has no seam-artifact risk that band-splitting
     would otherwise exist to solve. Cropping still adds real complexity (N attachments per diagram,
     N figure blocks, harder to keep in sync when the source `.mmd` changes) for no upside once the
     area cap is in place. Not implemented; revisit only if the pixel-area cap alone is ever
     insufficient (e.g. a diagram whose width-based scale-16 target still exceeds 240M px at its
     *natural* pre-cap size — hasn't happened on any diagram seen so far, but the ceiling was raised
     from 7 to 16 in round 3, so re-check this if a genuinely enormous new diagram shows up).

     **`-s` accepts a decimal value** (e.g. `-s 7.4`), not just an integer — use the full computed
     value, don't round to a whole scale, since the safety margin under the corruption boundary is
     narrow enough that whole-number rounding throws away real, safe resolution.
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
     <figure data-type="media-single" data-layout="center" data-width="100" data-width-type="percentage">
       <div data-type="media" data-media-type="file" data-id="<fileId>" data-collection="<collection>" data-alt="<basename>.png"></div>
     </figure>
     ```
     Confirmed working end-to-end this way on a real page — this is the only syntax in this HTML
     format that renders a real inline image from a REST-API-uploaded attachment. `data-width="100"`
     with `data-layout="center"` makes the diagram span the full paragraph width and stay centered,
     matching the rest of the page's formatting — confirmed as the preferred default on a real page
     after the user asked for wider diagrams twice (first from 80px effective to 80%, then from 80%
     to 100%). **Never omit `data-width` entirely** — confirmed on a real page that omitting it makes
     Confluence fall back to the image's own native pixel width (e.g. `5488px`) as a literal pixel
     width, which badly overflows the content column; always send an explicit `data-width="100"`.
     **Correction to earlier guidance in this file (previously claimed `data-width-type="percentage"`
     was mandatory and its absence caused a near-invisible diagram) — re-investigated on a real page
     via three direct ADF probes and found to be a misdiagnosis:** `data-width-type` is not
     authoritative. Confluence silently normalizes `mediaSingle.attrs.widthType` to `"pixel"` on
     write regardless of what width-type value the HTML/ADF send specifies (confirmed: an explicit
     `widthType: "percentage"` sent via a raw ADF write round-tripped back as `{"width": 680,
     "widthType": "pixel"}` — `680px` being this page's actual, correct, full-column-width value, not
     a bug). The real variable that matters is the **numeric `data-width` value itself** — small
     values like `80` (a leftover from an even earlier default, not `80%`) really did render a
     near-invisible diagram, but that was because `80` was being stored as `80px` literal, not
     because of a missing width-type flag; sending `data-width="100"` (the current default per this
     step) resolves to the correct full-column width either way. **You do not need to set
     `data-width-type` at all going forward** — `data-width="100"` alone is sufficient and is what
     the official Confluence HTML-format guide's own canonical media example uses (no width-type).
     Setting `data-width-type="percentage"` explicitly is harmless (it's simply overridden/ignored on
     write) but no longer treated as load-bearing in this file.
  5. **Immediately after that `<figure>`, append a collapsed Mermaid-source block** — an `expand`
     (`<details>`) containing the diagram's raw `.mmd` text as-is, verbatim, in a code block:
     ```html
     <details><summary>Ver código Mermaid (<basename>.mmd)</summary>
     <pre><code class="language-mermaid"><raw .mmd file contents, HTML-escaped></code></pre>
     </details>
     ```
     This is collapsed by default (`<details>` with no `open` attribute) so it doesn't clutter the
     page visually, but it means the page's own markdown export — what `Confluence Sync.md` mirrors
     back to (step 3/6) — carries the actual Mermaid source next to the image, not just a PNG
     reference. That's what lets an agent that later reads `Confluence Sync.md` (rather than looking
     at the rendered page) understand what the flow actually does instead of seeing an opaque image
     link. HTML-escape the `.mmd` content (`<`, `>`, `&`) before embedding — it's arbitrary Mermaid
     source, not markup. One expand per diagram, placed right after its own figure, not batched at
     the end of the page.
  6. **If `Get-ConfluenceApiToken` returns nothing from any of the three lookups**, don't fail the
     run — extract every `value="..."` label from the diagram's sibling `.drawio` copy if one
     exists (HTML-entity decoded) as a last-resort label-list fallback, and note in the report that
     the token is missing so the PNG couldn't be rendered/attached. Still append the collapsed
     Mermaid-source block from point 5 even in this fallback case — it costs nothing (no attachment
     upload involved) and is the only context an agent will get about the flow when the image itself
     couldn't be produced.

  Never paste the raw Mermaid text as a **visible, uncollapsed** code block *instead of* rendering
  the image — on a site where step 0's detection says native Mermaid isn't available (or wasn't
  checked), raw Mermaid text left unrendered just shows as plain text or "Error al cargar la
  extensión," never an actual diagram (this is genuinely instance-dependent — `pickit.atlassian.net`
  did NOT have a Mermaid app as of 2026-09-03, but DOES as of 2026-09-15; don't assume any given site
  this plugin targets has one installed, since this plugin isn't Pickit-specific — always run step 0's
  live detection, never assume based on this file's history). The collapsed block from point 5 is
  additive context alongside the rendered PNG in the fallback path, not a substitute for it — always
  render and attach the PNG per points 1-4 when the token is available and native Mermaid isn't.

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
- Comment preservation (steps 3.1/3.2): how many inline comments were snapshotted, and how many (if
  any) were found orphaned by the markdown push and reconciled as footer comments — or that this step
  was skipped and why (e.g. missing API token).
- Notes push (steps 4-5): files merged (noting which were integrated into an existing section vs
  appended under "Sync updates," and for `.mmd` files whether the diagram was rendered and
  attached as a PNG or only had its labels extracted as a fallback — and if only labels, why: the
  API token was missing, or PNG rendering was otherwise unavailable), duplicate `.gdoc`
  files trashed, unreadable files skipped, or "sin archivos nuevos" if none.
- Final mirror refresh (step 6): whether it fired and updated the mirror again after notes push.
