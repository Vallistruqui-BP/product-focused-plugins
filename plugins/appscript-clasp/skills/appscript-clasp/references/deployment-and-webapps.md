# Deployment and web apps

## Versions vs. deployments — don't conflate them

- A **version** is an immutable snapshot of the script's code (`clasp version "description"`).
  Creating one doesn't change what's live anywhere.
- A **deployment** points at a specific version and is what's actually invokable externally (a web
  app URL, an executable API, or an add-on). `clasp deploy` creates a new version implicitly if you
  don't pass `--versionNumber`, and either creates a new deployment or updates an existing one if
  you pass `--deploymentId`.

`clasp push` (step 4 of the main workflow) only updates the **development** copy — the one you see
when testing in the Apps Script editor with "Test deployments" or via `clasp run`. It does **not**
touch any live deployment. Nothing user-facing changes until `clasp deploy` runs. Don't deploy
automatically after a push — treat it as a distinct, user-requested release action.

## Listing and managing deployments

```
clasp deployments               # list existing deployments and their IDs
clasp deploy --description "..."          # new deployment (new version)
clasp deploy --deploymentId <id> --description "..."   # update an existing deployment in place
clasp undeploy <deploymentId>   # remove a deployment
```

Updating an existing deployment ID keeps its URL stable — prefer this over creating a new
deployment when the intent is "ship the latest code to the same web app URL", since a new
deployment gets a new URL/execution ID.

## Web apps (`doGet` / `doPost`)

```js
function doGet(e) {
  return ContentService.createTextOutput("hello");
}
```

Deployment settings for a web app (set via the Apps Script editor's deploy dialog — clasp itself
doesn't expose these as CLI flags):

- **Execute as**: "Me" (runs with the developer's permissions regardless of who calls it) or "User
  accessing the web app" (runs with the caller's own permissions). Get this right deliberately —
  "Me" means every caller's requests run with your access, including to any data the script
  touches.
- **Who has access**: "Only myself", "Anyone within [organization]" (domain-restricted/org-wide),
  or "Anyone" (public, unauthenticated). **Never default this to "Anyone" silently** — always have
  the user state the access level they want. Publishing a web app with a real capability (writes to
  a Sheet, sends email, calls an external API) as "Anyone" is a real, easy-to-make-by-accident
  security mistake.

**Tested and confirmed NOT to work (clasp 3.4.1, 2026-09):** adding a top-level `"webapp": {"access":
"DOMAIN", "executeAs": "USER_DEPLOYING"}` block to `appsscript.json` and running `clasp push` +
`clasp deploy` (even against an existing `--deploymentId`) does **not** apply the access level —
`clasp create`'s own printed tip ("configure `webApp` in appsscript.json and run
`clasp create-deployment`") is misleading for this version. The resulting `/exec` URL 404s
("Página no encontrada" / file-not-found style page, not an access-denied page) for every caller,
including the owner, until access is set manually. **There is currently no scripted way to set
Execute-as/Who-has-access — always send the user through the editor's manual deploy dialog**
(open the project at script.google.com → **Deploy → Manage deployments** → pencil/edit icon on the
existing deployment (or **New deployment**) → gear icon next to "Select type" → choose **Web app**
→ set **Execute as** and **Who has access** → **Deploy**).

**Domain-restricted URLs look different.** A deployment manually configured for "Anyone within
[organization]" gets a domain-scoped URL shaped
`https://script.google.com/a/macros/<domain>/s/<deploymentId>/exec` (note the `/a/macros/<domain>/`
segment) — not the generic `https://script.google.com/macros/s/<deploymentId>/exec` shape a
`--deploymentId`-only or "Anyone"/"Only myself" deployment gets. Don't be surprised if the URL
changes shape after setting domain access through the UI, and hand the user the URL they get back
from the deploy dialog rather than assuming the `clasp deploy` output URL still applies.

**Setting access for the first time via "New deployment" mints a new deployment ID**, separate
from whatever `clasp deploy` already created — confirmed by comparing IDs before/after in practice
(e.g. `AKfycbxWBnGR…` from `clasp deploy`, then `AKfycbxZYCv…` after manually configuring access
through **Deploy → New deployment** in the editor). Treat the *manually-created* deployment ID as
the real one going forward — that's the one with working access settings and the URL users should
get — and use `clasp deploy --deploymentId <that-id>` for later code updates so they land on the
same URL instead of creating yet another deployment.

**Confirmed: the access level sticks across later updates.** Once a deployment ID has had its
access level set manually (once), subsequent `clasp push` + `clasp deploy --deploymentId <id>`
cycles update the code and keep serving at the exact same URL with the exact same access level —
no repeat trip through the editor UI. Verified end-to-end: pushed new data, ran
`clasp deploy --deploymentId <manually-configured-id> --description "..."`, and the existing
domain-restricted URL immediately served the updated content. This is what makes a scheduled/
unattended refresh workflow viable — the manual UI step is genuinely one-time per deployment, not
per update.

## Executable APIs

Alternative to a web app: expose specific functions as a callable API (used by other Apps Script
projects or external OAuth clients). Requires `"executionApi": {"access": "..."}` in
`appsscript.json` (see `manifest-syntax.md`) and is invoked via the Apps Script Execution API, not
a plain HTTP URL like a web app.
