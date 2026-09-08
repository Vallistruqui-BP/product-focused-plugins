# Diagram Design Principles

A playbook for turning messy input (notes, requirements docs, transcripts) into a single clean,
correct flowchart. This file covers *how to think*, format-agnostically — `mermaid-syntax.md`
covers the Mermaid mechanics for the source-of-truth `.mmd` file, and `drawio-xml-syntax.md` covers
the mxGraph XML mechanics for generating the synced `.drawio` copy.

---

## 1. Standard Flowchart Symbols → Shapes

These meanings come from the classic flowcharting vocabulary (ANSI X3.5 / ISO 5807, the standard
still cited by process-mapping guides today) and from established BA/process-mapping practice.
Use the *right* shape for the *right* kind of node — mixing them up is one of the fastest ways to
make a diagram unreadable. The same meaning must map to the same shape in **both** the `.mmd` and
`.drawio` files — this table is the shared vocabulary that keeps them in sync (see
`mermaid-syntax.md` for the full Mermaid-side table with syntax).

| Symbol meaning | What it represents | draw.io shape | Mermaid shape |
|---|---|---|---|
| Terminator (start/end) | The single entry point or one of possibly several exit points of the process | Ellipse/stadium — `ellipse;whiteSpace=wrap;html=1;` | Stadium — `id([Text])` |
| Process / action step | One atomic action performed by an actor or system | Rectangle — `rounded=0;whiteSpace=wrap;html=1;` | Rectangle — `id[Text]` |
| Decision | A branch point where the flow splits based on a yes/no or multi-way condition | Diamond (rhombus) — `rhombus;whiteSpace=wrap;html=1;` | Diamond — `id{Text}` |
| Input/Output (data) | Data entering or leaving the process (a form submitted, a report generated) — not an action, a *data* event | Parallelogram — `shape=parallelogram;whiteSpace=wrap;html=1;` | Parallelogram — `id[/Text/]` |
| Predefined process / subroutine | A step that is itself a whole other documented process (e.g., "Run KYC check" that has its own flowchart) | Predefined process (double-border rectangle) — `shape=process;whiteSpace=wrap;html=1;` | Subroutine — `id[[Text]]` |
| Connector (on-page or off-page) | A jump point used to avoid a long crossing line, or to link to another page/diagram | Small circle (on-page) or a linked page within the same file (off-page) — `ellipse;whiteSpace=wrap;html=1;` sized small, or a second `<diagram>` element in the same `<mxfile>` | Circle — `id((Text))`; off-page link becomes a separate `.mmd` file (Mermaid has no multi-page equivalent) |
| Database / stored data | A step that reads or writes persistent data | Cylinder — `shape=cylinder3;whiteSpace=wrap;html=1;` | Cylinder — `id[(Text)]` |

**Rules of thumb:**
- If a node describes something *someone does*, it's a rectangle.
- If a node describes something *that must be decided*, it's a diamond — and only a diamond.
  Never phrase a decision as a rectangle with an implied branch, and never let a rectangle have
  two outgoing arrows without a diamond justifying the split.
- If a node describes *data appearing or leaving* (a document, a form, a message) rather than an
  action being performed on it, prefer the parallelogram — but don't overuse it; most business
  flowcharts can stay simple with just terminator/process/decision and still be fully correct.
- Reach for the subroutine shape when a step is genuinely "and then a whole separate documented
  procedure happens here" — it signals "there's more detail elsewhere," not "this step is
  important."
- Use a connector/off-page link only to solve a genuine layout problem (a line that would
  otherwise cross half the diagram, or a diagram that must be split — see §3). Don't introduce
  connectors as a substitute for simplifying the layout.

---

## 2. Extracting Logical Structure from Unstructured Input

Work in this order. Don't try to draw the diagram while you're still parsing the text — separate
"understand the process" from "lay out the diagram."

### Step 1 — First pass: harvest raw events
Read the whole input once. Pull out every verb phrase that describes something happening:
actions, decisions, data movements, waits, handoffs. Don't organize yet — just list them roughly
in the order mentioned. Keep the source wording nearby; you'll need it to check fidelity later.

### Step 2 — Identify actors/roles
Scan the harvested list and tag each item with *who* does it (a person, a role, a team, a system,
an external party). Common signals: subject of the sentence ("the manager reviews…"), passive
voice needing inference ("the request is approved" → by whom? ask or infer from context), or an
explicit system name ("the CRM sends an email").
- If there are 2+ distinct actors performing meaningfully different steps, this is a candidate for
  swimlane-style grouping (a `swimlane`-styled pool/lane container per actor — see
  `drawio-xml-syntax.md`).
- If there's only one actor, or the actors are trivial/interchangeable, skip swimlanes — they add
  visual overhead for no benefit on a single-actor process.

### Step 3 — Classify each harvested item
For every item, decide which bucket it belongs to:
- **Atomic action/step** — a single thing done, not further decomposed in the source. → rectangle.
- **Decision point** — the source describes a condition, a check, an "if", a fork in outcome
  ("if approved… otherwise…", "depending on…", "checks whether…"). → diamond. Extract *every*
  branch mentioned, even if only implied.
