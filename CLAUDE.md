# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**nxmcp** is an MCP (Model Context Protocol) server for NexusDB NXserver. This project enables AI assistants to interact with NexusDB databases through the standardized MCP protocol. The server is written in Delphi and uses NexusDB components to connect to the database.

## Repository Structure

- `Source/` - Main source code
  - `nxmcp.dpr` - Main program
  - `dmnx.pas` - NexusDB connection DataModule
  - `nxconfig.ini` - Configuration file
  - `nxmcp.Resource.*.pas` - MCP resource implementations
  - `nxmcp.Tool.*.pas` - MCP tool implementations
- `sample code/` - Reference code for NexusDB and MCP development
  - `sample code\Delphi-MCP-Server-Reference` - MCP Library (reference only)
  - `sample code\NexusDB` - NexusDB examples
  - `sample code\dataset.serialize` - JSON serialization library

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
| `execute_query` | Execute SELECT queries, returns JSON results |
| `get_table_schema` | Get detailed schema for a specific table |

### Data Manipulation (Phase 3)
| Tool | Description |
|------|-------------|
| `execute_sql` | Execute INSERT/UPDATE/DELETE statements |
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

### Table Maintenance (Phase 5)
| Tool | Description |
|------|-------------|
| `empty_table` | Delete all records from a table (keeps structure) |
| `pack_table` | Compact table to reclaim deleted space |
| `reindex_table` | Rebuild an index |
| `recover_table` | Attempt to recover records from broken table |
| `change_password` | Change table password |
| `get_autoinc_value` | Get next auto-increment value |

### Transactions (Phase 6)
| Tool | Description |
|------|-------------|
| `batch_execute` | Execute multiple SQL statements in a single transaction |

### Utility (Phase 7)
| Tool | Description |
|------|-------------|
| `count_records` | Get record count using table metadata (fast, no scan) |
| `list_indexes` | List all indexes on a table |
| `explain_query` | Show query execution plan (standard or verbose mode) |

**batch_execute usage:**
```json
{
  "statements": ["SELECT * FROM Orders", "SELECT * FROM Inventory"],
  "snapshot": true
}
```
- Supports SELECT, INSERT, UPDATE, DELETE
- All statements succeed together or all are rolled back
- `snapshot`: Use snapshot transaction for consistent point-in-time reads (default: false)
- SELECT results include `data` array; non-SELECT results include `rowsAffected`

## NexusDB-Specific Notes

### SQL Syntax Differences
- DROP INDEX: `DROP INDEX "tablename"."indexname"` (not `ON` syntax)
- RENAME TABLE: `ALTER TABLE "old" RENAME TO "new" RESTRICT`
- System tables: `#TABLES`, `#FIELDS`, `#INDEXES` (column names have underscores like `TABLE_NAME`)

### Schema Operations
- Use `TnxDataDictionary` for schema manipulation (faster than SQL)
- Restructure via `database.RestructureTableEx()` with `TnxTableMapperDescriptor`
- Table passwords: Use `SET PASSWORDS ADD 'password'` after connection

### Field Types
Supported types for create_table/add_column:
`AutoInc`, `ShortString`, `WideString`, `Integer`, `Int64`, `Word`, `Byte`, `Boolean`, `Float`, `Currency`, `DateTime`, `Date`, `Time`, `Blob`, `Memo`

### Default Value Types
For add_column: `CurrentDateTime`, `CurrentUser`

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

```pascal
// Example: Get execution plan
nxQuery1.SQL.Text := '#L+ SELECT * FROM Orders WHERE Status = ''Active''';
nxQuery1.Prepare;
// nxQuery1.Log now contains execution plan

// Example: Disable index optimization for testing
nxQuery1.SQL.Text := '#I- SELECT * FROM LargeTable WHERE ID > 100';
```

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
