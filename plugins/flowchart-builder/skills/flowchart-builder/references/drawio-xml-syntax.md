# draw.io / diagrams.net XML (mxGraph) Reference

`.drawio` files are XML (the "mxGraph" format) — generated as a synced copy of the `.mmd` source
(see `mermaid-syntax.md` and the parent `SKILL.md` workflow), not written by hand from scratch.
Unlike the `.mmd` file, this one **is** directly the diagram's native visual data — VSCode's
draw.io extension opens it as a real visual editor with native zoom/pan and drag-to-edit, not a
text-to-image renderer, which is exactly why it exists alongside the Mermaid source: free-hand
visual editing. Generate valid XML directly; there is no separate "compile" step.

## File skeleton

Every `.drawio` file follows this exact structure — one `<mxfile>` root, one `<diagram>` per page,
one `<mxGraphModel>`, and a `<root>` containing two mandatory boilerplate cells (`id="0"` and
`id="1"`) followed by your actual shapes and edges:

```xml
<mxfile host="app.diagrams.net">
  <diagram name="Page-1" id="page1">
    <mxGraphModel dx="800" dy="600" grid="1" gridSize="10" guides="1" tooltips="1" connect="1"
                  arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100"
                  math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- your vertices and edges go here, all with parent="1" -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

## Vertices (nodes)

Every shape is an `mxCell` with `vertex="1"`, a unique `id`, a `value` (the label text), a `style`
string, `parent="1"`, and a child `<mxGeometry>` giving its position/size:

```xml
<mxCell id="step1" value="Process the order" style="rounded=0;whiteSpace=wrap;html=1;"
        vertex="1" parent="1">
  <mxGeometry x="360" y="40" width="160" height="60" as="geometry" />
</mxCell>
```

### Standard flowchart shapes → `style` value

| Symbol | Meaning | `style` |
|---|---|---|
| Rectangle | process/action step | `rounded=0;whiteSpace=wrap;html=1;` |
| Rounded rectangle | process step (softer look) | `rounded=1;whiteSpace=wrap;html=1;` |
| Ellipse/stadium | start/end (terminator) | `ellipse;whiteSpace=wrap;html=1;` |
| Rhombus | decision | `rhombus;whiteSpace=wrap;html=1;` |
| Parallelogram | input/output | `shape=parallelogram;whiteSpace=wrap;html=1;` |
| Predefined process/subroutine | reusable subprocess | `shape=process;whiteSpace=wrap;html=1;` |
| Cylinder | database/data store | `shape=cylinder3;whiteSpace=wrap;html=1;` |
| Hexagon | preparation step | `shape=hexagon;perimeter=hexagonPerimeter2;whiteSpace=wrap;html=1;` |
| Document | report/document output | `shape=document;whiteSpace=wrap;html=1;` |

### Color/font styling (append to any `style` string)

```
fillColor=#ffffff;strokeColor=#2563eb;fontColor=#0f172a;
```

- `fillColor` — shape fill
- `strokeColor` — border color
- `fontColor` — label text color
- `strokeWidth` — border thickness (default 1)
- `fontSize=14;fontStyle=1;` — `fontStyle=1` is bold, `=2` italic, `=3` bold+italic
- `dashed=1;` — dashed border (useful for optional/future steps)

Always set all three of `fillColor`/`strokeColor`/`fontColor` together from one of the palettes in
`themes.md` — never leave a shape on draw.io's default light-gray/black styling if the rest of the
diagram uses a theme, the mismatch reads as a mistake.

## Edges (connectors)

An edge is an `mxCell` with `edge="1"`, referencing the vertex `id`s via `source`/`target`:

```xml
<mxCell id="e1" value="Yes" style="edgeStyle=orthogonalEdgeStyle;html=1;strokeColor=#334155;strokeWidth=2;fontColor=#0f172a;exitX=0;exitY=0.5;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;"
        edge="1" parent="1" source="decision1" target="step2">
  <mxGeometry relative="1" as="geometry" />
