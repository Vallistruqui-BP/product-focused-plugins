# Claude Code plugins

A shareable marketplace of generic, reusable Claude Code plugins: Microsoft
Fabric SQL connections, Confluence/Jira sync, Google Apps Script
development, flowcharting, and a PM/business skills library. No
company-specific configuration required.

## Installing a plugin from here

1. Clone this repo locally.
2. Add the marketplace (one-time, per machine):
   ```
   claude plugin marketplace add "<path to your local clone>"
   ```
3. Install a plugin from it:
   ```
   claude plugin install fabric-connect@pickit-claude-plugins
   ```
4. Verify it loaded:
   ```
   claude plugin list
   ```

That's it — the `connect-fabric` skill (or any other plugin added here
later) is now available in every project you open with Claude Code.

## For the maintainer: adding another plugin later

1. Create `plugins/<new-plugin-name>/.claude-plugin/plugin.json` +
   whatever `skills/`/`commands/`/etc. it needs, same shape as
   `plugins/fabric-connect/`.
2. Add an entry to `.claude-plugin/marketplace.json`'s `plugins` array:
   `{"name": "<new-plugin-name>", "source": "./plugins/<new-plugin-name>", "description": "..."}`.
3. Validate before telling anyone to update: `claude plugin validate .`
   from this folder.
4. Teammates who already added this marketplace pick up new/updated
   plugins with `claude plugin marketplace update pickit-claude-plugins`
   (or `claude plugin update <plugin-name>` for just one plugin).

## Plugins in here

- **`fabric-connect`** — sets up a Microsoft Fabric SQL connection to a
  **new/different** server (no admin rights, no Entra ID app registration
  needed) in any project. See
  `plugins/fabric-connect/skills/connect-fabric/SKILL.md`.
- **`flowchart-builder`** — converts notes/requirements/transcripts into a
  polished draw.io (`.drawio`) flowchart, edited live via chat or by
  drag-editing directly in VSCode (native zoom, no Mermaid/PlantUML
  rendering issues). See
  `plugins/flowchart-builder/skills/flowchart-builder/SKILL.md`.
- **`confluence-live-sync`** — generic, config-driven, bidirectional sync
  between a project folder and its linked Confluence page: `/setup-sync`
  once per folder, then `/sync-doc` to sync bidirectionally (local files
  merge into the page; the page mirrors back into `Confluence Sync.md`), or
  `/watch-start` to run it automatically in the background via a Windows
  scheduled task. No hardcoded project/template — works against any
  Jira/Confluence site you configure. See
  `plugins/confluence-live-sync/README.md`.
- **`appscript-clasp`** — develop Google Apps Script projects locally with
  Claude using `clasp`: create/clone standalone, container-bound, or web
  app projects, write and iterate on code, push/pull, run functions, tail
  logs, and manage deployments. See
  `plugins/appscript-clasp/skills/appscript-clasp/SKILL.md`.
- **`pm-skills`** — a library of ~50 product-management and business
  skills: discovery, PRD writing, roadmap planning, stakeholder mapping,
  finance/SaaS metrics, diagramming (mermaid/drawio/plantuml/excalidraw),
  PDF/PPTX/XLSX generation, prompt engineering, and more. See
  `plugins/pm-skills/skills/`.
