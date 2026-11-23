# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**nxmcp** is an MCP (Model Context Protocol) server for NexusDB NXserver. This project enables AI assistants to interact with NexusDB databases through the standardized MCP protocol. The server is written in Delphi and uses NexusDB components to connect to the database.

## Repository Structure

- `Source/` - Main source code
  - `nxmcp.dpr` - Main program
  - `dmnx.pas` - NexusDB connection DataModule (auto-creates `nxmcp.ini` on first run)
  - `nxmcp.Resource.*.pas` - MCP resource implementations
  - `nxmcp.Tool.*.pas` - MCP tool implementations
- `sample code/` - Reference code for NexusDB and MCP development
  - `sample code\Delphi-MCP-Server-Reference` - MCP Library (reference only)
  - `sample code\NexusDB` - NexusDB examples
  - `sample code\dataset.serialize` - JSON serialization library
- `DEPENDENCIES.md` - library versions nxmcp is built against, and the dataset-serialize
  patch a build needs

## Development Workflow

**Important:** The user must manually compile and run the Delphi project. Claude cannot execute the compiler or run the executable directly.

- Ask the user to compile and run
- Once running, Claude can interact with the MCP HTTP API via curl
- Default endpoint: `http://localhost:3000/mcp`

## MCP Resources

| Resource URI | Description |
|--------------|-------------|
| `nexusdb://server` | Connection status and server info |
| `nexusdb://tables` | List of all tables in the database |
| `nexusdb://schema` | Schema overview (tables with record counts) |

## MCP Tools

### Query & Discovery (Phase 2)
| Tool | Description |
|------|-------------|
| `execute_query` | Execute SELECT queries, returns JSON results (supports `:name` parameters via `params`) |
| `get_table_schema` | Get detailed schema for a specific table |

### Data Manipulation (Phase 3)
| Tool | Description |
|------|-------------|
| `execute_sql` | Execute INSERT/UPDATE/DELETE statements (supports `:name` parameters via `params`) |
| `get_table_data` | Paginated table data retrieval |
| `insert_record` | Insert record with JSON data |
| `update_records` | Update records matching WHERE clause |
| `delete_records` | Delete records matching WHERE clause |

### Schema Management (Phase 4)
| Tool | Description |
|------|-------------|
| `create_table` | Create new table with column definitions |
| `drop_table` | Delete a table |
| `copy_table` | Clone table structure (optionally with data) |
| `rename_table` | Rename a table |
| `add_column` | Add column with optional default value |
| `drop_column` | Remove column from table |
| `modify_column` | Change column type, size, or rename |
| `create_index` | Create index on column(s) |
| `drop_index` | Remove an index |

### Schema Metadata (Phase 4b)
| Tool | Description |
|------|-------------|
| `set_table_description` | Set or clear the description (comment) on a table |
| `set_column_description` | Set or clear the description on a column |
| `set_index_description` | Set or clear the description on an index |
| `set_field_validator` | Add/remove MinMax or NoChange server-side validator on a column |
| `set_column_default` | Add/replace/clear default value on an existing column (CurrentDateTime, CurrentUser, Constant) |
| `set_data_policies` | Set/clear table-level data policies: deny insert/modify/delete, min/max record count |
| `set_audit` | Enable/disable audit-trail logging and BLOB inclusion for a table |

`get_table_schema` reads the table dictionary directly and surfaces table description, column descriptions, defaults, validators, index descriptions, data policies, audit settings, and (read-only) referential-integrity references. `list_indexes` also includes each index's description.

### Table Maintenance (Phase 5)
| Tool | Description |
|------|-------------|
| `empty_table` | Delete all records from a table (keeps structure) |
| `pack_table` | Compact table to reclaim deleted space |
| `reindex_table` | Rebuild an index |
| `recover_table` | Attempt to recover records from broken table |
| `change_password` | Change table password |
| `get_autoinc_value` | Get next auto-increment value |
| `close_inactive_tables` | Release the tables *and folders* the server holds in its cache for this session |

### Transactions (Phase 6)
| Tool | Description |
|------|-------------|
| `batch_execute` | Execute multiple SQL statements in a single transaction |
| `run_script` | Run a whole script as ONE batch; return the last result set as typed JSON. See "run_script" below |

### Utility (Phase 7)
| Tool | Description |
|------|-------------|
| `count_records` | Get record count using table metadata (fast, no scan) |
| `list_indexes` | List all indexes on a table with their fields |
| `explain_query` | Show query execution plan (standard or verbose mode). Reads are analysed without being run; writes run in an always-rolled-back transaction — see "There is no EXPLAIN" |
| `list_locks` | Live lock state from `#TABLE_LOCKS` / `#TRANSACTION_LOCKS`; absent meta tables reported, not raised |

### Database Management (Phase 8)
| Tool | Description |
|------|-------------|
| `list_aliases` | List available database aliases on the server (reports `currentAlias`/`currentAliasPath`) |
| `switch_database` | Switch the active database by `aliasName` **or** `aliasPath` (keeps session) |
| `switch_server` | Switch server connection (full reconnect): `mode` remote/embedded; optional `aliasName`/`aliasPath` |

### Tool Annotations and Server Instructions
Every tool constructor calls `AnnotateTool(FAnnotations, <kind>)` (`nxmcp.ToolAnnotations.pas`), which sets all four MCP hints explicitly (`openWorldHint` is false except for `switch_server`, which passes `AOpenWorld=True` because it connects to any host and port the caller names). Clients use them to auto-approve or parallelise calls, so they are a promise: **a new tool must pick a kind**, and `tkReadOnly` only when the tool changes nothing at all — data, schema, session or server state.