- **Parallel branch** — the source says things happen at the same time, independently, or
  "meanwhile" / "in parallel" / "simultaneously". These need concurrent paths that later
  rejoin (a fork node and a join node), not a single sequential chain forced into order.
- **Loop / repeat** — the source describes retrying, looping back, "until", "repeat until",
  "if rejected, send back to step X". These need an edge that points backward to an earlier node,
  usually out of a decision.
- **Input/output data event** — a document, message, or record appears/leaves without an actor
  actively "doing" something to it in this telling.

When in doubt between "atomic step" and "this is really two steps," prefer splitting only if the
source implies a decision or handoff between them; otherwise keep it as one node — see §3 on
abstraction-level consistency.

### Step 4 — Identify the start state and all end states
- There must be **exactly one** start terminator. If the input describes multiple possible
  triggers ("this can be kicked off by a customer request or an internal audit"), either:
  (a) merge them into one start node with the trigger as a label/condition, or
  (b) model them as parallel entry arrows into a single first shared step, whichever matches the
  source.
- There can be **multiple** end terminators — one per distinct outcome (Approved, Rejected,
  Cancelled, Escalated, etc.). Walk every decision branch and every described outcome and confirm
  each one terminates somewhere. A branch that just trails off in the source is a gap — see
  Step 5.
- Every terminal state mentioned in the text (success, failure, timeout, cancellation, escalation)
  should get its own end node, clearly labeled with the outcome, not a generic "End" repeated four
  times.

### Step 5 — Handle ambiguous or contradictory input
Use this test: **can you make a reasonable, low-risk assumption that a domain-literate reader
would find obviously correct, or does the choice materially change the meaning of the process?**

- **Make a reasonable assumption and flag it** when:
  - The gap is cosmetic (e.g., unclear if "the manager" and "the supervisor" are the same role —
    assume they're the same unless context suggests otherwise) — note the assumption.
  - A common-sense default exists (e.g., a rejected request implies a "notify requester" step even
    if unstated) — add it and flag it as inferred, don't silently invent it.
  - Only one interpretation makes the process actually work (e.g., a decision with only one
    labeled branch obviously needs a second — infer the natural "otherwise" outcome).
- **Ask a clarifying question** when:
  - Two parts of the input genuinely contradict each other (e.g., one paragraph says approval
    needs two signatures, another says one is enough).
  - A decision's branches lead somewhere materially different depending on interpretation (e.g.,
    unclear whether "escalate" means loop back to step 2 or terminate the process).
  - The actor responsible for a critical step (approval, payment, data deletion) is unclear or
    contested.
  - Missing information would make the diagram misleading rather than merely incomplete (silently
    guessing would produce a "confidently wrong" diagram).
- Always mark assumptions explicitly (e.g., "(assumed)" in your working notes, and a short
  "Assumptions" note when you present the diagram) rather than blending guesses invisibly into the
  authoritative-looking output.

### Step 6 — Deduplicate near-identical steps
Unstructured input — especially transcripts — repeats itself: the same step gets described twice
in different words, or referenced again later as a callback ("like we said before, they check the
ID again").
- Normalize each candidate step to its core verb + object (e.g., "verify the customer's identity,"
  "check the customer's ID," "confirm who the customer is" → all become one node:
  *Verify customer identity*).
- Two mentions describe the same node if they have the same actor, same action, and same position
  in causal order relative to neighboring steps. If the actor or the causal position differs,
  they're probably two distinct occurrences of a similar step (e.g., ID is checked once at intake
  and again at pickup) — keep both, but consider distinguishing labels ("Verify ID (intake)" /
  "Verify ID (pickup)").
- When a later mention is really a loop-back reference to an earlier step ("if it fails, go back
  and check the ID again"), don't create a duplicate node — draw an edge back to the existing
  node instead.
- Merge only after you've done the classification pass (Step 3) — dedup before that risks
  collapsing a decision into a step or vice versa.

---

## 3. Layout & Legibility Rules

### Direction: top-down vs left-right
- **Top-down** for processes that are naturally sequential and read like a narrative, especially
  ones with many decision branches — vertical space handles branching fan-out better.
- **Left-right** for processes that are short, pipeline-like, or where the actors are best shown as
  columns/stages read in reading order (e.g., a lane-per-department diagram often reads better
  left-right, with lanes as horizontal bands).
- Pick based on the *shape* the diagram naturally wants: a diagram that's "wide" (few steps, many
  parallel branches side by side) fits left-right; a diagram that's "tall" (long sequential chain
  with occasional branches) fits top-down. Don't force one direction out of habit — check which one
  produces fewer crossings once you've sketched the structure.

### Minimizing crossing edges
- Order sibling branches of a decision so the more common/expected path is drawn straighter
  (usually continuing downward/rightward) and the exceptional path branches off to the side —
  don't make both paths equally serpentine.
- Keep actor lanes in a stable left-to-right or top-to-bottom order that matches the
  real-world handoff sequence; reordering lanes to "fix" one crossing often creates three more
  elsewhere.
