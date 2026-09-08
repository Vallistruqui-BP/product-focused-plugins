---
name: flowchart-builder
description: Convert requirements, notes, transcripts, or a rough description of a process into a polished Mermaid (`.mmd`) flowchart with a synced draw.io (`.drawio`) copy for free-hand editing, then keep both in sync through chat while the user visually inspects, zooms, and drag-edits the drawio copy directly in VSCode. Use when the user asks to build/create a flowchart or diagram, wants to visualize a process/decision sequence, or hands over unstructured notes and asks for them to become a flow.
when_to_use: Triggered when the user mentions "flowchart", "diagram", "process flow", "visualize this", or provides raw notes/requirements/a transcript and asks for a diagram to be generated from them.
allowed-tools: Read Write Edit Bash Glob Grep AskUserQuestion
---

# Flowchart Builder

Turns messy input into a correct, validated, themed flowchart, kept in **two synced files**:

- **`.mmd` (Mermaid) — the source of truth.** Plain text, easy for Claude to generate and edit
  directly from chat, and the format that gets rendered to PNG for Confluence embedding (see the
  confluence-sync plugins' own docs — this skill doesn't do that rendering itself).
- **`.drawio` — a generated copy for free-hand visual editing.** The user gets native zoom/pan and
  drag-edit directly in VSCode; Claude never treats this as the source, only as a rendering of the
  `.mmd` file's structure that the user is free to reposition, and occasionally re-shape, by hand.

Reference files hold the deep detail — read them on demand, don't try to hold everything in this
file.

- [`references/diagram-design-principles.md`](references/diagram-design-principles.md) — how to
  extract logical structure (actors, steps, decisions, loops, start/end) from unstructured input,
  and layout/legibility rules. Format-agnostic — applies to both files. **Read this before drafting
  any diagram from raw notes.**
- [`references/mermaid-syntax.md`](references/mermaid-syntax.md) — Mermaid flowchart mechanics:
  file skeleton, node shapes, edges, subgraphs, theming, gotchas. **Read this before writing any
  `.mmd` file you're not 100% sure of** — this is the primary format now, read it first.
- [`references/drawio-xml-syntax.md`](references/drawio-xml-syntax.md) — the mxGraph XML format for
  generating the `.drawio` copy: file skeleton, shapes, edges, styling, layout conventions,
  gotchas. **Read this before writing or re-reading any `.drawio` XML you're not 100% sure of.**
- [`references/themes.md`](references/themes.md) — 7 curated named color themes (Default, Nord,
  Dracula, Tokyo Night, Catppuccin Mocha, GitHub Dark, Solarized Light), given as
  `fillColor`/`strokeColor`/`fontColor` triples for drawio and the equivalent Mermaid
  `classDef`/`linkStyle` syntax for the same colors.
- [`references/validation-checklist.md`](references/validation-checklist.md) — pre-flight
  self-check to run before presenting any diagram as finished, including the `.mmd`/`.drawio`
  consistency check. **Always run this before finalizing.**
- [`references/vscode-drawio-setup.md`](references/vscode-drawio-setup.md) — one-time VSCode
  extension setup, usage notes, and troubleshooting for the `.drawio` copy. **Read only when the
  user reports a rendering/editor problem**, not during normal diagram creation.
- [`examples/basic-decision.mmd`](examples/basic-decision.mmd) and
  [`examples/basic-decision.drawio`](examples/basic-decision.drawio) — the same minimal diagram in
  both formats, default theme applied, showing what a synced pair looks like.

## Workflow

1. **Gather input.** Take whatever the user gives you — notes, a requirements doc, a transcript,
   or a verbal description in chat. If it's ambiguous or contradictory in a way that would change
   the diagram's shape (not just cosmetic wording), ask one targeted clarifying question rather
   than guessing. If it's ambiguous in a low-stakes way, make the reasonable assumption and say
   so in your reply rather than blocking on a question.

2. **Extract the logical structure** before writing either file. Follow the method in
   `diagram-design-principles.md`: identify actors, atomic steps vs. decisions vs. parallel
   branches vs. loops, the single start state, and all end states. Do this as a mental/scratch
   step — don't show the user a raw outline unless they ask for one; go straight to the diagrams.

3. **Pick shapes and layout** per the shared vocabulary in `diagram-design-principles.md` §1
   (stadiums for start/end, diamonds for decisions, rectangles for process steps, parallelograms
   for input/output). Use subgraphs/swimlanes for distinct actors or phases instead of flattening
   everything into one pool of shapes. Lay out top-to-bottom for depth-heavy flows, left-to-right
   for wide sequential ones.

