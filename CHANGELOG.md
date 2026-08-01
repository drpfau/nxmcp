# Changelog

Notable changes to nxmcp.

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
