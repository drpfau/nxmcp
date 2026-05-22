# nxmcp - NexusDB MCP Server

An MCP (Model Context Protocol) server that enables AI assistants to interact with NexusDB databases. Built with Delphi, this server exposes NexusDB operations as MCP tools and resources.

## Features

* **Dual Transport** - HTTP and STDIO (for Claude Desktop and other MCP clients)
* **Query Execution** - Run SELECT queries and retrieve results as JSON
* **Data Manipulation** - Insert, update, and delete records
* **Schema Management** - Create tables, add columns, manage indexes
* **Schema Metadata** - Descriptions on tables/columns/indexes, field validators, defaults on existing columns, data policies, audit settings
* **Database Management** - Switch databases and servers at runtime, list aliases
* **Discovery** - List tables, view schemas, get table structures (including descriptions, defaults, validators, policies, audit, and referential-integrity references), list indexes
* **Utility** - Count records, show query execution plan

## Requirements

* Delphi (RAD Studio 13) with NexusDB Komponente
* NexusDB NXserver running and accessible
* https://github.com/GDKsoftware/Delphi-MCP-Server (may have additional depencies)
* https://github.com/viniciussanchez/dataset-serialize
* Windows OS

## Configuration

On first run, `nxmcp.ini` is automatically created next to the executable with default values. Edit it to configure both the NexusDB connection and MCP server:

```ini
[Connection]
; NXserver host address
ServerHost=localhost
; NXserver port (default: 16000)
ServerPort=16000

[Database]
; Database alias as configured on the NXserver
AliasName=YourAlias
; Table passwords, comma separated (leave empty if not used)
TablePassword=

[Authentication]
; NexusDB username
Username=your_username
; NexusDB password
Password=your_password

[Options]
; Automatically connect on startup (1=yes, 0=no)
AutoConnect=1
; Connection timeout in milliseconds
Timeout=3000

[Server]
; MCP server configuration
Port=3000
Host=localhost
Name=nxmcp
Version=1.0.0
Endpoint=/mcp

[CORS]
; Cross-Origin Resource Sharing configuration
Enabled=1
; Comma-separated list of allowed origins
AllowedOrigins=http://localhost,http://127.0.0.1,https://localhost,https://127.0.0.1

[SSL]
; SSL/TLS configuration (optional)
Enabled=0
CertFile=
KeyFile=
RootCertFile=
```  


## Building

1. Open `Source/nxmcp.dpr` in Delphi
2. Ensure NexusDB components and the MCP library are in your search path
3. Build the project (Ctrl+F9)

## Running

### HTTP Transport (default)

```
nxmcp.exe
```

The server starts on `http://localhost:3000/mcp` by default.

### STDIO Transport

```
nxmcp.exe --stdio
```

Uses stdin/stdout for JSON-RPC communication. Required for Claude Desktop and other MCP clients that use the STDIO transport.

## Available Tools

### Query \& Discovery

| Tool | Description | Parameters |
|------|-------------|------------|
| `execute_query` | Run SELECT queries | `sql` |
| `get_table_schema` | Get table structure | `tableName` |

### Data Manipulation

| Tool | Description | Parameters |
|------|-------------|------------|
| `get_table_data` | Read table data with pagination | `tableName`, `maxRows?`, `offset?`, `orderBy?` |
| `insert_record` | Insert a new record | `tableName`, `data` (JSON string) |
| `update_records` | Update matching records | `tableName`, `data` (JSON string), `whereClause` |
| `delete_records` | Delete matching records | `tableName`, `whereClause` |
| `execute_sql` | Run INSERT/UPDATE/DELETE | `sql` |

### Schema Management

| Tool | Description | Parameters |
|------|-------------|------------|
| `create_table` | Create a new table | `tableName`, `columns` (JSON array) |
| `drop_table` | Delete a table | `tableName` |
| `copy_table` | Clone a table | `sourceTable`, `targetTable`, `copyData?` |
| `rename_table` | Rename a table | `oldName`, `newName` |
| `add_column` | Add a column | `tableName`, `columnName`, `columnType`, `size?`, `defaultValueType?` |
| `drop_column` | Remove a column | `tableName`, `columnName` |
| `modify_column` | Modify a column | `tableName`, `columnName`, `newType?`, `newSize?`, `newName?` |
| `create_index` | Create an index | `tableName`, `indexName`, `columns`, `unique?` |
| `drop_index` | Remove an index | `tableName`, `indexName` |

### Schema Metadata