| Kind | Hints | Tools |
|------|-------|-------|
| `tkReadOnly` | readOnly | `execute_query`, `get_table_data`, `get_table_schema`, `count_records`, `list_indexes`, `list_locks`, `list_aliases`, `get_autoinc_value`, `get_query_log` |
| `tkAdditive` | not destructive, not idempotent | `insert_record`, `create_table`, `create_index`, `add_column`, `copy_table`, `rename_table`, `explain_query` (really executes writes, rolled back - locks, autoinc) |
| `tkIdempotent` | not destructive, idempotent | `set_table/column/index_description`, `set_column_default`, `set_audit`, `reindex_table`, `close_inactive_tables`, `set_timeout`, `switch_database`, `switch_server` |
| `tkDestructive` | destructive | `execute_sql`, `batch_execute`, `run_script`, `update_records`, `delete_records`, `drop_table/column/index`, `empty_table`, `modify_column`, `pack_table`, `recover_table`, `change_password`, `set_field_validator`, `set_data_policies` (the last two block later writes) |

`nxmcp.ServerInstructions.pas` holds `cServerInstructions`, the text sent as `instructions` in the `initialize` result (set in `nxmcp.dpr` unless `[Server] Instructions` in `nxmcp.ini` overrides it). It repeats rules from this file for the AI client — typed literals, `params`, dialect specifics, the one-session gate. **When a tool's behaviour or one of those rules changes, update the text too.**

### Lock Inspection and Cache Release
`list_locks` reads the two **reserved (virtual) meta tables** the server populates on demand: `#TABLE_LOCKS` (record/cursor-level locks — `LOCK_TYPE`, `REFNR`, `WAITING`) and `#TRANSACTION_LOCKS` (transaction-level — `LOCK_STATE`, `EXCLUSIVE`, `TRANSACTION_LEVEL`, `RUNNING_FOR`). Both are defined in `nxsqlProxies.pas` and were **added in a later NexusDB release**, so `list_locks` must not raise on an older server.

Graceful degradation works by *asking the server*, not by trusting the constants compiled into nxmcp: when the `SELECT * FROM #<table>` fails, `ServerKnowsMetaTable` reads `SELECT METATABLE_NAME FROM #META`, which enumerates `ReservedTableNames` **as implemented by the SQL engine that ran the query**. In remote mode that engine lives in `nxServer.exe`, whose version is independent of this client — a client-side check would be wrong there. Only a name genuinely missing from `#META` yields `"available": false` plus an explanation; anything else (permissions, dead socket, …) is re-raised. If the `#META` probe itself fails, it returns `True` so the *original* error surfaces rather than a bogus "your server is too old". `list_locks` needs the SQL engine and therefore `EnsureConnection`. Row keys are lower-camel-cased by `dataset.serialize` (`TABLE_NAME` → `tableName`).

`close_inactive_tables` calls `nxSession1.CloseInactiveTables` **then** `CloseInactiveFolders` (that order — a folder cannot be released while one of its tables is still open; the EnterpriseManager does the same two calls in the same order). It closes `nxQuery1`/`nxTable1` first, since our own active cursors would otherwise survive the sweep. It uses **`EnsureSession`, not `EnsureConnection`**: the cache belongs to the session, and freeing server-side file handles is most useful exactly when the current database will not open — requiring a healthy database would block the cleanup that fixes it.

### Logging
`[Options] LogToFile` (default off) enables file logging; `[Options] LogFileName` overrides the path. **Leave `LogFileName` empty**: `Tnxmodule.ConfigureLogging` then derives `<exe name>.<pid>.log`, one file per process.

NexusDB also installs its own exception hook during unit initialization, before the nxmcp
program body runs. By default it creates a per-executable application-home directory below
`C:\ProgramData\NexusDB4\nxmcp\<encoded executable directory>`. Standard Windows ACLs
normally permit this, but restricted runners and sandboxes may block the write. Always run
relocated diagnostic copies in such environments with a writable NexusDB application home,
for example:

```text
nxmcp.exe /CONFIG:"C:\projects\nxmcp\temp\nxmcp-state"
```

`/CONFIG:` affects NexusDB's application-data and exception-log location only; nxmcp still
loads `nxmcp.ini` beside the executable. A failure here occurs before `nxmcp.dpr` can catch or
log it: the primary symptom is runtime error 217. A later access violation in
`System.TMonitor.Enter` is secondary finalization damage, not evidence that embedded
connection startup was reached. Do not launch a configuration matrix until a remote
`AutoConnect=0` control starts successfully with the same `/CONFIG:` override.

File logging is implemented in `nxmcp.FileLog.pas`, **not** by `TLogger.LogToFile` — `ConfigureLogging` explicitly sets `TLogger.LogToFile := False` and hooks `TLogger.OnLogMessage` instead. Do not turn `TLogger.LogToFile` back on. The library's `EnsureLogFile` opens the log through `TStreamWriter.Create(FileName, ...)`, which passes no share bits (exclusive handle) and lets an open failure escape as an exception. Under the STDIO transport *every MCP client spawns its own `nxmcp.exe`* — Claude Code and Claude Desktop routinely run concurrently — so the second instance could not open the shared log and died before its transport started, which the client reports as "MCP server exited immediately".

`nxmcp.FileLog` instead opens `fmShareDenyWrite` (editors and `tail` can read the log while nxmcp holds it), appends, and is fail-soft: an unopenable or unwritable log emits a `[WARN ] File logging disabled` line on **stderr** (never stdout, which carries JSON-RPC) and the server continues console-only. Setting an explicit `LogFileName` shared by two concurrent instances is therefore safe but pointless — the loser silently drops to console-only.

