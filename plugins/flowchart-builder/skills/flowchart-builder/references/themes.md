# Theming Reference (Mermaid + draw.io)

Ask the user which theme they want, or default to "Default" if they haven't expressed a
preference. Keep the choice consistent across all diagrams in a session unless asked to change it.

Each theme below gives three values to append to every shape's `style` attribute
(`fillColor`, `strokeColor`, `fontColor`), plus an edge `strokeColor`. **The VSCode draw.io editor
always renders on a plain white/light page — there is no dark-canvas mode.** A dark-toned shape
palette (near-black `fillColor`) on that white page doesn't read as "themed," it reads as a wall of
black boxes with poor legibility. Only pick a dark-toned theme (#2 through #6 below) when the user
explicitly wants that look and understands it will sit on a white page in-editor (e.g. they're
exporting to a slide deck they'll set to a dark background themselves) — otherwise use **Default**
or **Solarized Light**, the two light-canvas-appropriate options.

Edge `strokeColor` in every theme below is deliberately a different hue family from the shape's own
`strokeColor`, not just a lighter/darker tint of it — if a connector and a shape border are close in
hue, a reader can't tell at a glance which lines are edges and which are shape outlines. Edges also
use `strokeWidth=2` (vs. the shape border's default `strokeWidth=1`) so arrows read clearly against
the fill colors around them.

---

## 1. Default

Light, high-contrast — white fill, near-black text, a strong blue border. The safe default: reads
correctly on the white canvas the VSCode editor actually renders, with no dark-canvas assumption.

```
fillColor=#ffffff;strokeColor=#2563eb;fontColor=#0f172a;
```
Edge color: `strokeColor=#334155;strokeWidth=2;` (dark slate — distinct from the shape's blue border)

---

## 2. Nord

Cool blue-gray "Arctic" palette — calm, muted, icy blue (Frost) accents.

```
fillColor=#434c5e;strokeColor=#88c0d0;fontColor=#eceff4;
```
Edge color: `strokeColor=#d08770;strokeWidth=2;` (Nord Aurora orange — distinct from the Frost blue border)

Source colors (nord0–nord15): `#2e3440`, `#3b4252`, `#434c5e`, `#4c566a` (Polar Night), `#eceff4`
(Snow Storm), `#88c0d0`, `#81a1c1` (Frost).

---

## 3. Dracula

Dark purple-gray base with vivid, high-saturation accents.

```
fillColor=#44475a;strokeColor=#bd93f9;fontColor=#f8f8f2;
```
Edge color: `strokeColor=#50fa7b;strokeWidth=2;` (Dracula green — distinct from the Purple border)

Source colors: Background `#282a36`, Selection `#44475a`, Foreground `#f8f8f2`, Purple `#bd93f9`,
Cyan `#8be9fd`.

---

## 4. Tokyo Night (Storm)

Deep navy-blue "night city" theme with electric blue/cyan accents.

```
fillColor=#24283b;strokeColor=#7aa2f7;fontColor=#a9b1d6;
```
Edge color: `strokeColor=#e0af68;strokeWidth=2;` (Tokyo Night amber — distinct from the blue border)

Source colors (Storm variant): bg `#24283b`, foreground `#a9b1d6`, blue `#7aa2f7`, cyan `#7dcfff`.

---

## 5. Catppuccin Mocha

Dark, low-glare pastel palette — muted lavender/mauve accents.

```
fillColor=#1e1e2e;strokeColor=#cba6f7;fontColor=#cdd6f4;
```
Edge color: `strokeColor=#a6e3a1;strokeWidth=2;` (Catppuccin green — distinct from the Mauve border)

Source colors (Mocha): Base `#1e1e2e`, Text `#cdd6f4`, Mauve `#cba6f7`, Blue `#89b4fa`.

---

## 6. GitHub Dark

GitHub's own dark UI theme — near-black fill, cool gray text, signature blue accent.

```
fillColor=#161b22;strokeColor=#58a6ff;fontColor=#c9d1d9;
```
Edge color: `strokeColor=#f0883e;strokeWidth=2;` (GitHub's own warning-orange — distinct from the accent blue border)

Source colors: canvas.subtle `#161b22`, fg.default `#c9d1d9`, accent.fg `#58a6ff`.

---

## 7. Solarized Light

The other light-canvas-appropriate option (alongside Default). Warm, low-contrast cream/paper tones.

```
fillColor=#eee8d5;strokeColor=#268bd2;fontColor=#586e75;
```
Edge color: `strokeColor=#cb4b16;strokeWidth=2;` (Solarized orange — distinct from the blue border)

Source colors (Ethan Schoonover's official Solarized spec): base2 `#eee8d5`, base01 `#586e75`,
blue `#268bd2`, cyan `#2aa198`.

---

## Applying a theme — draw.io copy

Append the three shape colors to every vertex's `style` string, and the edge color (including its
`strokeWidth=2`) to every edge's `style` string. See `drawio-xml-syntax.md` for the full
style-string syntax. Example applying "Default" to a process rectangle:

```xml
style="rounded=0;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#2563eb;fontColor=#0f172a;"
```

## Applying a theme — Mermaid source

Same three hex values, as a `classDef` (see `mermaid-syntax.md` for the full syntax). Example
applying "Default":

```mermaid
classDef default fill:#ffffff,stroke:#2563eb,color:#0f172a;
```

Edge color goes on `linkStyle`, e.g. for Default: `linkStyle 0,1,2 stroke:#334155,stroke-width:2px;`
(list every edge's index — see `mermaid-syntax.md`'s gotcha on this).

## Per-node-type accent variants

Apply these by default on top of the base theme so decision/success/error nodes are visually
distinct from plain process steps, not just distinguishable by shape — a reader scanning quickly
should be able to spot a decision or an error outcome by color alone. Use the set matching whether
the base theme is light or dark:

**For light themes (Default, Solarized Light):**
```
Decision:  fillColor=#fef3c7;strokeColor=#d97706;fontColor=#78350f;
Success:   fillColor=#dcfce7;strokeColor=#16a34a;fontColor=#14532d;
Error:     fillColor=#fee2e2;strokeColor=#dc2626;fontColor=#7f1d1d;
```

**For dark themes (Nord, Dracula, Tokyo Night, Catppuccin Mocha, GitHub Dark):**
```
Decision:  fillColor=#78350f;strokeColor=#fbbf24;fontColor=#fef3c7;
Success:   fillColor=#14532d;strokeColor=#4ade80;fontColor=#f0fdf4;
Error:     fillColor=#450a0a;strokeColor=#f87171;fontColor=#fef2f2;
```

Mermaid side: same hex values as `classDef`s (e.g. for a light theme:
`classDef decision fill:#fef3c7,stroke:#d97706,color:#78350f;`, then `class <nodeId> decision`),
applied per-node via `class` statements rather than inline styling — see `mermaid-syntax.md`.