4. **Apply a theme** from `themes.md` to every shape and edge in both files. Ask the user once per
   session (or reuse whatever theme they've already picked/used) rather than asking on every
   diagram. Default to "Default" if they've expressed no preference.

5. **Write the `.mmd` file first** per `mermaid-syntax.md` — this is the source of truth. One
   flowchart per `.mmd` file (Mermaid has no multi-page equivalent to drawio's multiple `<diagram>`
   elements — a diagram needing a split per `diagram-design-principles.md` §3 becomes multiple
   `.mmd` files). Use a descriptive filename (`checkout-flow.mmd`, not `flowchart1.mmd`).

6. **Generate the matching `.drawio` copy** from the same logical structure, same base filename
   (`checkout-flow.drawio`), per `drawio-xml-syntax.md`. This is a rendering of the `.mmd`
   structure, not an independent diagram — same nodes, same edges, same shape-per-meaning mapping
   (see the table in `mermaid-syntax.md`), same theme.

7. **Validate before presenting.** Run the full `validation-checklist.md` pass on both files —
   including that they describe the same graph — and fix routine issues (unescaped characters,
   colliding ids, dangling edges) silently. Only mention a fix in your reply if it required a
   judgment call that changes meaning.

8. **Tell the user how to view each file** only the first time in a session: the `.drawio` file
   opens directly as a visual editor in VSCode (native zoom/pan, drag-edit); the `.mmd` file is
   plain text they can also preview with any Mermaid-aware viewer. Don't repeat this every turn.

9. **Iterate — two directions:**
   - **Change requested in chat** (new step, different condition, restructure): edit the `.mmd`
     file first (don't regenerate from scratch unless the change is structural), then re-generate
     or hand-edit the `.drawio` copy to match. Briefly state what changed.
   - **User says they edited the `.drawio` copy by hand** (moved shapes, added/removed/relabeled
     nodes, redrew a connection) and wants it synced back: **read the current `.drawio` XML**,
     re-derive its logical structure (nodes, edges, labels, shape-per-meaning per the table in
     `mermaid-syntax.md`) — don't assume your last-known structure still matches, the user may have
     changed more than they mentioned — and rewrite the `.mmd` file to match that structure. Note
     plainly that only structure/labels sync back, not exact positions (Mermaid auto-lays-out; it
     has no `.drawio`-style manual `x`/`y` geometry to carry over).
   - If unsure which direction a request means (e.g. "update the flowchart" with no file named),
     ask — editing the wrong file as source would silently overwrite the other's real content.

10. **If the user reports a rendering/editor problem** with the `.drawio` copy, consult
    `vscode-drawio-setup.md` first.

## Converting an existing `.drawio`-only file to Mermaid

Use this whenever a `.drawio` file already exists with **no `.mmd` sibling** — a diagram built
before this skill supported Mermaid, one authored by a different tool or session, or any legacy
file someone hands you and asks to "convert to Mermaid." This is the general-purpose entry point
for that operation — don't wait for the user to mention they hand-edited a drawio copy (step 9's
second bullet) before doing this; if a `.drawio` file has no matching `.mmd`, this is the workflow.

1. **Read the full `.drawio` XML.** Every `<mxCell>`/`<object>` `value="..."` attribute is a node
   or edge's visible text — **decode its HTML entities before writing it into the `.mmd` file**
   (`&#191;` → `¿`, `&#243;` → `ó`, `&#8212;` → `—`, etc. — draw.io escapes non-ASCII characters as
   numeric references; skipping this step produces garbled accented text, a real failure mode hit
   converting real diagrams, not a hypothetical).
2. **One `<diagram>` page → one `.mmd` file.** Mermaid has no multi-page equivalent (see
   `mermaid-syntax.md`'s last gotcha) — a multi-page `.drawio` file becomes one `.mmd` file per
   page. Name each `<basename>-<page-slug>.mmd`, slugifying the page's own `name` attribute (e.g.
   page "B. Notificación al punto" → `<basename>-b-notificacion-al-punto.mmd`), not a numeric
   index, so the filename stays meaningful without opening the file.
3. **Map each vertex's `style` to the matching Mermaid shape** via the table in `mermaid-syntax.md`
   (`rhombus`→`{}`, `ellipse`→`([])`, `hexagon`→`{{}}`, `shape=process`→`[[ ]]`, else→`[]`) and each
   edge's `source`/`target`/`value` to `a --> b` / `a -->|"label"| b`. If the source diagram used a
   shape for a meaning that doesn't match this skill's own conventions (it may predate them),
   preserve *that* diagram's actual shape-per-meaning choices rather than silently reassigning
   shapes to match this skill's table — converting must not change what a shape means.
4. **Carry over the color theme**, if any (`fillColor`/`strokeColor`/`fontColor` triples in the
   `style` string) — match it against `themes.md` if it corresponds to one of the curated themes,
   or emit `classDef`s with the literal hex values directly if it doesn't match a named theme
   exactly. Don't force-fit to the nearest named theme and silently change colors.
5. **Preserve cross-page link nodes as-is.** A multi-page file that used a node purely to mark
   where logic continues onto another page (e.g. "Continúa: Módulo B", "Viene de: Módulo A") should
   keep that same node, verbatim, in the corresponding `.mmd` file — don't try to merge the pages
   back into one file or resolve the cross-reference away.
6. **Run the full `validation-checklist.md` pass** against every new `.mmd` file before presenting
   them as done, same as for a freshly-authored diagram.
7. **Report which file(s) were written**, and if the source `.drawio` had N pages, say so plainly
   (e.g. "5 pages → 5 `.mmd` files, one per module") rather than leaving the file count implicit.

The resulting `.mmd` file(s) are then usable by the Confluence-embedding pipeline in
`confluence-live-sync`/`pickit-sync-kickoff`, which expects Mermaid as its primary rendering
source for PNG export and upload.

## Output conventions

- File naming: `kebab-case-description.mmd` / `kebab-case-description.drawio` (matching base name)
  in the directory the user is working in (or a `flowcharts/` subfolder if the project has many
  diagrams — ask once, then stay consistent).
- Prefer real condition text on decision branches (`order total > $50`) over generic `Yes`/`No`
  when the source material states the actual condition.
- Never emit PlantUML output for this skill's core flowchart use case. If a user specifically asks
  for PlantUML text output for another purpose, that's a different request; don't default to it for
  this workflow.
- This skill does not export to PNG or touch Confluence — see the `confluence-live-sync` and
  `pickit-sync-kickoff` plugins for how the `.mmd` source gets rendered and embedded elsewhere.