### Concurrency and Connection Recovery

One process currently owns one mutable NexusDB session. HTTP dispatch is concurrent, so the
tool and resource managers are wrapped at startup as:

```text
FilterTools(SerializeTools(TMCPToolsManager.Create, SharedGate), IsToolEnabled)
FilterResources(SerializeResources(TMCPResourcesManager.Create, SharedGate), IsResourceEnabled)
```

The filter must remain outermost, and both serialized managers must receive the same gate.
Only `tools/call` and `resources/read` acquire it. `tools/list`, `resources/list`,
`resources/templates/list`, core methods such as `initialize`, and `ping` bypass it.
`[Options] BusyTimeout` bounds acquisition independently of the database `Timeout`; `0`
fails fast and negative configured values fall back to 3000 ms. Never log request arguments,
SQL, passwords, or result data while diagnosing contention—only the tool name/resource URI
and wait duration.

Every server round-trip must declare a retry policy. Use `ExecuteWithReconnect` only where
replaying the action is part of the existing contract. Use `ExecuteWithoutRetry` for DDL,
restructure, maintenance, password, and other ambiguous writes. Transaction and switch code
may retain a documented state machine, but it must call `RecoverSessionAfterError` for a
poisoned-session failure before returning. Pure local component property access needs no
round-trip boundary after connection establishment.

`nxSession1.Active` and `nxDatabase1.Connected` are **client-side flags**: after the server dies or the socket drops they both still report `True`, and only the next server round-trip reveals the truth. Recovery therefore needs two mechanisms, and most tools use both.

| Helper | Guarantees | Use when |
|--------|-----------|----------|
| `EnsureConnection` | session **and** database open (`Reconnect` = `ForceDisconnect` + `Connect`) | the tool needs the *current* database — the 36 data/schema tools |
| `EnsureSession` | session/transport/engine only, **database left closed** | the tool is server-level and must survive a database that won't open: `list_aliases`, `switch_database` |
| `ExecuteWithReconnect` | recovers communication loss/re-entry and retries once; reports a timeout without retry | replay-safe round-trips |
| `ExecuteWithoutRetry` | recovers a poisoned session but always reports the original failure | ambiguous writes, DDL/restructure, maintenance and password changes |
| `RecoverSessionAfterError` | classifies, best-effort cancels timeout/re-entry, fully retires and reconnects | transaction/switch state machines that catch the exception themselves |

Recovery policy:

| NexusDB failure | Retry-enabled boundary | No-retry boundary | Session action |
|---|---|---|---|
| `DBIERR_SERVERCOMMLOST` | retry once | report original error | retire and reconnect |
| `DBIERR_REENTERED` | retry once | report original error | cancel best-effort, retire and reconnect |
| `DBIERR_NX_GENERALTIMEOUT` | never retry | never retry | cancel best-effort, retire and reconnect |
| Other | never retry | never retry | leave session alone unless the owning state machine requires cleanup |

Classification lives in `nxmcp.NexusErrors.pas` and must recognize both NexusDB exception
families (`EnxDatabaseError` and `EnxBaseException`). The attempt loop classifies failures
from the retry as well as the first call. Cleanup/reconnect failure is logged but must never
mask the original operation exception.

Rules:
- **Never call `EnsureConnection`/`EnsureSession` in `switch_server` or `SwitchToEmbedded`.** The server being switched away from is frequently the one that is down — that is *why* the caller is switching. Requiring the old connection to be healthy turns the escape hatch into a deadlock.
- **A teardown must never abort on its first failing step.** `Disconnect` and `ForceDisconnect` both run `TearDownComponents`, which wraps every `Close` / `Active := False` in its own `try..except`, so all eight components end up inactive even when the socket is dead. The two differ *only* in whether the first error is recorded in `GLastError` or discarded. Closing a dataset, database or session is a server round-trip and raises on a dead connection; a single-`try` sequence would skip the engines and leave the transport active (which then silently reuses a dead transport on the next `Connect`).
- **Mode-changing** switches tear down via `DisconnectForSwitch`, which guards `ReleaseDatasets` (its `nxSession1.CloseInactiveTables` is a server round-trip) and then calls `Disconnect`. An **embedded→embedded** `SwitchToEmbedded` never tears the engine down — it delegates to `SwitchDatabaseTarget` (database-level close/reopen; session, server engine and SQL engine stay up). `SwitchDatabaseTarget` uses `CloseDatabaseForSwitch`, which falls back to `ForceDisconnect` so that `OpenTargetDatabase` rebuilds the whole chain.
- `OpenTargetDatabase` reopens on the new target, falling back to a full `Connect` when the preceding teardown had to force-disconnect.
- **Switch rollbacks** (all three: `SwitchServer`, `SwitchToEmbedded`, `SwitchDatabaseTarget`): tear down first (`ForceDisconnect` / `CloseDatabaseForSwitch` while connected) - components left active by the failed attempt reject `ServerName`/`AliasName` with "must be inactive", which used to abort the restore half way; restore the target with `RestoreDatabaseTarget`, which clears **both** alias properties first (NexusDB only clears the other one for a non-empty value); bring the connection back only to the level snapshotted before the switch (`LOldDbOpen`/`LOldSessionOpen` → `RestorePreviousLevel`: database, session only, or nothing); and if the rollback itself fails, `RetireAfterFailedRollback` (full teardown) so no half-built chain is reused. `ConnectRemote` and `EnsureSession` copy host, port and target from the fields onto inactive components, so a reconnect always follows the fields. A restored rollback appends `cPreviousRestored` to the error.
- In the `except` block of any switch, hold the failure message in a **local** before rolling back: `Connect` resets `GLastError` to `''` on entry, so a successful rollback silently erased the original error (this surfaced as `Error executing tool:` with an empty message).
- **Embedded targets are validated before anything closes.** The embedded engine opens a directory in *this* process, so `SwitchToEmbedded`, `SwitchDatabaseTarget` (embedded mode) and `ConnectEmbedded` all reject a non-existent path with `Embedded database path does not exist: ...` while the current connection is still fully intact. Remote alias paths are server-side and cannot be pre-checked.
- **Fatal engine state is surfaced, never reset.** Once NexusDB records a critical failure (e.g. an AV inside engine code) the process-wide `nxllException._FatalException` flag makes every engine call fail with "operations are suspended until the server is restarted", and nothing short of a process restart clears it — for embedded mode "the server" *is* nxmcp.exe. `dmnx.WithFatalHint` appends a restart hint to connect/switch errors when the flag is set. Do not try to reset the flag; it exists to protect data files.