</mxCell>
```

- `value` on an edge is the edge label (e.g. `Yes` / `No` on a decision branch, or the actual
  condition text — prefer real condition text when the source material states it).
- `edgeStyle=orthogonalEdgeStyle;` gives clean right-angle routing (default recommendation for
  flowcharts). `edgeStyle=none;` gives a straight line. Add `rounded=1;` to an orthogonal edge for
  rounded corners at bends.
- `startArrow=none;` / `endArrow=none;` to suppress arrowheads if needed; default is a filled
  arrow at the target end, which is correct for almost all flowchart edges.
- **Always set explicit `exitX/exitY/entryX/entryY`** rather than leaving draw.io to pick a
  floating connection point automatically. These are fractions (0 to 1) of the shape's bounding
  box: `0.5,0` = top-center, `0.5,1` = bottom-center, `0,0.5` = left-center, `1,0.5` = right-center.
  Without them, draw.io auto-picks a point on the shape's perimeter — fine for a single edge, but
  once two or more edges enter or leave the same shape (a decision's Yes/No branches, or two
  branches converging back into one node) the auto-picked points can land close together or
  overlap, making it genuinely hard to tell which arrow belongs to which branch. Assign each edge
  into/out of a shared shape a *different* side or offset instead (e.g. the "Yes" branch exits the
  decision's left side, "No" exits the right side; two converging edges enter a shape's left and
  right sides rather than both landing top-center).
- Give edges a `strokeColor` from a **different hue family** than the shapes' own `strokeColor`
  (see `themes.md`) and `strokeWidth=2` (vs. the shape border's default `strokeWidth=1`) — if a
  connector's color is just a lighter/darker tint of the shape border color, or the same thin
  width, it's easy to lose the line where it runs close to or crosses near another shape.

## Geometry / layout conventions

- Coordinate origin is top-left; `x`/`y` is the shape's top-left corner, `width`/`height` its size.
- Standard shape sizing: ~120-160 width, 60-80 height for rectangles/ellipses; rhombus (decision)
  needs more room — ~140-180 width, 80-100 height, since diamond shapes waste corner space.
- Vertical spacing: leave ~40-60px between a shape's bottom edge and the next shape's top edge so
  edge labels have room to sit without overlapping.
- For a `TD`-style flow (top-to-bottom), increment `y` by roughly `height + 80` per row and keep
  `x` aligned per branch column. For branches (e.g. Yes/No), offset `x` left/right symmetrically
  from the decision node's center, then converge back to a shared `x` before the next merge point.
- You do not need to hand-place every coordinate with extreme precision — the user can drag shapes
  after the fact in the visual editor. Aim for "readable and non-overlapping," not pixel-perfect.

## Grouping actors/phases (swimlane-equivalent)

For actor/phase grouping (the drawio equivalent of a Mermaid subgraph), use a pool/lane container:

```xml
<mxCell id="lane1" value="Customer" style="swimlane;horizontal=0;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#2563eb;fontColor=#0f172a;"
        vertex="1" parent="1">
  <mxGeometry x="40" y="40" width="800" height="200" as="geometry" />
</mxCell>
```

Shapes placed inside a lane need `parent="lane1"` instead of `parent="1"`, and their `x`/`y`
become relative to the lane's own coordinate space (starting near `0,0` inside it, not the page's
absolute coordinates).

## Common gotchas that break the file or corrupt the diagram

| Gotcha | Symptom | Fix |
|---|---|---|
| Duplicate `id` values | one shape silently overwrites another, or edges connect to the wrong shape | every `mxCell id` must be unique across the whole file |
| Edge `source`/`target` referencing a non-existent id | edge doesn't render, or draw.io reports a corrupt-file error | double check every edge's `source`/`target` matches an actual vertex `id` exactly |
| Missing `parent="1"` (or the correct lane id) | shape doesn't appear, or appears detached from the intended container | every vertex/edge needs the right `parent` |
| Unescaped XML special characters in `value` (`&`, `<`, `>`, `"`) | malformed XML, file fails to open entirely | escape as `&amp;`, `&lt;`, `&gt;`, `&quot;` |
| Forgetting the two boilerplate cells (`id="0"`, `id="1"`) | file fails to open / draw.io shows an empty or broken canvas | always include both before your content cells |
| Overlapping geometry (two shapes with the same/overlapping `x`,`y`) | diagram opens but looks broken/stacked | space shapes per the layout conventions above |
