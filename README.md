# nxmcp - NexusDB MCP Server

An MCP (Model Context Protocol) server that enables AI assistants to interact with NexusDB databases. Built with Delphi, this server exposes NexusDB operations as MCP tools and resources.

## Features

* **Query Execution** - Run SELECT queries and retrieve results as JSON
* **Data Manipulation** - Insert, update, and delete records
* **Schema Management** - Create tables, add columns, manage indexes
* **Discovery** - List tables, view schemas, get table structures

## Requirements

* Delphi (RAD Studio 13) with NexusDB Komponente
* NexusDB NXserver running and accessible
* https://github.com/GDKsoftware/Delphi-MCP-Server
* https://github.com/viniciussanchez/dataset-serialize
* Windows OS

## Configuration

Edit `Source/nxconfig.ini` and put it next to the executable before running:

```ini
\[Connection]
ServerHost=localhost
ServerPort=16000

\[Database]
AliasName=YourDatabaseAlias
TablePassword=optional\_table\_password

\[Authentication]
Username=your\_username
Password=your\_password

\[Options]
AutoConnect=1
Timeout=30000
```

Edit `Source/settings.ini` and put it next to the executable before running:

```ini
; for a detailed example check https://github.com/GDKsoftware/Delphi-MCP-Server
\[Server]
Port=3000
Host=localhost
Name=nxmcp
Version=1.0.0
Endpoint=/mcp
; Server configuration=
\[CORS]
Enabled=1
AllowedOrigins=http://localhost,http://127.0.0.1,https://localhost,https://127.0.0.1
; Comma-separated list of allowed origins=
; Cross-Origin Resource Sharing configuration=
\[SSL]
Enabled=0
CertFile=
KeyFile=
RootCertFile=
; SSL/TLS configuration (optional)=
```

## Building

1. Open `Source/nxmcp.dpr` in Delphi
2. Ensure NexusDB components and the MCP library are in your search path
3. Build the project (Ctrl+F9)

## Running

```
nxmcp.exe
```

The server starts on `http://localhost:3000/mcp` by default.

## Available Tools

### Query \& Discovery

| Tool | Description | Parameters |
|------|-------------|------------|
| `execute\_query` | Run SELECT queries | `sql` |
| `get\_table\_schema` | Get table structure | `tableName` |

### Data Manipulation

| Tool | Description | Parameters |
|------|-------------|------------|
| `get\_table\_data` | Read table data with pagination | `tableName`, `maxRows?`, `offset?`, `orderBy?` |
| `insert\_record` | Insert a new record | `tableName`, `data` (JSON string) |
| `update\_records` | Update matching records | `tableName`, `data` (JSON string), `whereClause` |
| `delete\_records` | Delete matching records | `tableName`, `whereClause` |
| `execute\_sql` | Run INSERT/UPDATE/DELETE | `sql` |

### Schema Management

| Tool | Description | Parameters |
|------|-------------|------------|
| `create\_table` | Create a new table | `tableName`, `columns` (JSON array) |
| `drop\_table` | Delete a table | `tableName` |
| `copy\_table` | Clone a table | `sourceTable`, `targetTable`, `copyData?` |
| `rename\_table` | Rename a table | `oldName`, `newName` |
| `add\_column` | Add a column | `tableName`, `columnName`, `columnType`, `size?`, `defaultValueType?` |
| `drop\_column` | Remove a column | `tableName`, `columnName` |
| `modify\_column` | Modify a column | `tableName`, `columnName`, `newType?`, `newSize?`, `newName?` |
| `create\_index` | Create an index | `tableName`, `indexName`, `columns`, `unique?` |
| `drop\_index` | Remove an index | `tableName`, `indexName` |

### Table Maintenance

| Tool | Description | Parameters |
|------|-------------|------------|
| `empty\_table` | Delete all records (keeps structure) | `tableName` |
| `pack\_table` | Compact table, reclaim deleted space | `tableName` |
| `reindex\_table` | Rebuild an index | `tableName`, `indexName` |
| `recover\_table` | Recover records from broken table | `tableName` |
| `change\_password` | Change table password | `tableName`, `oldPassword`, `newPassword` |
| `get\_autoinc\_value` | Get next auto-increment value | `tableName` |

### Transactions

| Tool | Description | Parameters |
|------|-------------|------------|
| `batch\_execute` | Execute multiple SQL in one transaction | `statements` (JSON array), `snapshot?` |

### Utility

| Tool | Description | Parameters |
|------|-------------|------------|
| `count\_records` | Fast record count via metadata | `tableName` |
| `list\_indexes` | List all indexes on a table | `tableName` |
| `explain\_query` | Show query execution plan | `sql` |

## Available Resources

| URI | Description |
|-----|-------------|
| `nexusdb://server` | Connection status and server info |
| `nexusdb://tables` | List of all tables |
| `nexusdb://schema` | Schema overview with record counts |

## Column Types

For `create\_table` and `add\_column`:

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

For `add\_column`:

* `CurrentDateTime` - Auto-populate with current timestamp
* `CurrentUser` - Auto-populate with current user

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
  "name": "create\_table",
  "arguments": {
    "tableName": "Customers",
    "columns": "\[{\\"name\\":\\"ID\\",\\"type\\":\\"AutoInc\\"},{\\"name\\":\\"Name\\",\\"type\\":\\"ShortString\\",\\"size\\":100},{\\"name\\":\\"Email\\",\\"type\\":\\"ShortString\\",\\"size\\":255}]"
  }
}
```

### Insert a record

```json
{
  "name": "insert\_record",
  "arguments": {
    "tableName": "Customers",
    "data": "{\\"Name\\":\\"John Doe\\",\\"Email\\":\\"john@example.com\\"}"
  }
}
```

### Query data

```json
{
  "name": "execute\_query",
  "arguments": {
    "sql": "SELECT \* FROM Customers WHERE Name LIKE 'J%'"
  }
}
```

## Integration with Claude Desktop

Add to your Claude Desktop MCP configuration:

```json
{
  "mcpServers": {
    "nxmcp": {
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

## License

MIT License

Copyright (c) 2025 Dr. Pfau Fernwirktechnik GmbH

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.