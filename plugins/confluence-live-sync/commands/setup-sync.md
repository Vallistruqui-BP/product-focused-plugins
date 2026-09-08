---
description: Interactively configure this folder to sync with a Confluence page via a matching Jira issue
---

# Set up Confluence live sync (per-folder)

You are configuring **the current working directory** to sync with a Confluence page, following the
same pattern as Pickit's internal `pickit-sync-kickoff` plugin, but generic: every site/project/field
detail is gathered here and written to a config file, never hardcoded.

## 1. Gather settings conversationally

Ask the user for each of these (don't demand them all in one giant prompt if the conversation is more
natural step by step, but do get all of them before writing anything):

1. **Cloud ID** — the Atlassian site, e.g. `example.atlassian.net`. If unsure, call
   `getAccessibleAtlassianResources` and let them pick from what's available in this session.
2. **Jira project key** — e.g. `PYT`.
3. **Issue type** — ask for the display name (e.g. "Idea", "Iniciativa", "Story"). Resolve it to a
   numeric ID via `getJiraProjectIssueTypesMetadata` on the given project key — **never store a
   display-name filter**, only the resolved ID. If the name doesn't match any type exactly, list the
   available type names and ask again.
4. **Extra JQL clause** (optional) — e.g. restricting to issues assigned to the current user, or a
   specific "referente" custom field. Leave empty if they want to match on project + issue type
   alone. Don't validate the syntax beyond confirming it's non-empty; it gets appended into a larger
   JQL query as-is.
5. **Linked-page custom field** — the Jira custom field that holds the URL/link to this issue's
   Confluence page (e.g. `customfield_10904`). If the user only knows it by display name (e.g.
   "Documento de kickOff"), call `getJiraIssueTypeMetaWithFields` for the resolved issue type and
   look for a field whose name matches; report its `customfield_NNNNN` ID back to the user for
   confirmation before using it.
6. **Frozen statuses** (optional) — a list of Jira status names past which this command should never
   edit the page again (e.g. "Desarrollo", "Done"). Empty list is valid (never freeze).
7. **Local file patterns** — which file types in this folder count as sync sources. Default to
   `["*.md", "*.gdoc", "*.drawio"]` unless the user wants something different.
8. **Poll interval** (minutes) — only matters if they later run `/watch-start`; default to `15` if
   they have no preference.

## 2. Validate before writing anything

This mirrors `pickit-sync-kickoff`'s "never guess" philosophy — a bad config silently pointed at the
wrong page is worse than no config.

1. Take the **current working directory's own folder name** (final path component only) as
   `$folderName`.
2. Run this JQL via `searchJiraIssuesUsingJql` (cloudId from step 1), requesting fields
   `["summary", "<linkedPageField>", "status"]`:
   ```
   project = <projectKey> AND issuetype = <issueTypeId> AND <extraJql, if any> ORDER BY updated DESC
   ```
3. Match `$folderName` against each result's `summary` by **exact string equality** (trim whitespace
   both sides). No fuzzy matching.
   - **Zero matches** → stop, do not write the config, and explain clearly: no issue in
     `<projectKey>` with summary exactly `"<folderName>"` matching the given filters. Suggest
     renaming the folder or checking the extra JQL clause.
   - **More than one match** → stop, do not write the config, list every matching key, and explain
     the ambiguity — never guess.
   - **Exactly one match** → continue.
4. Read the linked-page field on that one match. If empty, stop and report `sin página vinculada en
   <KEY> (campo <linkedPageField>)` — nothing to sync against, don't write the config.
5. Extract the Confluence page ID from the field's URL (`/pages/(\d+)/` → numeric ID, or
   `/wiki/x/([A-Za-z0-9]+)` → that code as `pageId`) and confirm it resolves via `getConfluencePage`.
   If it 404s or errors, stop and report the broken link — don't write the config.
6. **Live-doc check**: this plugin only supports classic Confluence pages, never Live Docs (same
   restriction `pickit-sync-kickoff` lives with — see that command's guard for why). Check the
   resolved page's metadata for `subType: "live"` / `iconCssClass: "aui-icon content-type-live-page"`.
   If it's a Live Doc, stop and report: "esta página es un Live Doc — convertila a página clásica
   primero (`•••` → `Convertir a página` en Confluence) y volvé a correr `/setup-sync`." Don't write
   the config.

## 3. Write the config

Only after step 2 fully succeeds, write `.claude/confluence-sync-config.json` (relative to the
current working directory, creating `.claude/` if needed) with this shape:

```json
{
  "cloudId": "<cloudId>",
  "jira": {
    "projectKey": "<projectKey>",
    "issueTypeId": "<resolved numeric id>",
    "extraJql": "<extra clause or empty string>",
    "linkedPageField": "<customfield_NNNNN>",
    "frozenStatuses": ["<...>"]
  },
  "sync": {
    "localFilePatterns": ["*.md", "*.gdoc", "*.mmd"],
    "dedupeGdocCopies": true,
    "pollIntervalMinutes": 15
  }
}
```

## 4. Report

Confirm: which Jira issue and Confluence page this folder is now linked to, the config file path,
and the next steps — `/sync-doc` to run a sync right now, or `/watch-start` to have it run
automatically in the background (mention that `/watch-start` runs Claude unattended with permission
checks off, so they should read what it says before agreeing). If the folder has (or will have)
`.mmd` flowchart files, also mention: rendering them to PNG for the page needs `$env:CONFLUENCE_API_TOKEN`
set to an Atlassian API token (created once at `id.atlassian.com/manage-profile/security/api-tokens`)
— without it, `/sync-doc` falls back to a label-list summary instead of an actual rendered image.
