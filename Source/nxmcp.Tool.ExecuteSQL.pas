unit nxmcp.Tool.ExecuteSQL;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the execute_sql tool
  /// </summary>
  TExecuteSQLParams = class
  private
    FSql: string;
  public
    [SchemaDescription('SQL statement to execute (INSERT, UPDATE, DELETE, or other non-SELECT statements)')]
    property Sql: string read FSql write FSql;
  end;

  /// <summary>
  /// MCP Tool that executes SQL statements (INSERT, UPDATE, DELETE)
  /// </summary>
  TExecuteSQLTool = class(TMCPToolBase<TExecuteSQLParams>)
  protected
    function ExecuteWithParams(const Params: TExecuteSQLParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  Data.DB,
  MCPServer.Registration,
  dmnx;

{ TExecuteSQLTool }

constructor TExecuteSQLTool.Create;
begin
  inherited;
  FName := 'execute_sql';
  FTitle := 'Execute SQL Statement';
  FDescription := 'Execute a SQL statement (INSERT, UPDATE, DELETE) against the NexusDB database. ' +
                  'Returns the number of rows affected. For SELECT queries, use execute_query instead. ' +
                  'Statement switches can be prefixed: #T ms (timeout). Example: "#T 10000 DELETE FROM large_table WHERE old = 1"';
end;

function TExecuteSQLTool.ExecuteWithParams(const Params: TExecuteSQLParams): string;
var
  LResultObj: TJSONObject;
  LRowsAffected: Integer;
  LSqlUpper: string;
begin
  // Validate parameters
  if Trim(Params.Sql) = '' then
    raise Exception.Create('SQL statement cannot be empty');

  // Check for SELECT statements - those should use execute_query
  LSqlUpper := Params.Sql.TrimLeft.ToUpper;
  if LSqlUpper.StartsWith('SELECT') then
    raise Exception.Create('SELECT queries are not allowed. Use execute_query for SELECT statements.');

  // Check connection
  if not Assigned(nxmodule) or not nxmodule.IsConnected then
    raise Exception.Create('Not connected to NexusDB');

  // Execute SQL
  nxmodule.nxQuery1.Close;
  nxmodule.nxQuery1.SQL.Text := Params.Sql;
  nxmodule.nxQuery1.ExecSQL;
  LRowsAffected := nxmodule.nxQuery1.RowsAffected;

  // Build result
  LResultObj := TJSONObject.Create;
  try
    LResultObj.AddPair('success', TJSONBool.Create(True));
    LResultObj.AddPair('rowsAffected', TJSONNumber.Create(LRowsAffected));
    LResultObj.AddPair('statement', Copy(LSqlUpper, 1, Pos(' ', LSqlUpper + ' ') - 1));
    Result := LResultObj.ToJSON;
  finally
    LResultObj.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('execute_sql',
    function: IMCPTool
    begin
      Result := TExecuteSQLTool.Create;
    end
  );

end.
