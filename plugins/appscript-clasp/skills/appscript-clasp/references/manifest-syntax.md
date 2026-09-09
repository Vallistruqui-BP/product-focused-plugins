# appsscript.json manifest reference

Every Apps Script project has one `appsscript.json` manifest at the project root. clasp
pushes/pulls it like any other project file — edit it directly.

## Minimal shape

```json
{
  "timeZone": "America/Montevideo",
  "dependencies": {},
  "exceptionLogging": "STACKDRIVER",
  "runtimeVersion": "V8"
}
```

`runtimeVersion` should stay `"V8"` for any new project — the legacy Rhino runtime is deprecated;
don't set it to anything else unless the user is maintaining an old project that specifically
needs it.

## OAuth scopes

Only needed when the script calls a service beyond the implicit scopes Apps Script grants
automatically (Sheets/Docs/Drive access *through the built-in services*, `Logger`, etc. don't need
explicit scopes). Add explicit scopes when:

- Calling `UrlFetchApp` to reach external URLs — needs
  `"https://www.googleapis.com/auth/script.external_request"`.
- Sending mail via `MailApp`/`GmailApp` — needs
  `"https://www.googleapis.com/auth/gmail.send"` or `.../script.send_mail`.
- Using an **advanced service** (see below) — each has its own scope.

```json
{
  "oauthScopes": [
    "https://www.googleapis.com/auth/script.external_request",
    "https://www.googleapis.com/auth/spreadsheets"
  ]
}
```

**Principle of least privilege**: only add the scopes the code actually uses. Adding broad scopes
"just in case" makes the consent screen scarier for whoever authorizes the script and is a real
security smell — don't do it speculatively.

## Advanced services

Enable a Google service beyond the default built-ins (e.g. Admin SDK, BigQuery, Sheets API v4 for
functionality the built-in `SpreadsheetApp` doesn't cover):

```json
{
  "dependencies": {
    "enabledAdvancedServices": [
      {
        "userSymbol": "Sheets",
        "version": "v4",
        "serviceId": "sheets"
      }
    ]
  }
}
```

Enabling an advanced service in the manifest is necessary but sometimes not sufficient — some
services also require enabling the matching API in the linked Google Cloud project
(script.google.com → Project Settings → Google Cloud Platform (GCP) Project). If a call to an
advanced service fails with "API not enabled", that GCP-side toggle is the likely cause, not the
manifest.

## Libraries

```json
{
  "dependencies": {
    "libraries": [
      {
        "userSymbol": "SomeLib",
        "libraryId": "<script id of the library>",
        "version": "3"
      }
    ]
  }
}
```

## webapp / executable API config

`webapp` (access, executeAs) does affect the deployment, and belongs in the manifest — see
`deployment-and-webapps.md` for the full picture. Earlier notes here said this block was "silently
ignored" and that access could only ever be set through the editor UI; that undersold it. In
practice: the very first deploy of a brand-new deployment ID still needs one manual pass through
the editor's deploy dialog to become a correctly-typed Web app at all, **but after that, the
`webapp` block is what keeps `clasp push` + `clasp deploy --deploymentId <id>` updates from silently
reverting the deployment's type back to Library.** Add it and leave it in `appsscript.json` for any
web app deployment you intend to update more than once:
```json
"webapp": {
  "executeAs": "USER_DEPLOYING",
  "access": "DOMAIN"
}
```
The manifest only needs `"executionApi": {"access": "..."}` instead if exposing the script as an
executable API rather than a web app.
