# Approaches that don't work -- don't retry these

Learned the hard way building the first Fabric connection (no admin rights,
no app registration allowed). Saves re-discovering the same dead ends on a
new project.

1. **Native Claude Code MCP tool for Fabric**
   (`claude mcp add --transport http fabric-dw
   https://api.fabric.microsoft.com/v1/mcp/dataPlane/sqlEndpoint`) — fails:
   Entra ID doesn't support dynamic client registration, and no app
   registration is available to supply as `--client-id`.

2. **Azure CLI + pyodbc** — fails without admin rights: `winget install` for
   both Azure CLI and ODBC Driver 18 needs admin (exit code 1602). `pip
   install azure-cli` fails to build on Windows without a compiler toolchain.

3. **`python-tds` (pytds) + `azure-identity`** — auth succeeds (device code
   + token acquisition work), but the TDS-level connection itself fails:
   `InterfaceError: Invalid packet type: 18, expected REPLY(4)`. pytds has
   protocol-compatibility gaps specifically against Fabric endpoints.

4. **`mssql-python`'s built-in `Authentication=ActiveDirectoryDeviceCode`**
   — fails immediately with `DeviceCodeCredential.get_token failed:
   Interactive authentication is required to get a token. Call
   'authenticate' to begin.` — a bug in how this driver version drives
   `azure-identity`'s device-code credential internally.

5. **`mssql-python`'s `Authentication=ActiveDirectoryInteractive`** — fails
   with SQLSTATE FA004 / error 0x534. This mode delegates to the Windows
   broker (WAM) for the popup, which isn't available in every shell/session
   context (e.g. remote/headless sessions, some terminal emulators).

   → **Workaround for both 4 and 5:** acquire the access token manually
   (raw MSAL device-code flow) and pass it via the `SQL_COPT_SS_ACCESS_TOKEN`
   connection attribute instead of letting the driver manage auth itself.
   This is what `fabric_query.py.template` does.

6. **`azure-identity`'s `DeviceCodeCredential` +
   `TokenCachePersistenceOptions(allow_unencrypted_storage=True)`** — never
   actually persists anything; no cache file appears, every run re-prompts
   for login. Root cause not fully diagnosed, but the persistence wrapper
   appears to silently no-op without a working OS keychain backend (e.g. no
   `pywin32`/DPAPI available) rather than raising an error.

   → **Workaround:** bypass `azure-identity`'s persistence layer entirely
   and drive `msal.PublicClientApplication` + `msal.SerializableTokenCache`
   directly, with manual file load/save. This is what
   `fabric_query.py.template`'s `get_access_token()` does.

7. **Installing `mssql-python` inside a venv at a long Windows path** (e.g.
   nested several folders deep, especially under a synced Drive/OneDrive
   folder with a long absolute path) — pip install can fail on Windows due
   to the ~260-character MAX_PATH limit. Fix: create the venv at a short
   path close to the drive root (e.g. `C:\Users\<you>\pyv`), not nested deep
   inside a project folder.
