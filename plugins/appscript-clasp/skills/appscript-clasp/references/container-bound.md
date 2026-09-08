# Container-bound projects (Sheets / Docs / Forms / Slides)

A container-bound script lives attached to a specific Sheet/Doc/Form/Slides file, gets an implicit
reference to it (`SpreadsheetApp.getActiveSpreadsheet()` etc. work without extra setup), and can
add custom menus and simple triggers to that file.

## Binding to a NEW container

```
clasp create --type sheets --title "My Project"
```

`--type` is one of `sheets`, `docs`, `forms`, `slides` (or `standalone`/`webapp`/`api` for
non-container types). This creates **both** the container file and the bound script, and the
container is created in the account's Drive root — the user may want to move it into a specific
folder afterward.

## Binding to an EXISTING container

`clasp create` cannot bind to a file that already exists — clasp has no CLI flag for this. The
user has to do it once through the UI:

1. Open the existing Sheet/Doc/Form.
2. Extensions → Apps Script. This creates (if not already present) a bound script and opens the
   Apps Script editor.
3. In the editor: Project Settings (gear icon) → copy the **Script ID**.
4. Back in the terminal: `clasp clone <scriptId>` in the folder where the local project should
   live.

Tell the user this upfront if they mention an existing spreadsheet/doc rather than discovering the
`create` limitation after the fact.

## Custom menus

```js
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('My Menu')
    .addItem('Do the thing', 'doTheThing')
    .addToUi();
}
```

`onOpen` is a **simple trigger** — runs automatically when the container opens, no manual trigger
setup needed, but simple triggers run with restricted permissions (no `UrlFetchApp`, no services
needing authorization beyond what the container itself already grants).

## Triggers

- **Simple triggers** (`onOpen`, `onEdit`, `onFormSubmit`, `onSelectionChange`): named functions
  Apps Script calls automatically; no explicit registration, but limited permissions as above.
- **Installable triggers**: needed for anything a simple trigger can't do (sending email, calling
  external services, running on a time schedule). Set up via `ScriptApp.newTrigger(...)` run once
  (e.g. from the editor or `clasp run`), or through the Apps Script editor's Triggers page. These
  persist against the deployed script, tied to the user who created them — don't assume they carry
  over automatically when a different account re-deploys.

```js
function createDailyTrigger() {
  ScriptApp.newTrigger('dailyJob')
    .timeBased()
    .everyDays(1)
    .atHour(6)
    .create();
}
```

Run `createDailyTrigger` once (`clasp run createDailyTrigger`) to install it — don't put trigger
*creation* code inside a function that runs on every execution, or duplicate triggers accumulate.
