# Pre-Flight Validation Checklist

Run through this before presenting any generated `.mmd`/`.drawio` pair as finished — silently fix
anything you can, and only surface it to the user if a fix required a judgment call that changes
meaning (e.g. renaming a colliding node ID).

## `.mmd`/`.drawio` consistency (run this one first)

- [ ] Same set of nodes in both files (by meaning/label, not literal id) — no node present in one
      file and silently missing from the other.
- [ ] Same edges, same direction, same labels (`Yes`/`No`/real condition text) in both files.
- [ ] Same shape-per-meaning mapping in both (per the table in `diagram-design-principles.md` §1 /
      `mermaid-syntax.md`) — a decision must be a diamond/rhombus in both, not a rectangle in one.
- [ ] Same theme colors in both (the Mermaid `classDef`/`linkStyle` values match the drawio
      `fillColor`/`strokeColor`/`fontColor` values for the same theme, per `themes.md`).
- If this is a fresh diagram (not a sync-back from a hand-edited `.drawio`), this check is
  automatic by construction — you wrote both from the same structure. It matters most after a
  sync-back, where the `.drawio` file may have been hand-edited in ways not yet reflected in `.mmd`.

## Mermaid syntax sanity (`.mmd`)

- [ ] Every node `id` is unique within the file, plain identifier syntax (no spaces).
- [ ] Any label containing `(`, `)`, `[`, `]`, `{`, `}`, `|`, or `"` is wrapped in quotes
      (`id["Approve (level 2)"]`) — an unquoted one breaks shape-delimiter parsing.
- [ ] Every `linkStyle` index list is recounted against the file's actual edge order — a stale
      index silently styles the wrong edge (see `mermaid-syntax.md`'s gotcha on this).
- [ ] Exactly one `flowchart TD`/`flowchart LR` declaration; never the legacy `graph` alias.

## XML well-formedness (`.drawio`)

- [ ] Every opening tag has a matching closing tag (or is self-closed with `/>`).
- [ ] Any `&`, `<`, `>`, `"` inside a `value` attribute is escaped as `&amp;`, `&lt;`, `&gt;`,
      `&quot;` — an unescaped one breaks the whole file, not just that node.
- [ ] The two boilerplate cells (`<mxCell id="0" />` and `<mxCell id="1" parent="0" />`) are
      present before any content cells.

## Structural checks

- [ ] Every `mxCell id` is unique across the entire file — no two shapes or edges share an id.
- [ ] Every edge's `source` and `target` attribute matches an actual vertex `id` that exists in
      the file — a typo'd reference makes the edge silently vanish or connect wrong.
- [ ] Every shape has the correct `parent` (`"1"` for top-level, or the containing lane/group's id
      if nested) — a wrong parent makes a shape appear detached or in the wrong container.
- [ ] Every decision node (rhombus) has at least two outgoing edges, and their labels are
      mutually exclusive (not two edges both effectively meaning "yes").
- [ ] Exactly one start shape has no incoming edges (unless multiple entry points are genuinely
      intentional — confirm that's the case).
- [ ] Every path terminates at an end shape — no dangling node with no outgoing edge that isn't
      meant to be a terminator.

## Layout sanity

- [ ] No two shapes have overlapping or identical `x`/`y` geometry (per the spacing conventions in
      `drawio-xml-syntax.md`) — the user can nudge things visually afterward, but a first draft
      that's already unreadable defeats the point.
- [ ] Edge labels ("Yes"/"No" or real condition text) don't visually collide with a nearby shape —
      leave enough vertical/horizontal gap for the label to render clearly.

## Theming consistency (`.drawio`)

- [ ] Every shape's `style` includes the three theme colors (`fillColor`/`strokeColor`/
      `fontColor`) from the chosen theme in `themes.md` — no shape left on draw.io's default
      styling if the rest of the diagram is themed.
- [ ] Every edge's `style` includes the theme's edge `strokeColor`.

## Rendering sanity

- [ ] Mentally trace 2-3 paths through the diagram from start to an end state and confirm they
      match what the source input actually described — not just that the XML is valid.
- [ ] If the diagram has grown past ~15-20 shapes, reconsider whether it should be split into
      linked pages (multiple `<diagram>` elements in the same `<mxfile>`) or grouped into
      lanes, per `diagram-design-principles.md`'s layout rules.

## When something fails this checklist

Fix it directly and move on — don't ask the user to approve routine fixes like escaping a
character or de-duplicating an id. Only flag it in your reply if the fix changed the diagram's
meaning (e.g. two nodes turned out to be duplicates and got merged, or a decision branch had no
clear opposite and you had to infer one — say what you inferred).
