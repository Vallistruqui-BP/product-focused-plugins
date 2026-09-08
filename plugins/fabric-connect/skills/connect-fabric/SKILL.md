---
name: connect-fabric
description: Set up a working SQL query connection from Claude Code to a Microsoft Fabric SQL analytics endpoint (a Lakehouse or Warehouse item) in the current project -- no admin rights and no Entra ID app registration required. Use whenever the user wants to query Microsoft Fabric, connect to a Fabric Lakehouse/Warehouse, or asks to set up/repeat "the same Fabric connection as before" in a new project.
---

# Connect to Microsoft Fabric (no admin rights, no app registration)

This sets up a project with the ability to run T-SQL queries against a
Microsoft Fabric SQL analytics endpoint, authenticating via device-code
login against Azure CLI's public first-party client ID -- not a custom app
registration, which many orgs restrict or which the user may not have
permission to create. It was built once, the hard way (see `DEAD_ENDS.md`
in this skill's folder), and this skill exists so that work never has to be
redone from scratch on a new project.

## When to use this

The user wants to query Microsoft Fabric (a Lakehouse or Warehouse's SQL
analytics endpoint) from Claude Code, in a project that doesn't already
have a working connection. If the project already has a `fabric_query.py`
(or equivalent) that works, don't redo this -- just use it.

## Step 1 -- confirm the constraints and gather connection details

Ask the user (skip whichever you can infer or they've already stated):

1. **No admin rights, and/or no Entra ID app registration available or
   wanted?** This skill's whole approach exists for that case. If the user
   *does* have an app registration and admin rights, a more conventional
   `pyodbc` + `ClientSecretCredential` setup may be simpler -- ask which
   they'd prefer rather than assuming.
2. **The Fabric SQL analytics endpoint connection string.** In the Fabric
   portal: open the Lakehouse/Warehouse item, then open its **SQL analytics
   endpoint** (a separate item in the workspace, darker-blue database icon
   -- not the Lakehouse/Warehouse item itself, which has a lighter icon) →
   Settings → Connection string. Looks like
   `<workspace>-<item>.datawarehouse.fabric.microsoft.com`.
3. **The database (Lakehouse/Warehouse) name**, shown alongside that same
   connection string.
4. **Is the project folder inside a cloud-synced path** (OneDrive, Google
   Drive Desktop, Dropbox, etc.)? This matters for where the token cache
   file goes in Step 4 -- it will hold a live refresh token and must NOT
   live in a cloud-synced folder.

## Step 2 -- set up the Python environment

Check for existing `mssql-python`/`msal` availability first; if missing:

```
pip install --user mssql-python msal
```

`mssql-python` is Microsoft's official driver and bundles its own ODBC
driver -- no system-level ODBC install needed, works without admin rights.

**Windows-specific gotcha:** if `pip install` fails with a path-length
error, it's the ~260-char `MAX_PATH` limit combined with a deeply-nested
project folder. Fix: create a short-path venv close to the drive root, e.g.:

```
python -m venv C:\Users\<username>\pyv
C:\Users\<username>\pyv\Scripts\python.exe -m pip install --user mssql-python msal
```

and use that interpreter for everything in this project going forward.

## Step 3 -- scaffold the query runner

Copy `fabric_query.py.template` (in this skill's folder) into the target
project as `fabric_query.py`, then fill in the three `>>> FILL IN <<<`
sections:

- `SERVER` / `DATABASE` — from Step 1.
- `TOKEN_CACHE_PATH` — a **local-only** path, e.g.:
  - If the project is cloud-synced: `Path.home() / ".fabric" /
    "<project_name>_token_cache.bin"` (outside the synced folder).
  - If the project is already local-only: can live next to the venv, or
    even in the project itself -- your call, but flag to the user that
    it's a credential file and should never be committed to git or synced
    anywhere.

Do not otherwise modify the template's auth logic (`get_access_token`,
`_load_cache`/`_save_cache`, the `SQL_COPT_SS_ACCESS_TOKEN` injection) --
see `DEAD_ENDS.md` for why each piece is shaped the way it is; the obvious
simpler alternatives (driver's built-in AD auth modes, `azure-identity`'s
own token cache persistence) are the ones that don't actually work.

## Step 4 -- first login and verification

Run a trivial query to bootstrap the connection:

```
python fabric_query.py "SELECT TOP 10 * FROM INFORMATION_SCHEMA.TABLES"
```

This prints a `https://microsoft.com/devicelogin`-style URL and a short
code. The user opens that URL in a browser and signs in within a few
minutes. On success, the token cache file is created and every subsequent
run reuses it silently -- no repeated logins. (The cache eventually needs a
fresh login again when the refresh token expires -- normally on the order
of months, not something to design around up front.)

Confirm the query returned results before considering setup done.

## Step 5 -- apply these standing conventions going forward

Unless the user says otherwise, apply these to every query written against
this connection from now on (they came from hard-won production-safety
lessons on the first project this was built for):

- **Always cap results:** `SELECT TOP N ...` on every query, so nothing
  can do an unbounded scan against production data.
- **Always pretty-print SQL:** one column per line, multi-line
  `FROM`/`JOIN`/`WHERE`/`ORDER BY` -- never a single long line. This is for
  the end user's own readability when they look at a saved `.sql` file, not
  a technical requirement.
- **Read-only by default:** only run `SELECT` unless the user explicitly
  asks for something else. (Lakehouse SQL analytics endpoints are
  typically read-only by platform design regardless -- Warehouses may not
  be, so don't assume that safety net exists there.)

## Step 6 -- if something in Step 2-4 fails

Check `DEAD_ENDS.md` in this skill's folder first -- it documents six
specific failure modes already hit and worked around (MCP dynamic client
registration, `pyodbc`/Azure CLI needing admin, `python-tds` protocol
incompatibility, the driver's own broken AD auth modes, `azure-identity`'s
non-functional token persistence, and the Windows path-length install
failure). Don't re-derive a workaround for one of these from scratch --
the fix is already documented.

## Reusing an existing multi-query pattern

`fabric_query.py.template` also includes `run_many(named_queries,
save_files, interactive)` for running several queries under a single login
(avoids repeated device-code logins when a script needs multiple queries),
and an `interactive=False` mode on `get_access_token`/`run_many` that
raises `NeedsInteractiveLoginError` instead of hanging, for use in
unattended/scheduled jobs where nobody is present to complete a login
prompt. Reach for these directly rather than writing your own multi-query
or scheduled-job wrapper.
