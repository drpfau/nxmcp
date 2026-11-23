unit nxmcp.Tool.RunScript;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the run_script tool
  /// </summary>
  TRunScriptParams = class
  private
    FSql: string;
    FTransaction: string;
    FParams: string;
    FTimeoutMs: Integer;
    FMaxRows: Integer;
    FBlobFormat: string;
  public
    [SchemaDescription('Complete SQL script: any number of statements separated by semicolons, executed as ONE ' +
      'batch, so #temp tables, DECLAREd variables and cursors live for the whole script. The result set of ' +
      'the last statement is returned.')]
    property Sql: string read FSql write FSql;

    [Optional]
    [SchemaDescription('"rollback" (default): run inside a transaction that is always rolled back, also on ' +
      'error. "commit": run inside a transaction committed on success, rolled back on error. "none": no ' +
      'explicit transaction - needed for DDL (e.g. CREATE TABLE ##x), which NexusDB refuses inside a ' +
      'transaction. In every mode, transactions the script itself leaves open are rolled back.')]
    property Transaction: string read FTransaction write FTransaction;

    [Optional]
    [SchemaDescription('JSON array binding values to :name placeholders in the script, same format as ' +
      'execute_query, e.g. [{"name":"id","value":42},{"name":"since","value":"2024-01-15","type":"date"}].')]
    property Params: string read FParams write FParams;

    [Optional]
    [SchemaDescription('Timeout in milliseconds for the whole script (default: the database Timeout). ' +
      'A "#T ms" switch only works at the very start of the script.')]
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;

    [Optional]
    [SchemaDescription('Maximum number of rows to return (default: 1000, max: 100000)')]
    property MaxRows: Integer read FMaxRows write FMaxRows;

    [Optional]
    [SchemaDescription('How BLOB/graphic/binary values are returned: "base64" (default) or "md5" ' +
      '({"bytes": n, "md5": "..."}).')]
    property BlobFormat: string read FBlobFormat write FBlobFormat;
  end;

  /// <summary>
  /// MCP Tool that runs a whole multi-statement SQL script and returns the last result set.
  /// Writes are allowed; rolled back by default (transaction="rollback").
  /// </summary>
  TRunScriptTool = class(TMCPToolBase<TRunScriptParams>)
  protected
    function ExecuteWithParams(const Params: TRunScriptParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.StrUtils,
  System.Diagnostics,
  System.NetEncoding,
  System.Hash,
  System.Math,
  Data.DB,
  Data.FmtBcd,
  MCPServer.Registration,
  MCPServer.Errors,
  nxmcp.NexusErrors,
  nxmcp.QueryParams,
  dmnx;

type
  TScriptTransactionMode = (stmRollback, stmCommit, stmNone);

const
  cTransactionModeNames: array[TScriptTransactionMode] of string = ('rollback', 'commit', 'none');
  // Bound on the cleanup loop: each Rollback ends one nesting level, and a script that opened
  // more levels than this is not a realistic case - stop rather than spin on a failing server.
  cMaxRollbackLevels = 64;
  cNoAutoCommitOnDDL = '#OPT::STATEMENT::AUTOCOMMITONDDL=''0'' ';

function ParseTransactionMode(const AValue: string): TScriptTransactionMode;
var
  LMode: TScriptTransactionMode;
begin
  if Trim(AValue) = '' then
    Exit(stmRollback);
  for LMode := Low(TScriptTransactionMode) to High(TScriptTransactionMode) do
    if SameText(Trim(AValue), cTransactionModeNames[LMode]) then
      Exit(LMode);
  raise Exception.Create('Invalid transaction "' + AValue + '". Use rollback, commit or none.');
end;

function BlobToJSON(const ABytes: TBytes; AAsMd5: Boolean): TJSONValue;
var
  LEncoding: TBase64Encoding;
  LHash: THashMD5;
  LObj: TJSONObject;
begin
  if AAsMd5 then
  begin
    LHash := THashMD5.Create;
    LHash.Update(ABytes);
    LObj := TJSONObject.Create;
    LObj.AddPair('bytes', TJSONNumber.Create(Length(ABytes)));
    LObj.AddPair('md5', LHash.HashAsString);
    Exit(LObj);
  end;

  // CharsPerLine = 0: the default TNetEncoding.Base64 inserts a line break every 76 chars.
  LEncoding := TBase64Encoding.Create(0);
  try
    Result := TJSONString.Create(LEncoding.EncodeBytesToString(ABytes));
  finally
    LEncoding.Free;
  end;
end;

function FieldToJSON(AField: TField; ABlobAsMd5: Boolean): TJSONValue;
begin
  if AField.IsNull then
    Exit(TJSONNull.Create);

  // Typed and locale-independent: numbers as numbers, ISO 8601 dates without offset (NexusDB
  // stores wall-clock values), so a caller can compare results without a per-column type map.
  case AField.DataType of
    ftSmallint, ftInteger, ftWord, ftAutoInc, ftLargeint, ftShortint, ftByte, ftLongWord:
      Result := TJSONNumber.Create(AField.AsLargeInt);
    ftCurrency:
      // The Currency overload formats the scaled value itself (FloatToText fvCurrency, System.JSON), so
      // serialization adds no rounding. The value is already a Double, though: TCurrencyField is a
      // TFloatField and TField.GetAsCurrency is GetAsFloat (Data.DB), so ~15 significant digits.
      Result := TJSONNumber.Create(AField.AsCurrency);
    ftFloat, ftSingle, ftExtended:
      Result := TJSONNumber.Create(AField.AsFloat);
    ftBCD, ftFMTBcd:
      Result := TJSONNumber.Create(BcdToStr(AField.AsBCD, TFormatSettings.Invariant));
    ftBoolean:
      Result := TJSONBool.Create(AField.AsBoolean);
    ftDate:
      Result := TJSONString.Create(FormatDateTime('yyyy-mm-dd', AField.AsDateTime, TFormatSettings.Invariant));
    ftTime:
      Result := TJSONString.Create(FormatDateTime('hh:nn:ss.zzz', AField.AsDateTime, TFormatSettings.Invariant));
    ftDateTime, ftTimeStamp:
      Result := TJSONString.Create(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', AField.AsDateTime, TFormatSettings.Invariant));
    ftBlob, ftGraphic, ftBytes, ftVarBytes, ftTypedBinary:
      Result := BlobToJSON(AField.AsBytes, ABlobAsMd5);
    ftWideMemo, ftWideString, ftFixedWideChar:
      Result := TJSONString.Create(AField.AsWideString);
  else
    // Strings, memos, GUIDs (braced, as NexusDB returns them) and anything not listed above.
    Result := TJSONString.Create(AField.AsString);
  end;
end;

function ColumnsToJSON(ADataSet: TDataSet): TJSONArray;
var
  LField: TField;
  LCol: TJSONObject;
begin
  Result := TJSONArray.Create;
  for LField in ADataSet.Fields do
  begin
    LCol := TJSONObject.Create;
    LCol.AddPair('name', LField.FieldName);
    LCol.AddPair('type', FieldTypeNames[LField.DataType]);
    if LField.Size > 0 then
      LCol.AddPair('size', TJSONNumber.Create(LField.Size));
    Result.AddElement(LCol);
  end;
end;

// InTransaction asks the server (TransactionGetLevel), so it also sees transactions the script
// opened itself with START TRANSACTION.
function InTransactionNow: Boolean;
var
  LResult: Boolean;
begin
  LResult := False;
  nxmodule.ExecuteWithoutRetry(
    procedure
    begin
      LResult := nxmodule.nxDatabase1.InTransaction;
    end);
  Result := LResult;
end;

// Rolls back every open level (ours and any the script left open); returns True if any was open.
// Probe and rollbacks share one recovery boundary, like every other round-trip of this tool.
function RollbackAll: Boolean;
var
  LAnyOpen: Boolean;
begin
  LAnyOpen := False;
  nxmodule.ExecuteWithoutRetry(
    procedure
    var
      LLevel: Integer;
    begin
      LLevel := 0;
      while nxmodule.nxDatabase1.InTransaction and (LLevel < cMaxRollbackLevels) do
      begin
        LAnyOpen := True;
        nxmodule.nxDatabase1.Rollback;
        Inc(LLevel);
      end;
      if nxmodule.nxDatabase1.InTransaction then
        raise Exception.CreateFmt('Could not roll back the open transactions: still in a transaction ' +
          'after %d rollbacks.', [cMaxRollbackLevels]);
    end);
  Result := LAnyOpen;
end;

{ TRunScriptTool }

constructor TRunScriptTool.Create;
begin
  inherited;
  FName := 'run_script';
  FTitle := 'Run SQL Script';
  FDescription := 'Run a complete multi-statement SQL script (SELECT ... INTO #temp chains, DECLARE/cursor/' +
                  'WHILE loops, START TRANSACTION blocks, DML, DDL) as ONE batch and return the result set ' +
                  'of the last statement as typed JSON: columns (name, Delphi field type) and rows as arrays in column ' +
                  'order. WRITES ARE ALLOWED. By default everything runs inside a transaction that is always ' +
                  'rolled back (transaction="rollback"); use "commit" to keep the changes, or "none" for DDL. ' +
                  'A failing script is a tool error (isError) whose text is the JSON object ' +
                  '{"success": false, "error": "...", "errorCode": n, "rolledBack": bool} with the full NexusDB message; ' +
                  'invalid parameters are plain tool errors. ' +
                  'For a single read prefer execute_query.';
end;

function TRunScriptTool.ExecuteWithParams(const Params: TRunScriptParams): string;
var
  LSql: string;
  LMode: TScriptTransactionMode;
  LMaxRows: Integer;
  LBlobAsMd5: Boolean;
  LStopwatch: TStopwatch;
  LOldTimeout: Integer;
  LResultObj: TJSONObject;
  LHasResultSet: Boolean;
  LLeftOpen: Boolean;
  LInTransaction: Boolean;
  LStaleRolledBack: Boolean;
  LRolledBack: Boolean;
  LExecuting: Boolean;
  LCommitting: Boolean;
  LRollbackError: string;
  LErrorObj: TJSONObject;
  LErrorJson: string;
  LCode: Integer;
begin
  // Scripts read from a UTF-8 file with a BOM arrive with a leading U+FEFF, which NexusDB does not
  // skip: it breaks a leading "--" comment and the first statement then fails with a syntax error.
  LSql := Params.Sql;
  if LSql.StartsWith(#$FEFF) then
    Delete(LSql, 1, 1);
  if Trim(LSql) = '' then
    raise Exception.Create('SQL script cannot be empty');

  LMode := ParseTransactionMode(Params.Transaction);

  // AUTOCOMMITONDDL makes NexusDB commit the active transaction before each DDL statement and start
  // a new one (verified: an INSERT before a CREATE TABLE survived "rollback" mode), which would make
  // rolledBack/committed a false claim. A bare COMMIT in the script cannot do this - NexusDB refuses
  // it with "No explicit transaction is currently in progress".
  if (LMode <> stmNone) and (Pos('AUTOCOMMITONDDL', UpperCase(LSql)) > 0) then
    raise Exception.Create('AUTOCOMMITONDDL commits the transaction before each DDL statement, so it ' +
      'cannot be used with transaction="' + cTransactionModeNames[LMode] + '". Use transaction="none".');

  if SameText(Trim(Params.BlobFormat), 'md5') then
    LBlobAsMd5 := True
  else if (Trim(Params.BlobFormat) = '') or SameText(Trim(Params.BlobFormat), 'base64') then
    LBlobAsMd5 := False
  else
    raise Exception.Create('Invalid blobFormat "' + Params.BlobFormat + '". Use base64 or md5.');

  if Params.MaxRows > 0 then
    LMaxRows := Min(Params.MaxRows, 100000)
  else
    LMaxRows := 1000;

  if not Assigned(nxmodule) or not nxmodule.EnsureConnection then
    raise Exception.Create('Not connected to NexusDB');

  // A transaction left open by an earlier failure would silently absorb this script's commit. Tool
  // calls are serialized by the execution gate and no tool keeps a transaction across calls, so one
  // open at entry is always a leftover: roll it back (refusing instead would be a dead end - no tool
  // can end it). InTransactionNow/RollbackAll run inside a recovery boundary: a dead socket retires
  // the session there instead of failing every later call on the same stale connection.
  LStaleRolledBack := InTransactionNow and RollbackAll;

  LResultObj := nil;
  LExecuting := False;
  LCommitting := False;
  LRolledBack := False;
  LHasResultSet := False;
  LInTransaction := False;
  LOldTimeout := nxmodule.nxQuery1.Timeout;
  LStopwatch := TStopwatch.StartNew;
  try
    try
      // A script may write, so it is never replayed: ExecuteWithoutRetry retires a poisoned session
      // but reports the original failure instead of running the script a second time.
      nxmodule.ExecuteWithoutRetry(
        procedure
        var
          LRows: TJSONArray;
          LRow: TJSONArray;
          LField: TField;
          LRowCount: Integer;
        begin
          if LMode <> stmNone then
            nxmodule.nxDatabase1.StartTransaction(False);

          nxmodule.nxQuery1.Close;
          // Setting SQL.Text carries old values onto same-named params (TParams.AssignValues).
          nxmodule.nxQuery1.Params.Clear;
          // AUTOCOMMITONDDL can also be inherited, set at SESSION/DATABASE scope by an earlier call (the
          // text check above only sees this script). Options resolve from the statement outwards, so
          // a statement-scoped '0' wins. Prefixed on line 1 so later line numbers in errors are
          // unchanged; only a position reported on line 1 shifts.
          if LMode <> stmNone then
            nxmodule.nxQuery1.SQL.Text := cNoAutoCommitOnDDL + LSql
          else
            nxmodule.nxQuery1.SQL.Text := LSql;
          ApplyJsonParamsToQuery(nxmodule.nxQuery1, Params.Params);
          if Params.TimeoutMs > 0 then
            nxmodule.nxQuery1.Timeout := Params.TimeoutMs;

          // Open executes the batch once. When the last statement returns no cursor (DML, DDL),
          // TnxDataset.OpenCursor executes without raising and simply creates no fields, and
          // RowsAffected holds the count instead - so one call covers both cases with no replay.
          LExecuting := True;
          nxmodule.nxQuery1.Open;

          LResultObj := TJSONObject.Create;
          LHasResultSet := nxmodule.nxQuery1.FieldCount > 0;
          if LHasResultSet then
          begin
            LResultObj.AddPair('columns', ColumnsToJSON(nxmodule.nxQuery1));
            LRows := TJSONArray.Create;
            LResultObj.AddPair('rows', LRows);
            LRowCount := 0;
            nxmodule.nxQuery1.First;
            while (not nxmodule.nxQuery1.Eof) and (LRowCount < LMaxRows) do
            begin
              LRow := TJSONArray.Create;
              LRows.AddElement(LRow);
              for LField in nxmodule.nxQuery1.Fields do
                LRow.AddElement(FieldToJSON(LField, LBlobAsMd5));
              Inc(LRowCount);
              nxmodule.nxQuery1.Next;
            end;
            LResultObj.AddPair('rowCount', TJSONNumber.Create(LRowCount));
            LResultObj.AddPair('maxRows', TJSONNumber.Create(LMaxRows));
            LResultObj.AddPair('truncated', TJSONBool.Create(not nxmodule.nxQuery1.Eof));
          end
          else
          begin
            // -1 is NexusDB's "no count was sent" sentinel, not a count.
            if nxmodule.nxQuery1.RowsAffected >= 0 then
              LResultObj.AddPair('rowsAffected', TJSONNumber.Create(nxmodule.nxQuery1.RowsAffected))
            else
              LResultObj.AddPair('rowsAffected', TJSONNull.Create);
          end;
          nxmodule.nxQuery1.Close;
          // The script's timeout must not also govern the commit/rollback that follows.
          nxmodule.nxQuery1.Timeout := LOldTimeout;
        end);

      // Finish the transaction. Read the result first: rows read after a rollback would be gone.
      // Safety net. No known script statement ends our transaction: a bare COMMIT/ROLLBACK only acts
      // on a level the script opened with START TRANSACTION (otherwise NexusDB refuses it), and
      // AUTOCOMMITONDDL is rejected above. Should something still end it, there is nothing of ours
      // left to finish and changes may be committed - say so, never claim a rollback that did not happen.
      if LMode <> stmNone then
      begin
        LInTransaction := InTransactionNow;
        if not LInTransaction then
          LResultObj.AddPair('warning', 'The transaction run_script started was ended during the script, ' +
            'so changes made before that point may have been committed.');
      end;

      case LMode of
        stmRollback:
          LResultObj.AddPair('rolledBack', TJSONBool.Create(RollbackAll));
        stmCommit:
          if LInTransaction then
          begin
            LCommitting := True;
            nxmodule.ExecuteWithoutRetry(
              procedure
              begin
                nxmodule.nxDatabase1.Commit;
              end);
            // Still in a transaction: the script left a level of its own open, so the Commit above
            // only closed that inner level and our outer one would be committed by nobody.
            // The outcome stays "unknown" until this probe returns: if the script left a level open, the
            // Commit only closed that inner level and nothing is durable; if not, it all is. A lost
            // session in between leaves no way to tell, so LCommitting is cleared only afterwards.
            LRolledBack := RollbackAll;
            LCommitting := False;
            if LRolledBack then
              raise Exception.Create('The script left a transaction open, so nothing was committed ' +
                '(all levels were rolled back). Close every START TRANSACTION the script opens.');
            LResultObj.AddPair('committed', TJSONBool.Create(True));
          end
          else
            LResultObj.AddPair('committed', TJSONBool.Create(False));
        stmNone:
          begin
            LLeftOpen := RollbackAll;
            if LLeftOpen then
              LResultObj.AddPair('openTransactionRolledBack', TJSONBool.Create(True));
          end;
      end;

      if LStaleRolledBack then
        LResultObj.AddPair('staleTransactionRolledBack', TJSONBool.Create(True));
      LResultObj.AddPair('success', TJSONBool.Create(True));
      LResultObj.AddPair('hasResultSet', TJSONBool.Create(LHasResultSet));
      LResultObj.AddPair('transaction', cTransactionModeNames[LMode]);
      LResultObj.AddPair('elapsedMs', TJSONNumber.Create(LStopwatch.ElapsedMilliseconds));
      Result := LResultObj.ToJSON;
    except
      on E: Exception do
      begin
        // Never commit after a failure, in any mode. Cleanup is best-effort and must not replace
        // the script error, which is what the caller compares against.
        try
          nxmodule.nxQuery1.Close;
        except
        end;
        LRollbackError := '';
        // Keep a rollback already done on the commit path ("script left a transaction open").
        try
          if RollbackAll then
            LRolledBack := True;
        except
          on LCleanupError: Exception do
            LRollbackError := LCleanupError.Message;
        end;

        LErrorObj := TJSONObject.Create;
        try
          LErrorObj.AddPair('success', TJSONBool.Create(False));
          LErrorObj.AddPair('error', E.Message);
          LCode := NexusErrorCode(E);
          if LCode <> 0 then
            LErrorObj.AddPair('errorCode', TJSONNumber.Create(LCode));
          // rolledBack is false also when the failure already ended the transaction (e.g. a lost
          // session); in no case did the tool commit anything after the error.
          LErrorObj.AddPair('rolledBack', TJSONBool.Create(LRolledBack));
          // A lost/timed-out/re-entered session was retired by the recovery boundary: the server
          // discards its open transaction, except that a Commit whose reply was lost may have landed.
          // Say so explicitly (as batch_execute does), so a caller does not blindly re-run the script.
          if IsConnectionLostError(E) or IsTimeoutError(E) or IsReenteredError(E) then
          begin
            LErrorObj.AddPair('transactionState', 'sessionRetired');
            if LCommitting then
              LErrorObj.AddPair('commitOutcome', 'unknown');
          end;
          if LRollbackError <> '' then
            LErrorObj.AddPair('rollbackError', LRollbackError);
          // A separate field, so the NexusDB message stays exactly as the server sent it.
          if (LMode <> stmNone) and ContainsText(E.Message, 'DDL statements cannot execute while a transaction is active') then
            LErrorObj.AddPair('hint', 'NexusDB refuses DDL (CREATE/DROP/ALTER, also on #temp tables) inside a ' +
              'transaction. Use transaction="none". SELECT ... INTO #temp is not DDL and works in every mode.')
          else if LMode = stmNone then
            LErrorObj.AddPair('hint', 'transaction="none": any statements that ran before the failing one were ' +
              'applied and are not undone.');
          if LStaleRolledBack then
            LErrorObj.AddPair('staleTransactionRolledBack', TJSONBool.Create(True));
          LErrorObj.AddPair('transaction', cTransactionModeNames[LMode]);
          LErrorObj.AddPair('elapsedMs', TJSONNumber.Create(LStopwatch.ElapsedMilliseconds));
          LErrorJson := LErrorObj.ToJSON;
        finally
          LErrorObj.Free;
        end;

        // An argument error (malformed params) raised before the script ran is the caller's
        // mistake, not a script failure: report it as a tool error, like the other argument checks.
        if not LExecuting and (NexusErrorCode(E) = 0) then
          raise;

        // A failed script is a failed tool call: clients rely on isError to tell success from
        // failure. EMCPToolError makes the tools manager answer isError=true with this message
        // as the text, verbatim (no "Error executing tool:" prefix), so the body stays the same
        // JSON object and callers can still compare the exact NexusDB message in "error".
        raise EMCPToolError.Create(LErrorJson);
      end;
    end;
  finally
    // Best-effort: with a cursor still open (its Close above may have failed) the write is forwarded
    // to it, and nothing raised here may replace the result or the error built above.
    try
      nxmodule.nxQuery1.Timeout := LOldTimeout;
    except
    end;
    LResultObj.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('run_script',
    function: IMCPTool
    begin
      Result := TRunScriptTool.Create;
    end
  );

end.