| Tool | Description | Parameters |
|------|-------------|------------|
| `set_table_description` | Set or clear the description (comment) on a table | `tableName`, `description` |
| `set_column_description` | Set or clear the description on a column | `tableName`, `columnName`, `description` |
| `set_index_description` | Set or clear the description on an index | `tableName`, `indexName`, `description` |
| `set_field_validator` | Add/remove a server-side validator on a column (`minmax` or `nochange`, or `none` to remove) | `tableName`, `columnName`, `validator`, `minValue?`, `maxValue?`, `minNull?`, `maxNull?` |
| `set_column_default` | Add, replace, or clear the default-value descriptor on an existing column | `tableName`, `columnName`, `defaultType` (`none`/`CurrentDateTime`/`CurrentUser`/`Constant`), `constantValue?`, `applyAt?`, `applyOnInsert?`, `applyOnModify?`, `overwriteNonNull?` |
| `set_data_policies` | Set/clear table-level data policies: deny insert/modify/delete and enforce min/max record counts | `tableName`, `clear?`, `denyInsert?`, `denyModify?`, `denyDelete?`, `minRecordCount?`, `maxRecordCount?` |
| `set_audit` | Enable/disable audit-trail logging and BLOB inclusion (requires a server-side audit monitor for rows to be recorded) | `tableName`, `clear?`, `useAudit?`, `includeBlobFields?` |

`get_table_schema` reads directly from the table's `TnxDataDictionary` and surfaces description, per-column descriptions/defaults/validators, per-index descriptions, data policies, audit settings, and (read-only) referential-integrity references. `list_indexes` also includes each index's description.

### Table Maintenance

| Tool | Description | Parameters |
|------|-------------|------------|
| `empty_table` | Delete all records (keeps structure) | `tableName` |
| `pack_table` | Compact table, reclaim deleted space | `tableName` |
| `reindex_table` | Rebuild an index | `tableName`, `indexName` |
| `recover_table` | Recover records from broken table | `tableName` |
| `change_password` | Change table password | `tableName`, `oldPassword`, `newPassword` |
| `get_autoinc_value` | Get next auto-increment value | `tableName` |

### Transactions

| Tool | Description | Parameters |
|------|-------------|------------|
| `batch_execute` | Execute multiple SQL in one transaction | `statements` (JSON array), `snapshot?` |

### Utility

| Tool | Description | Parameters |
|------|-------------|------------|
| `count_records` | Fast record count via metadata | `tableName` |
| `list_indexes` | List all indexes on a table | `tableName` |
| `explain_query` | Show query execution plan | `sql` |

### Database Management

| Tool | Description | Parameters |
|------|-------------|------------|
| `list_aliases` | List available database aliases on the server | _(none)_ |
| `switch_database` | Switch to a different database alias | `aliasName`, `tablePassword?` |
| `switch_server` | Switch to a different NexusDB server | `serverHost`, `serverPort?`, `aliasName?`, `tablePassword?` |

## Available Resources

| URI | Description |
|-----|-------------|
| `nexusdb://server` | Connection status and server info |
| `nexusdb://tables` | List of all tables |
| `nexusdb://schema` | Schema overview with record counts |

## Column Types

For `create_table` and `add_column`:

* `AutoInc` - Auto-incrementing integer
* `ShortString` - ANSI string (specify size)
* `WideString` - Unicode string (specify size)
* `Integer` - 32-bit integer
* `Int64` - 64-bit integer
* `Word` - 16-bit unsigned
* `Byte` - 8-bit unsigned
* `Boolean` - True/False
* `Float` - Double precision
* `Currency` - Currency type
* `DateTime` - Date and time
* `Date` - Date only
* `Time` - Time only
* `Blob` - Binary data
* `Memo` - Large text

## Default Value Types

For `add_column` and `set_column_default`:

* `CurrentDateTime` - Auto-populate with current timestamp
* `CurrentUser` - Auto-populate with current user
* `Constant` - Literal value (`set_column_default` only; pass via `constantValue`)
* `none` - Remove any existing default (`set_column_default` only)

## Statement Switches

Prefix SQL statements with switches to control execution:

| Switch | Syntax | Purpose |
|--------|--------|---------|
| `#T` | `#T 5000` | Timeout in milliseconds |
| `#I` | `#I-` | Disable index optimization |
| `#S` | `#S-` | Disable query simplification |
| `#L` | `#L+` | Enable query logging (used by `explain\_query`) |
| `#B` | `#B+` | Force BLOB copying |

Example: `#T 10000 SELECT * FROM LargeTable WHERE Status = 'Active'`

## Example Usage

### Create a table

```json
{
  "name": "create_table",
  "arguments": {
    "tableName": "Customers",
    "columns": "[{"name":"ID","type":"AutoInc"},{"name":"Name","type":"ShortString","size":100},{"name":"Email","type":"ShortString","size":255}]"
  }
}
```

### Insert a record

```json
{
  "name": "insert_record",
  "arguments": {
    "tableName": "Customers",
    "data": "{"Name":"John Doe","Email":"john@example.com"}"
  }
}
```

### Query data

```json
{
  "name": "execute_query",
  "arguments": {
    "sql": "SELECT * FROM Customers WHERE Name LIKE 'J%'"
  }
}
```

## Integration with Claude Code

### HTTP Transport
```bash
claude mcp add --transport http nxmcp http://localhost:3000/mcp
```

### STDIO Transport
```bash
claude mcp add nxmcp -- /path/to/nxmcp.exe --stdio
```

## Integration with Claude Desktop

Add to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "nxmcp": {
      "command": "C:\\path\\to\\nxmcp.exe",
      "args": ["--stdio"]
    }
  }
}
```


## License

The MIT License (MIT)

Copyright (c) 2025 Dr. Pfau Fernwirktechnik GmbH

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