- Route loop-back edges (retry/rework loops) around the outside of the main flow rather than
  through the middle — a loop-back arrow that cuts across unrelated nodes is a common source of
  visual spaghetti.
- If two unrelated parts of the diagram need an edge between them and it would cross everything in
  between, prefer a connector/reference instead of forcing a direct line (see §1).

### When to split or collapse
A diagram has gotten too dense when any of these is true:
- More than roughly 15–20 nodes in a single view (rule of thumb, not a hard limit — legibility
  matters more than the count).
- A decision node has so many downstream nodes that the diagram becomes wider than it is tall (or
  vice versa, breaking the direction choice above).
- You find yourself needing 3+ connector jumps to avoid crossings — that's a sign the diagram
  wants to be two diagrams.
- A "predefined process" step (§1) has enough internal detail mentioned in the source that
  drawing it inline would double the node count — collapse it into a subroutine node and (if the
  source has enough detail) produce it as its own linked sub-diagram instead of inlining it.

**How to split:** identify the natural seam — usually a handoff between actors, a predefined
subprocess, or a point where the process genuinely forks into independent tracks that don't need
to be seen together. Replace the seam with a single subroutine node in the parent diagram and
produce the detail as a separate diagram. **How to collapse instead of splitting:** if the extra
detail is low-value (e.g., "log the action," "update the ticket status"), fold it into the
label of an adjacent step rather than giving it its own node, or group a tight cluster of trivial
steps into one lane labeled with the phase name (e.g., "Intake" containing three small steps) so
the top-level view stays scannable even if the detail is preserved.

### Node phrasing
- **Action nodes: verb-first, imperative, concrete.** "Verify customer identity," not "Customer
  identity verification" or "The identity of the customer is verified." Keep it to one action —
  if a label needs "and" to join two actions, it's probably two nodes.
- **Decision nodes: phrase as a real question**, ending in a question mark, using the actual
  condition from the source. "Is the invoice over $10,000?" not "Check invoice amount" (that's an
  action, not a decision) and not a vague "Amount OK?" if the source gives you the real threshold.
- **Branch labels: use the real answer, not a placeholder.** Prefer "Yes"/"No" only when the
  decision is a genuine binary question. For multi-way or condition-based branches, label the edge
  with the actual condition text ("> $10,000", "Rejected", "Timeout after 48h") rather than
  generic labels like "Option A" / "Option B" — a reader should be able to understand the branch
  logic from the edge labels alone, without re-reading the diamond.
- Keep verb tense and voice consistent across the whole diagram (all imperative present tense is
  standard: "Send email," "Check balance," "Notify manager" — not a mix of "Sending email" /
  "Manager is notified" / "Notify manager").
- Keep terminology consistent with the source's own vocabulary for actors, systems, and document
  names — don't silently rename "the ticket" to "the request" partway through.

---

## 4. Common Failure Modes to Avoid

- **Spaghetti density.** Too many nodes, too many crossing lines, no clear left-to-right/top-to-
  bottom reading order. Fix by applying §3 (split/collapse) before finalizing, not after.
- **Decision nodes with unclear or missing branches.** Every diamond must have every outcome
  mentioned in (or reasonably inferable from) the source represented as a labeled outgoing edge.
  A diamond with only one exit isn't a decision — either the second branch was dropped by mistake,
  or the node shouldn't be a diamond. Audit every diamond by asking "what happens if the answer
  is the opposite of the obvious case?"
- **Missing error/exception paths.** Business processes described casually almost always omit the
  unhappy path (declined payment, failed validation, timeout, system error, customer cancels).
  Actively check the source for hints of these ("if it doesn't work," "in case of," "unless") and,
  where the source is silent but an exception is clearly possible for the domain, flag it as an
  assumption rather than silently omitting it or silently inventing a specific handling procedure
  the source never described.
- **Orphan or unreachable nodes.** After drawing the diagram, trace every node from the single
  start terminator forward — every node must be reachable, and (excluding intentional infinite-
  loop processes) every path must reach a terminator. A node with no incoming edge (other than
  Start) or no outgoing edge (other than an End) is either a leftover from editing or a sign a
  connection was missed during extraction (§2).
- **Inconsistent abstraction level.** Don't mix "Process the order" (high-level) with "Click
  Submit button" (keystroke-level) in the same diagram. Decide the altitude up front — typically
  "one node per meaningful business action a person would describe to a colleague," not
  system-click granularity unless the user explicitly asked for a UI-level walkthrough — and hold
  every node to that same altitude. If the source naturally contains both levels of detail, keep
  the high-level diagram as the primary deliverable and push the fine-grained steps into a linked
  subroutine diagram (§3) rather than flattening everything into one view.
- **Silent invention.** Don't add steps, actors, or outcomes that aren't in the source and aren't
  a reasonable, flagged inference (§2, Step 5). A flowchart that looks authoritative but contains
  invented steps is worse than one that visibly says "assumption: …".
- **Generic/placeholder labels.** "Process," "Handle request," "Check," "Yes/No" on a non-binary
  decision — any label vague enough that it could apply to half the other nodes in the diagram is
  a sign the extraction (§2) wasn't specific enough. Go back to the source text and pull the
  concrete verb and object.
