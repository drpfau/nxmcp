unit nxmcp.Tool.ExecuteQuery;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Math,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the execute_query tool
  /// </summary>
  TExecuteQueryParams = class
  private
    FSql: string;
    FMaxRows: Integer;
  public
    [SchemaDescription('SQL SELECT query to execute')]
    property Sql: string read FSql write FSql;

    [Optional]
    [SchemaDescription('Maximum number of rows to return (default: 100, max: 10000)')]
    property MaxRows: Integer read FMaxRows write FMaxRows;
  end;

  /// <summary>
  /// MCP Tool that executes SQL SELECT queries and returns JSON results
  /// </summary>
  TExecuteQueryTool = class(TMCPToolBase<TExecuteQueryParams>)
  protected
    function ExecuteWithParams(const Params: TExecuteQueryParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  Data.DB,
  DataSet.Serialize,
  MCPServer.Registration,
  dmnx;

{ TExecuteQueryTool }

constructor TExecuteQueryTool.Create;
begin
  inherited;
  FName := 'execute_query';
  FTitle := 'Execute SQL Query';
  FDescription := 'Execute a SQL SELECT query against the NexusDB database and return results as JSON. ' +
                  'Use this for reading data. For INSERT/UPDATE/DELETE, use execute_sql instead. ' +
                  'Statement switches can be prefixed: #T ms (timeout), #I- (disable index optimization), ' +
                  '#S- (disable simplification), #B+ (force BLOB copy). Example: "#T 5000 SELECT * FROM large_table"';
end;

function TExecuteQueryTool.ExecuteWithParams(const Params: TExecuteQueryParams): string;
var
  LMaxRows: Integer;
  LRowCount: Integer;
  LJSONArray: TJSONArray;
  LResultObj: TJSONObject;
begin
  // Validate parameters
  if Trim(Params.Sql) = '' then
    raise Exception.Create('SQL query cannot be empty');

  // Check for non-SELECT statements
  if not Params.Sql.TrimLeft.ToUpper.StartsWith('SELECT') then
    raise Exception.Create('Only SELECT queries are allowed. Use execute_sql for other statements.');

  // Determine max rows
  if Params.MaxRows > 0 then
    LMaxRows := Min(Params.MaxRows, 10000)
  else
    LMaxRows := 100;

  // Check connection
  if not Assigned(nxmodule) or not nxmodule.IsConnected then
    raise Exception.Create('Not connected to NexusDB');

  // Execute query
  nxmodule.nxQuery1.Close;
  nxmodule.nxQuery1.SQL.Text := Params.Sql;
  nxmodule.nxQuery1.Open;

  try
    // Count rows and limit if needed
    LRowCount := 0;
    nxmodule.nxQuery1.First;
    while not nxmodule.nxQuery1.Eof do
    begin
      Inc(LRowCount);
      if LRowCount >= LMaxRows then
        Break;
      nxmodule.nxQuery1.Next;
    end;

    // Reset to beginning and export
    nxmodule.nxQuery1.First;

    // Use dataset.serialize to convert to JSON
    LJSONArray := nxmodule.nxQuery1.ToJSONArray;
    try
      // Build result with metadata
      LResultObj := TJSONObject.Create;
      try
        LResultObj.AddPair('rowCount', TJSONNumber.Create(LRowCount));
        LResultObj.AddPair('maxRows', TJSONNumber.Create(LMaxRows));
        LResultObj.AddPair('truncated', TJSONBool.Create(LRowCount >= LMaxRows));
        LResultObj.AddPair('data', LJSONArray);

        Result := LResultObj.ToJSON;
      finally
        // Note: LJSONArray ownership transferred to LResultObj
        LResultObj.Free;
      end;
    except
      LJSONArray.Free;
      raise;
    end;
  finally
    nxmodule.nxQuery1.Close;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('execute_query',
    function: IMCPTool
    begin
      Result := TExecuteQueryTool.Create;
    end
  );

end.
