unit nxmcp.Tool.ExplainQuery;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the explain_query tool
  /// </summary>
  TExplainQueryParams = class
  private
    FSql: string;
    FVerbose: Boolean;
  public
    [SchemaDescription('SQL SELECT query to analyze')]
    property Sql: string read FSql write FSql;
    [SchemaDescription('Use verbose mode (#V+) for full optimizer internals: all indexes considered, relation analysis, decision process. Default is standard mode (#L+) showing plan summary.')]
    property Verbose: Boolean read FVerbose write FVerbose;
  end;

  /// <summary>
  /// MCP Tool that returns the execution plan for a query.
  /// Uses NexusDB query logging to show how the query will be executed.
  /// </summary>
  TExplainQueryTool = class(TMCPToolBase<TExplainQueryParams>)
  protected
    function ExecuteWithParams(const Params: TExplainQueryParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.StrUtils,
  Data.DB,
  MCPServer.Registration,
  nxmcp.SqlUtils,
  dmnx;

{ TExplainQueryTool }

constructor TExplainQueryTool.Create;
begin
  inherited;
  FName := 'explain_query';
  FTitle := 'Explain Query Plan';
  FDescription := 'Show the execution plan for a single SELECT, INSERT, UPDATE or DELETE. ' +
                  'IMPORTANT: NexusDB produces a plan only by running the statement, so this ' +
                  'tool executes it. A SELECT is read-only anyway; INSERT/UPDATE/DELETE are ' +
                  'run inside a transaction that is ALWAYS rolled back, so they change nothing ' +
                  '(the response reports rolledBack). DDL is rejected because it is not ' +
                  'transactional. Exactly one statement - no semicolon-separated batches. ' +
                  'Standard mode (#L+) shows plan summary: index used, join strategy, rows read. ' +
                  'Verbose mode (#V+) shows full optimizer internals: all available indexes, ' +
                  'relation analysis, index selection decisions, simplification steps. ' +
                  'You can add #I- to disable index optimization or #S- to disable simplification ' +
                  'to compare different execution plans.';
end;

function TExplainQueryTool.ExecuteWithParams(const Params: TExplainQueryParams): string;
var
  LResultObj: TJSONObject;
  LPlanArray: TJSONArray;
  LSwitch: string;
  I: Integer;
  LFacts: TnxSqlFacts;
  LNeedsRollback: Boolean;
begin
  // Validate parameters
  if Trim(Params.Sql) = '' then
    raise Exception.Create('SQL query cannot be empty');

  LFacts := AnalyzeSql(Params.Sql);
  if LFacts.Kind = skUnparsable then
    raise Exception.Create('SQL could not be parsed. Check the statement syntax.');
  if not LFacts.IsSingle then
    raise Exception.Create('Only a single statement can be explained - a second statement ' +
      'after a semicolon would also be executed. Use batch_execute to run several statements.');
  if not (LFacts.Kind in [skSelect, skInsert, skUpdate, skDelete]) then
    raise Exception.Create('Only SELECT, INSERT, UPDATE and DELETE can be explained. ' +
      'Producing a plan requires running the statement, and DDL is not transactional, so it ' +
      'could not be rolled back afterwards. Use execute_sql to run DDL.');
  if LFacts.HasInto then
    raise Exception.Create('SELECT ... INTO creates and populates a table, which a rollback ' +
      'would not undo. Use execute_sql for it.');

  // Check connection
  if not Assigned(nxmodule) or not nxmodule.EnsureConnection then
    raise Exception.Create('Not connected to NexusDB');

  // Choose logging switch: #V+ for verbose, #L+ for standard
  if Params.Verbose then
    LSwitch := '#V+'
  else
    LSwitch := '#L+';

  // There is no non-executing explain in NexusDB: TnxQuery.Log is filled from the
  // ExecStream of StatementExecDirect (nxdb.pas), i.e. the plan is a by-product of
  // running the statement - Prepare alone leaves Log empty (verified). So to
  // explain a write without performing it, run it inside a transaction and always
  // roll back. DDL is rejected above because it is not transactional, so a
  // rollback would not undo it.
  LNeedsRollback := LFacts.Kind in [skInsert, skUpdate, skDelete];

  if LNeedsRollback then
    nxmodule.nxDatabase1.StartTransaction(False);
  try
    nxmodule.ExecuteWithReconnect(
      procedure
      begin
        nxmodule.nxQuery1.Close;
        nxmodule.nxQuery1.SQL.Text := LSwitch + ' ' + Params.Sql;
        nxmodule.nxQuery1.Open;
      end);
  except
    if LNeedsRollback and nxmodule.nxDatabase1.InTransaction then
      nxmodule.nxDatabase1.Rollback;
    raise;
  end;

  try
    // Build result from Log property
    LResultObj := TJSONObject.Create;
    try
      LResultObj.AddPair('sql', Params.Sql);
      LResultObj.AddPair('mode', IfThen(Params.Verbose, 'verbose', 'standard'));

      LPlanArray := TJSONArray.Create;
      for I := 0 to nxmodule.nxQuery1.Log.Count - 1 do
        LPlanArray.Add(nxmodule.nxQuery1.Log[I]);

      LResultObj.AddPair('plan', LPlanArray);
      LResultObj.AddPair('lineCount', TJSONNumber.Create(nxmodule.nxQuery1.Log.Count));
      LResultObj.AddPair('executed', TJSONBool.Create(True));
      LResultObj.AddPair('rolledBack', TJSONBool.Create(LNeedsRollback));

      Result := LResultObj.ToJSON;
    finally
      LResultObj.Free;
    end;
  finally
    nxmodule.nxQuery1.Close;
    // Always roll back - the statement ran only to produce the plan.
    if LNeedsRollback and nxmodule.nxDatabase1.InTransaction then
      nxmodule.nxDatabase1.Rollback;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('explain_query',
    function: IMCPTool
    begin
      Result := TExplainQueryTool.Create;
    end
  );

end.
