# Changelog

Notable changes to nxmcp.

## [5.0.0.0] - 2026-08-01

Major version because tool contracts are now enforced: input that earlier builds accepted
is rejected, and `explain_query` no longer persists the statement it explains.

### Security

Tools that promise to read, or to act on one named table, could be made to do neither.
Reported by a user embedding nxmcp in their own product; all four vectors were reproduced
against a live server before fixing. Anyone running an earlier build should update.

* **`execute_query` executed arbitrary statements.** Validation was
  `StripSwitches(sql).ToUpper.StartsWith('SELECT')`, and NexusDB executes a
  semicolon-separated batch submitted as one `SQL.Text` in a single call. So
  `SELECT * FROM t; DELETE FROM t` returned a normal-looking result set *and* emptied the
  table. `SELECT * INTO t2 FROM t1` also passed, and creates and populates a table.
* **`explain_query` validated nothing at all** and called `Open`, so a bare
  `DELETE FROM t` executed. This was the widest hole - no semicolon trick needed.
* **`get_table_data` / `get_table_schema` concatenated the table name** into SQL inside
  double quotes with no validation, so a name containing `"` closed the quote and appended
  a second statement.
* **`insert_record` / `update_records` / `delete_records` / `drop_index`** concatenated
  table, column and index names (and, for the record tools, JSON keys) the same way.

Fixes, in `nxmcp.SqlUtils.pas`:

* `AnalyzeSql` classifies a statement using **NexusDB's own SQL lexer**
  (`TnxSQLTokenizer`, `nxSQLTok.pas`) rather than scanning text. Comments, string literals
  and quoted identifiers are distinct token types, so none of them can hide a `;` or an
  `INTO`, and a column legitimately named `"into"` is not a false positive. Anything the
  lexer cannot tokenize fails closed.
* `CheckTableName` / `CheckIdentifier` validate against the engine's own
  `nxCheckValidTableName` / `nxCheckValidIdent`. Their character set (`nxcValidIdentChars`,
  `nxllConst.pas`) excludes `"` and `;`. Validation rather than escaping is not a
  shortcut - NexusDB has no escape for a quote inside a quoted identifier at all
  (`SELECT 1 AS "a""b"` is a syntax error), so there is nothing to escape to. Meta tables,
  memory/temp tables (`<name>`), child tables (`parent:child`) and names with spaces all
  still work.
* `update_records` / `delete_records` validate the **composed** statement, not the WHERE
  fragment, which keeps subselects working (`WHERE id IN (SELECT ...)`) while rejecting
  `1=1; DROP TABLE other`.

`explain_query` now accepts one SELECT/INSERT/UPDATE/DELETE and rejects DDL. It still
executes the statement, because NexusDB has no non-executing explain - `TnxQuery.Log` is
filled from the execution round trip and `Prepare` alone leaves it empty (verified). Writes
are therefore run inside a transaction that is **always rolled back**, and the response
reports `executed` and `rolledBack`. DDL is rejected because it is not transactional.

`execute_sql` and `batch_execute` are unchanged and remain deliberately unrestricted.

### Changed

* README gained a Security section documenting each tool's contract, how it is enforced,
  and the recommendation to use a rights-restricted NexusDB user when embedding nxmcp in a
  product rather than using it as a dev tool.

## [4.1.0.0] - 2026-08-01

### Added

* **`close_inactive_tables`** (Table Maintenance) — releases the tables *and* folders the
  NexusDB server holds open in its cache for this session
  (`TnxSession.CloseInactiveTables` followed by `CloseInactiveFolders`). Frees server-side
  file handles before backing up, copying or replacing database files. In embedded mode the
  handles released are held by the nxmcp process itself. Takes no parameters.
* **`list_locks`** (Utility) — live lock state from the server's lock meta tables:
  `#TABLE_LOCKS` (record and cursor level) and `#TRANSACTION_LOCKS` (transaction level).
  Parameters: `lockType` (`table` / `transaction` / `all`, default `all`), `tableName`
  filter, `maxRows` (default 500, max 10000).

  Both meta tables only exist on newer NexusDB releases. Instead of failing there,
  `list_locks` returns `"available": false` with an explanation for that lock table. The
  check asks the server — it reads `SELECT METATABLE_NAME FROM #META`, which enumerates the
  meta tables the SQL engine that ran the query actually implements. In remote mode that
  engine lives in `nxServer.exe`, whose version is independent of this client, so a
  client-side check against nxmcp's own constants would be wrong. Any other failure
  (permissions, lost connection) is still raised.

### Required dependency patch — dataset-serialize

**`list_locks` needs a one-line patch in dataset-serialize that is not yet fixed upstream.**
Without it the tool fails whenever locks actually exist.

`TDataSetSerialize.DataSetToJSONObject` in `src/DataSet.Serialize.Export.pas` groups
`ftLongWord` with the plain integer types and reads it via `AsInteger`. Delphi's
`TLongWordField.GetAsInteger` (`Data.DB`) calls `RangeError(Value, 0, High(Integer))` for
values above 2147483647, so serializing such a column raises. `ftLongWord` is the only type
in that case group whose range does not fit in `Integer`.

The lock meta tables expose `SESSION_ID`, `TRANSACTION_CONTEXT_ID`, `DATABASE_ID` and
`CURSOR_ID` as `Word32`, and real session ids routinely exceed the limit (observed here:
4273865552). The same failure affects `execute_query`, `get_table_data` and `batch_execute`
on any table with a large `Word32` value, so this is not specific to the new tool.

Give `ftLongWord` its own branch reading `AsLargeInt` — `Int64` represents the whole
unsigned 32-bit range exactly, so the value stays a JSON number:

```diff
-      TFieldType.ftInteger, TFieldType.ftSmallint, TFieldType.ftAutoInc{$IF NOT DEFINED(FPC)}, TFieldType.ftShortint, TFieldType.ftLongWord, TFieldType.ftWord, TFieldType.ftByte{$ENDIF}:
+      TFieldType.ftInteger, TFieldType.ftSmallint, TFieldType.ftAutoInc{$IF NOT DEFINED(FPC)}, TFieldType.ftShortint, TFieldType.ftWord, TFieldType.ftByte{$ENDIF}:
         Result.{$IF DEFINED(FPC)}Add{$ELSE}AddPair{$ENDIF}(LKey, {$IF DEFINED(FPC)}LField.AsInteger{$ELSE}TJSONNumber.Create(LField.AsInteger){$ENDIF});
+      {$IF NOT DEFINED(FPC)}
+      TFieldType.ftLongWord:
+        Result.AddPair(LKey, TJSONNumber.Create(LField.AsLargeInt));
+      {$ENDIF}
       TFieldType.ftLargeint:
```

Reported upstream as
[viniciussanchez/dataset-serialize#269](https://github.com/viniciussanchez/dataset-serialize/issues/269).
Present in `master` and in releases v.2.7.0 and v.2.6.9. Remove this note once a released
version carries the fix.