### Server Mode: Remote vs Embedded
The `[Connection] Mode` ini key (or `switch_server`'s `mode` param) selects how `nxSession1` reaches a server:
- **Remote** (default) — `nxSession1.ServerEngine = nxRemoteServerEngine1` over `nxWinsockTransport1` (a separate NXserver process). Supports `AliasName` or `AliasPath`.
- **Embedded** — `nxSession1.ServerEngine = nxServerEngine1`, an in-process `TnxServerEngine` with `nxSqlEngine1` (`TnxSqlEngine`, wired in `dmnx.dfm` via `SqlEngine = nxSqlEngine1`) and the storage sub-engines from `uses nxseAllEngines`. **Embedded has no aliases — `AliasPath` only, and it is required.**

`Connect` branches to `ConnectRemote`/`ConnectEmbedded`; `Disconnect`/`ForceDisconnect` deactivate *both* engines so the components not in use are always `Active := False`. `WireServerEngine` (re)points the session at the mode's engine (session must be closed). Runtime switch: `switch_server mode="embedded" aliasPath=...` → `dmnx.SwitchToEmbedded`; `mode="remote" ...` → `dmnx.SwitchServer` (a mode change does a full reconnect with rollback and sets `FServerMode`; embedded→embedded only switches the database, see the rules above). `switch_database` by `aliasName` is rejected while embedded (path only). `IsEmbedded`/`ServerMode` expose the state; `Tnxmodule.ModeToStr`/`StrToMode` parse `Remote`/`Embedded`.

> **Win64 build note (embedded SQL):** an older NexusDB revision truncated a pointer through a 32-bit `DWord` in the SQL tokenizer, so every embedded query on Win64 failed with `Invalid token: error at line 1 pos 1` (remote is unaffected — it tokenizes in the 32-bit `nxServer.exe`). Reported by a contributor building embedded support in July 2026. **Fixed in 4.75**, which uses the pointer-sized `TnxMemSize` at `nxSQLTok.pas:1213`; no patch needed there or later.

> **Stale-library build note (embedded switch AV):** a July 2026 beta build crashed with `Access violation ... Read of address 0000000000000010` on the *second* embedded engine activation in one process (`switch_server mode="embedded"`, any target path), after which the exception hook set `_FatalException` and every call failed with "suspended until the server is restarted". The crash is a NexusDB library bug in pre-2026-07-09 `nexusdb4` sources; it is not reproducible when built against the library from 2026-07-13 or later (verified by driving `dmnx.pas` through the exact scenario, cross-thread, valid and invalid paths). If that signature ever reappears, first check which library revision the exe was built against — and note nxmcp now avoids the engine bounce entirely for embedded→embedded switches anyway.

**AliasName vs AliasPath:** `TnxDatabase` exposes two mutually-exclusive ways to point at a database — `AliasName` (a server-configured alias) and `AliasPath` (a server-side filesystem path to the database folder). Setting one clears the other on the component, and both require the DB to be closed first (the switch/reconnect logic already handles this). The `.ini` `[Database]` section accepts either `AliasName` or `AliasPath` (path wins if both are set). `switch_database`/`switch_server` accept either `aliasName` or `aliasPath` (never both). The DataModule tracks the active target in `FAliasName`/`FAliasPath` (exactly one non-empty); `dmnx.SwitchDatabaseTarget` is the shared core with name/path-aware rollback, wrapped by `SwitchDatabase` and `SwitchDatabaseByPath`.

**Table passwords across switches:** the INI passwords (`TablePassword`, comma-split, plus verbatim `TablePasswords1..N`) are kept in `FIniTablePassword`/`FIniExtraTablePasswords`; `SetTablePasswords` derives the active set. `switch_database` keeps the INI passwords in effect (same server) and adds a tool-supplied `tablePassword` on top. `switch_server` / switch to embedded keep them only when returning to the INI-configured target (remote: same host and port, compared literally; embedded: INI mode is `Embedded`); otherwise only the tool-supplied password is used. `[Database] TablePasswordServers` widens this for installations with several servers sharing database copies: a comma list of `host:port`, `host` (any port), `[ipv6]:port`, `embedded`, or `*` (any target). `Tnxmodule.IniPasswordsAllowedFor` decides; the INI target always qualifies, compared literally. Parsing (`TryParsePasswordServer`) **fails closed**: a port separator needs a valid port (digits, 1..65535), nothing may follow `[ipv6]` but `:port`, and an invalid entry is dropped with a console warning at startup - a typo like `dbhost:` must never widen to every port of `dbhost`. **The default stays empty**: `switch_server` takes its target from the AI client and `PasswordAdd` transmits the password to that server, so `*` as a default would hand the secrets to any host a (possibly prompt-injected) client names. `SetTablePasswords` logs whether the INI passwords are in effect for a target, never the passwords. A `switch_database`/`switch_server` call to the target that is already open is a no-op ("Already connected") **only without** a `tablePassword`; with one, the tools run the regular switch to the same target, so the password replaces the previous tool-supplied one. **Never send the INI passwords to a server that `TablePasswordServers` does not list** — an AI client chooses the `switch_server` target, so that would hand the configured secrets to any host it names (PR #2 closed that leak). PR #6 proposed a global opt-in; it was replaced by this explicit list, with `*` available but never the default. `ApplyConfiguredPasswords` calls `PasswordRemoveAll` first so the session holds exactly the active set, and `AddSessionPassword` uses `PasswordAddEx(..., True)` because plain `PasswordAdd` raises `DBIERR_NAMENOTUNIQUE` for a password the session already holds. **The session is the single source of table passwords:** table-level API calls (`GetDataDictionaryEx`, `RestructureTableEx`, `EmptyTable`, `RenameTable`, `PackTableEx`, …) pass `cSessionPasswords` (`''`) as their explicit password. The server merges the session list with the explicit one (`TnxServerSession.ssBuildPasswords` copies `ssPasswords` and only appends `aPassword`, `nxsrServerEngine.pas`), so an explicit password adds nothing — verified with a database whose password existed only on the session. There is deliberately no `TablePassword` property any more: it could not express a password set (a comma-list INI value is not a valid password).

**batch_execute usage:**
```json
{
  "statements": ["SELECT * FROM Orders", "SELECT * FROM Inventory"],
  "snapshot": true
}
```
- Supports SELECT, INSERT, UPDATE, DELETE
- All statements succeed together or all are rolled back. Every statement is sent prefixed with `cNoAutoCommitOnDDL` (`#OPT::STATEMENT::AUTOCOMMITONDDL='0'`, `nxmcp.SqlUtils`), and statements mentioning `AUTOCOMMITONDDL` are refused: with that option on (e.g. at SESSION scope from an earlier `execute_sql`), NexusDB commits the transaction before each DDL statement and starts a new one, so the work before the DDL survived while the tool reported `transactionRolledBack: true` (verified on 4.75). With the prefix, DDL fails inside the transaction and everything is rolled back. `run_script` shares the constant and `MentionsAutoCommitOnDDL`.
- `snapshot`: Use snapshot transaction for consistent point-in-time reads (default: false)
- SELECT results include `data` array; non-SELECT results include `rowsAffected`

**run_script** (`nxmcp.Tool.RunScript.pas`) exists because `batch_execute` runs each statement separately (a `#temp` table is gone by the next one) and `execute_query` must keep refusing multi-statement and `INTO`. Rules that keep it correct:
- The whole script is one `nxQuery1.Open`. `TnxDataset.OpenCursor` (`nxdb.pas`) executes without raising when the last statement returns no cursor and just creates no fields, so `FieldCount = 0` means "no result set, read `RowsAffected`". Never fall back to `ExecSQL` after `Open`: that would run the script twice.
- Always `ExecuteWithoutRetry` - a script may write and must never be replayed.
- `InTransaction` asks the server (`TransactionGetLevel`), so it also sees `START TRANSACTION` issued inside the script. `RollbackAll` rolls back every level; in `commit` mode, still being in a transaction after our `Commit` means the script left a level open, so everything is rolled back and an error returned (nothing committed). A transaction already open at entry is a leftover (calls are serialized, no tool keeps one across calls), so it is rolled back and reported as `staleTransactionRolledBack` - refusing would be a dead end, no tool can end it. `RollbackAll` raises if levels remain after `cMaxRollbackLevels`.
- Results are formatted by `FieldToJSON`, not `dataset.serialize`: column names stay as NexusDB returns them (no camel-casing; a repeated name is made unique by the dataset layer, e.g. a second `ID` becomes `ID_2` - verified), rows are arrays, dates are ISO 8601 without offset, BLOBs are base64 with no line breaks (`TBase64Encoding.Create(0)`) or `{bytes, md5}`. Currency: `TJSONNumber.Create(Currency)` serializes exactly, but the dataset already delivers a `Double` (`TCurrencyField` is a `TFloatField`, `TField.GetAsCurrency` = `GetAsFloat`), so precision is ~15 significant digits; `CurrToStr` would not help.
- A failed script raises `EMCPToolError` whose message is the JSON error object (`success: false`, `error`, `errorCode` from `NexusErrorCode`, `rolledBack`, ...). The tools manager turns `EMCPToolError` into an `isError: true` result with the message as text, verbatim (no `Error executing tool:` prefix), so clients see a failed call and callers can still compare the exact NexusDB message. Parameter validation errors are re-raised as they are (plain tool errors).
- NexusDB refuses DDL inside a transaction (`$3CA0/15520`), so DDL scripts need `transaction="none"`.
- What can end the tool's transaction from inside a script (verified on 4.75): a bare SQL `COMMIT` cannot - NexusDB refuses it with "No explicit transaction is currently in progress" (the SQL-level and API-level transactions are tracked separately). `#OPT::...::AUTOCOMMITONDDL='1'` can: it commits before each DDL and starts a new transaction, so an INSERT before a CREATE TABLE survived "rollback" mode while the tool reported `rolledBack: true`. Hence scripts mentioning `AUTOCOMMITONDDL` are rejected in `rollback`/`commit` mode, and in those modes the script is sent prefixed (inline, on line 1) with `#OPT::STATEMENT::AUTOCOMMITONDDL='0'` (`cNoAutoCommitOnDDL`): options resolve from the statement outwards, so this also neutralizes the option inherited at SESSION/DATABASE scope from an earlier `execute_sql` or `run_script transaction="none"`. Side effect: a syntax error on line 1 reports a shifted position. As a further safety net, if `InTransactionNow` is False after the script the result carries a `warning` and `rolledBack`/`committed` false.
- Every `InTransaction` probe and rollback goes through `InTransactionNow`/`RollbackAll`, i.e. inside `ExecuteWithoutRetry`: it is a server round-trip, and outside a boundary a dead socket would never retire the session.
- A leading U+FEFF (script read from a UTF-8 file with BOM) is stripped: NexusDB does not skip it, it breaks a leading `--` comment and the first statement then fails with a syntax error.

### Query Parameters (execute_query / execute_sql)
Both tools accept an optional `params` argument — a JSON array (passed as a string, like all complex tool arguments) binding values to `:name` placeholders in the SQL:

```json
{
  "sql": "SELECT * FROM Orders WHERE CustomerGuid = :cust AND OrderDate >= :since AND Total > :min",
  "params": "[{\"name\":\"cust\",\"value\":\"d94660ff-...\",\"type\":\"guid\"},{\"name\":\"since\",\"value\":\"2024-01-15\",\"type\":\"date\"},{\"name\":\"min\",\"value\":100}]"
}
```

- Entries are `{"name", "value", "type"?}`. `type` is inferred from the JSON value when omitted (integral number → integer, fractional → float, bool → boolean, string → string); explicit types: `string`, `memo`, `integer`, `float`, `currency`, `boolean`, `date`, `time`, `datetime`/`timestamp`, `guid`, `blob` (base64). `"value": null` (or omitting `value`) binds a typed NULL.
- Values are bound as **native typed TParams** (`nxmcp.QueryParams.pas` → `ApplyJsonParamsToQuery`), not spliced into the SQL — no quoting/escaping, and **no typed-literal syntax needed** for GUID/DATE/TIME/DATETIME columns (this is the easiest way to compare against those columns; see "Typed-literal columns" below for the raw-SQL rules). Same lenient input as `insert_record` (bare/braced GUIDs any case; `T` or space separators; trailing `Z`/offset stripped). Date/time strings are converted to `TDateTime` client-side, so binding is locale-independent.
- NexusDB parses `:name` per **occurrence** (`quParseSql` creates one TParam each, all replaced positionally with `?`); a repeated name is bound to every occurrence. `:"multi word"` names are supported; `::` and colons inside quotes/comments are not parameters.
- Both tools call `nxQuery1.Params.Clear` before setting `SQL.Text`: `TnxQuery.quSqlChanged` carries old values onto same-named params of the next statement (`TParams.AssignValues`), which would let a stale binding from a previous tool call silently satisfy the missing-parameter check.
- Client-side validation errors (before the server round-trip): missing values for placeholders, names not in the SQL (lists what is), unknown `type`, unknown entry keys (catches `"vaule"` typos), fractional value with type `integer`, invalid GUID/date/time/base64.
- `explain_query` and `batch_execute` do **not** take params.

## NexusDB-Specific Notes

### SQL Syntax Differences
- DROP INDEX: `DROP INDEX "tablename"."indexname"` (not `ON` syntax)
- RENAME TABLE: `ALTER TABLE "old" RENAME TO "new" RESTRICT`
- System tables: `#TABLES`, `#FIELDS`, `#INDEXES` (column names have underscores like `TABLE_NAME`)

### Typed-literal columns: GUID / Date / Time / DateTime (string literals rejected)
NexusDB does **not** coerce a plain string literal (`'...'`) into a GUID, DATE, TIME or DATETIME column — assigning or comparing one raises `Type mismatch ... (column: X, [GUID/DATE/...])`. Each requires its typed literal, in a **fixed format** (parsed by `StringToGUID` and `nxsdDateTimeParser.pas`, which are strict about position/length):

| Column type | Typed literal | Format notes |
|---|---|---|
| GUID | `GUID '{...}'` | **Braces required** (`{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}`); stored/returned braced + uppercase |
| Date | `DATE 'YYYY-MM-DD'` | exactly 10 chars |
| Time | `TIME 'HH:MM:SS'` or `'HH:MM:SS.fff'` | len 8 or 12 |
| DateTime | `TIMESTAMP 'YYYY-MM-DD HH:MM:SS[.fff]'` | **space** between date and time, **not** `T`; no timezone offset |

```sql
-- WRONG (type mismatch):  SET "DT" = '2024-01-15 13:45:00'   /  SET "DT" = TIMESTAMP '2024-01-15T13:45:00'
-- RIGHT:                  SET "DT" = TIMESTAMP '2024-01-15 13:45:00'
```
Watch out for round-trips: `get_table_data`/`execute_query` return DateTime as ISO 8601 **with `T` and a local offset** (e.g. `2024-01-15T13:45:00.000+01:00`, per the `dataset.serialize` export config in `dmnx.pas`), which is **not** directly writable — the `T` and offset must be removed.

`insert_record` / `update_records` handle all of this automatically: they read the table's column types (`nxmcp.ValueFormat.pas` → `GetTableFieldTypes`) and emit the correct typed literal, normalizing the incoming JSON string via `FormatJsonValueAsSql` (`NormalizeGuidLiteral` / `NormalizeDateLiteral` / `NormalizeTimeLiteral` / `NormalizeTimestampLiteral`). They accept lenient input — bare or braced GUIDs (any case), and dates/times with `T` or space separators and a trailing `Z`/offset (stripped, wall-clock preserved) — and reject genuinely invalid values with a clear client-side message. The **WHERE clause** of `update_records` and the raw `batch_execute` SQL are passthrough — there you must write the typed literal yourself. In `execute_query`/`execute_sql`, prefer a `:name` parameter with `type` guid/date/time/datetime (see "Query Parameters" above) — typed binding sidesteps the literal syntax entirely.

### Schema Operations
- Use `TnxDataDictionary` for schema manipulation (faster than SQL)
- Restructure via `database.RestructureTableEx()` with `TnxTableMapperDescriptor`
- Table passwords: Use `SET PASSWORDS ADD 'password'` after connection

### Field Types
Supported types for create_table/add_column:
`AutoInc`, `ShortString`, `WideString`, `Integer`, `Int64`, `Word`, `Byte`, `Boolean`, `Float`, `Currency`, `DateTime`, `Date`, `Time`, `Blob`, `Memo`

### Column Options on create_table / add_column / modify_column
`create_table` columns accept per-column `required` (NOT NULL), `description`, and a `default` object (`{type, constantValue?, applyAt?, applyOnInsert?, applyOnModify?, overwriteNonNull?}`); plus a table-level `description`. `add_column` accepts `required`, `description`, `defaultValueType` (incl. `Constant` via `constantValue`), `applyAt`, `applyOnModify`, `overwriteNonNull`. `modify_column` accepts `required` as a tri-state string (`"true"`/`"false"`/empty = unchanged). Shared logic lives in `nxmcp.ColumnSpec.pas` (`SetFieldDefault`, `ApplyColumnMetadataFromJSON`). NOTE: `fdRequired` is set directly, then reconciled with `FieldsDescriptor.UpdateSetupAndOffsets` (the EnterpriseManager restructure pattern).

### Default Value Types
For add_column/create_table: `CurrentDateTime`, `CurrentUser`, `Constant`

### Statement Switches
Prefix SQL with switches to control execution:
| Switch | Syntax | Purpose |
|--------|--------|---------|
| `#B` | `#B+` / `#B-` | BLOB copying (default `-`: link only) |
| `#I` | `#I+` / `#I-` | Index optimization (default `+`: on) |
| `#S` | `#S+` / `#S-` | Query simplification (default `+`: on) |
| `#L` | `#L+` / `#L-` | Query logging: plan summary, index used, join strategy |
| `#V` | `#V+` / `#V-` | Verbose logging: full optimizer decisions, all indexes considered, relation analysis |
| `#T` | `#T 5000` | Timeout in milliseconds |
| `#OPT` | `#OPT::STATEMENT::NO_PROCESSING='1'` | Set a server-side option; see below |

`compPROD_nxSQL` (`nxSQLParse.pas`) loops over the switch kinds, so any number of them may be
prefixed in any order — `#L+ #OPT::… #I- SELECT …` is one statement, not a batch.

**`#OPT::<group>::<name>='<value>'`** sets an engine option, where `<group>` is `STATEMENT`,
`DATABASE`, `TRANSCONTEXT` or `SESSION`. The one nxmcp uses is `NO_PROCESSING='1'` — the closest
thing NexusDB has to an EXPLAIN, see below. Note the scope: `SESSION`/`DATABASE` options outlive
the statement, which is why `StripSwitches` deliberately does **not** strip `#OPT` — leaving it in
makes `AnalyzeSql` classify the input as `skOther`, so no caller can smuggle an option through the
SQL of a tool that promises to read.

```pascal
// Example: Get the execution plan for a read WITHOUT reading any rows
nxQuery1.SQL.Text := '#L+ #OPT::STATEMENT::NO_PROCESSING=''1'' ' +
                     'SELECT * FROM Orders WHERE Status = ''Active''';
nxQuery1.Open;   // NOT Prepare - see below; Open returns an empty result set
// nxQuery1.Log now contains the plan

// Example: Disable index optimization for testing
nxQuery1.SQL.Text := '#I- SELECT * FROM LargeTable WHERE ID > 100';
```

### There is no EXPLAIN, and no query plan object either (verified in the engine source)
Checked against the installed NexusDB tree in `C:\ProgramData\NexusDB\NexusDB4` (a hidden
directory — it is on the compiler's unit path but easy to miss when searching for sources), and
confirmed by the NexusDB lead developer.

* **No EXPLAIN anywhere.** No such keyword in the grammar, no `GetPlan`/`QueryPlan` symbol.
* **There is no plan artifact.** `TnxSqlRowBuilder.Optimize` records its decisions in the row
  builder's own state (index choice, join strategy, `WasOptimized`/`FullyOptimized`) and merely
  *narrates* them via `LogNormal`/`LogVerbose` into a `TnxSqlLogList` — a plain string list. There
  is nothing to serialize, which is why there is nothing to EXPLAIN.
* **`Prepare` does not produce it.** `TnxSqlStatement.ssPrepare` (`nxsqlEngine.pas:592`) only
  parses and binds; the only thing it ever writes to its stream is an error message. The optimizer
  runs inside execution — `Optimize` is called at the top of `TnxSqlRowBuilder.Execute`
  (`nxsqlTableExp.pas:7437`).
* **The log ships only in the exec reply.** `TnxSqlStatement.Exec` writes `LogList` into the exec
  stream and then clears it (`nxsqlEngine.pas:463-477`); the client reads `sdLog` exclusively from
  `ExecStream` (`nxdb.pas:20683-20694`) and never looks at the prepare stream. So `Prepare` alone
  always leaves `Log` empty.
* **A failed statement still returns its plan.** The engine attaches the log to the exception as
  `nxeCustomInfo('SqlLog', …)` (`nxsqlEngine.pas:499`) and the client falls back to it when the
  normal path yielded nothing (`nxdb.pas:20714`). That is why `get_query_log` works after a
  timeout.

**`NO_PROCESSING` is the engine's answer for reads.** With the option set,
`TnxSqlRowBuilder.ReadSources` (`nxsqlTableExp.pas:4048`) returns immediately while `Optimize` —
and therefore the whole `#L+`/`#V+` narration — still runs: parsed, bound, optimized, zero rows
read. Two adapters shipped in NexusDB's own `Bonus\` folder (DevExpress Server Mode, ReportBuilder
DADE) use it to fetch a query's metadata without its data.

**It refuses writes.** INSERT/UPDATE/DELETE/COMMIT raise `'… not supported in no processing mode'`
at the top of their `Execute` (`nxsqlDataManip.pas:560/1049/1391/1972`), as does all DDL
(`nxsqlDataDef.pas`). So `explain_query` needs two strategies, and has them:

| Statement | Strategy | Response |
|---|---|---|
| SELECT (no INTO) | `#OPT::STATEMENT::NO_PROCESSING='1'` — optimizer runs, row loop does not | `executed: false` |
| INSERT/UPDATE/DELETE, SELECT … INTO | really executed, inside a transaction that is always rolled back | `executed: true`, `rolledBack: true` |
| DDL | rejected — not transactional, and no-processing refuses it too | — |

### Transaction API
NexusDB transactions are managed via `TnxDatabase`:
```pascal
nxDatabase1.StartTransaction(Snapshot);  // Begin (snapshot=true for read consistency)
nxDatabase1.TryStartTransaction(Snapshot); // Returns false if already in transaction
nxDatabase1.Commit;    // Commit (manual rollback needed on error)
nxDatabase1.Rollback;  // Rollback all changes
nxDatabase1.InTransaction;  // Check if in transaction (property)
```

## Key Units

- `nxsdDataDictionary` - Schema manipulation
- `nxsdTypes` - Field types (TnxFieldType)
- `nxsdTableMapperDescriptor` - Restructure mapping
- `nxsdServerEngine` - Task info types (TnxTaskStatus, TnxAbstractTaskInfo)
- `nxllException` - nxCheck error handling

## Error Handling Patterns

### Ex Methods Return Error Codes
Methods ending in `Ex` return `TnxResult` instead of raising exceptions.

**Synchronous methods:**
| Method | Ex Variant | Notes |
|--------|------------|-------|
| `CreateTable` | `CreateTableEx` | Create new table |
| `GetDataDictionary` | `GetDataDictionaryEx` | Get table schema |
| `ChangePassword` | `ChangePasswordEx` | Change table password |
| `DeleteTable` | - | No Ex variant (raises exception) |
| `EmptyTable` | - | No Ex variant (raises exception) |
| `RenameTable` | - | No Ex variant (raises exception) |

**Async methods (return TnxAbstractTaskInfo):**
| Method | Ex Variant | Notes |
|--------|------------|-------|
| `RestructureTable` | `RestructureTableEx` | Modify table structure |
| `PackTable` | `PackTableEx` | Compact table, reclaim space |
| `ReIndexTable` | `ReIndexTableEx` | Rebuild index |
| `RecoverTable` | `RecoverTableEx` | Recover broken table |

**Other methods returning TnxResult:**
- `AddFieldToTable()` - simpler alternative to restructure for adding fields

**Always wrap `*Ex` methods with `nxCheck()`:**
```pascal
uses nxllException;

// Wrong - ignores error
nxmodule.nxDatabase1.GetDataDictionaryEx(TableName, Password, Dict);

// Correct - raises exception on error
nxCheck(nxmodule.nxDatabase1.GetDataDictionaryEx(TableName, Password, Dict));
```

### Async Task Error Handling
For async operations like `RestructureTableEx`, check errors at TWO points:

1. **Immediate** - the method return value (e.g., table locked)
2. **After completion** - `TnxTaskStatus.tsErrorCode` (e.g., processing errors)

```pascal
// 1. Check immediate error
nxCheck(nxmodule.nxDatabase1.RestructureTableEx(TableName, Password,
  NewDict, Mapper, LTaskInfo));

// 2. Wait for completion and check task status
if Assigned(LTaskInfo) then
try
  while True do
  begin
    LTaskInfo.GetStatus(LCompleted, LTaskStatus);
    if LCompleted then
      Break;
    Sleep(100);  // Avoid busy-waiting
  end;
  nxCheck(LTaskStatus.tsErrorCode);  // Check async error
finally
  LTaskInfo.Free;
end;
```

### TnxTaskStatus Fields
```pascal
TnxTaskStatus = packed record
  tsStartTime    : TnxWord32;    // Start tick count
  tsSnapshotTime : TnxWord32;    // Current tick count
  tsTotalRecs    : TnxWord32;    // Total records to process
  tsRecsRead     : TnxWord32;    // Records read
  tsRecsWritten  : TnxWord32;    // Records written
  tsErrorCode    : TnxResult;    // Error code (check with nxCheck)
  tsPercentDone  : Byte;         // Progress percentage
  tsFinished     : Boolean;      // Completion flag
  tsErrorMessage : string;       // Human-readable error message
end;
```
