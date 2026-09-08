# VSCode draw.io Setup & Troubleshooting

## One-time setup

```
code --install-extension hediet.vscode-drawio
```

Fully restart VSCode after install (a window reload is not enough for a freshly installed
extension to activate reliably — close all windows and reopen).

That's it — no separate preview command, no theme-detection config, no rendering pipeline to
configure. Opening a `.drawio` file directly opens it as a native visual editor tab; the file
itself *is* the diagram, not source text that gets rendered separately.

## Using it

- **Open**: double-click the `.drawio` file, or open it like any other file — it opens as a full
  visual canvas, not a text editor.
- **Zoom**: mouse wheel, `Ctrl+Shift+H` (fit page), or the zoom controls in the bottom-right corner
  of the canvas. This is native to the editor, not dependent on VSCode's window zoom.
- **Pan**: click-drag on empty canvas space, or spacebar+drag.
- **Edit visually**: click a shape to select it, drag to move, drag a corner to resize, drag from
  a shape's edge to draw a new connector. This works directly in the editor — the user doesn't
  need Claude for purely visual repositioning.
- **Edit via chat**: when the user describes a *structural* change (add a step, change a decision
  branch, rename something), Claude edits the underlying XML directly (see
  `drawio-xml-syntax.md`) and saves — the open editor tab picks up the change automatically.

## Why the `.drawio` copy exists at all, given `.mmd` is the source of truth

Earlier attempts to get native zoom/drag-edit directly on a Mermaid file in this environment hit
persistent, unresolved issues: Mermaid preview (`bierner.markdown-mermaid`) worked but had no zoom;
zoom-focused Mermaid extensions (`vstirbu.vscode-mermaid-preview`, `EchEmLabs.markdown-mermaid-zoom`)
failed outright (wrong file type requirement, and a "no diagram type detected" parse failure
respectively); PlantUML (`jebbs.plantuml`, even with a fully portable local Java + jar, verified
working from the command line) never triggered inside VSCode at all — no output, no error,
nothing. `hediet.vscode-drawio` worked immediately with native zoom and real drag-to-edit. This is
exactly why the workflow keeps a generated `.drawio` copy alongside the `.mmd` source rather than
asking the user to zoom/drag-edit the Mermaid file directly — **don't try to give the user native
visual editing on the `.mmd` file itself** (e.g. via a Mermaid preview/zoom extension) without
them explicitly asking and accepting the demonstrated limitations above; the `.drawio` copy is the
one with a demonstrated track record of working for that purpose.

## If something doesn't work

- Confirm Workspace Trust is enabled for the folder (VSCode restricts some extension behavior in
  Restricted Mode) — Command Palette → "Manage Workspace Trust".
- Confirm a full restart happened after install, not just a window reload.
- Confirm only one `.drawio`-handling extension is installed (`code --list-extensions | grep -i drawio`).
- If the file opens as raw XML text instead of the visual editor, right-click the tab → "Reopen
  Editor With..." → select the draw.io editor explicitly.
