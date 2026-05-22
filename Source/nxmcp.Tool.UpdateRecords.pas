unit nxmcp.Tool.UpdateRecords;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the update_records tool
  /// </summary>
  TUpdateRecordsParams = class
  private
    FTableName: string;
    FData: string;
    FWhereClause: string;
  public
    [SchemaDescription('Name of the table to update')]
    property TableName: string read FTableName write FTableName;

    [SchemaDescription('JSON string with column names as keys and new values, e.g. {"Name": "Updated", "Value": 456}')]
    property Data: string read FData write FData;

    [SchemaDescription('WHERE clause without the WHERE keyword (e.g., "ID = 5" or "Status = ''Active''")')]
    property WhereClause: string read FWhereClause write FWhereClause;
  end;

  /// <summary>
  /// MCP Tool that updates records in a table
  /// </summary>
  TUpdateRecordsTool = class(TMCPToolBase<TUpdateRecordsParams>)
  protected
    function ExecuteWithParams(const Params: TUpdateRecordsParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  Data.DB,
  MCPServer.Registration,
  dmnx;

{ TUpdateRecordsTool }

constructor TUpdateRecordsTool.Create;
begin
  inherited;
  FName := 'update_records';
  FTitle := 'Update Records';
  FDescription := 'Update records in a table matching the WHERE clause. Pass new values as a JSON object.';
end;

function TUpdateRecordsTool.ExecuteWithParams(const Params: TUpdateRecordsParams): string;
var
  LResultObj: TJSONObject;
  LDataObj: TJSONObject;
  LSql: string;
  LSetClause: string;
  LPair: TJSONPair;
  LRowsAffected: Integer;
begin
  // Validate parameters
  if Trim(Params.TableName) = '' then
    raise Exception.Create('Table name cannot be empty');

  if Trim(Params.Data) = '' then
    raise Exception.Create('Data cannot be empty');

  if Trim(Params.WhereClause) = '' then
    raise Exception.Create('WHERE clause is required to prevent accidental mass updates');

  // Parse JSON data
  LDataObj := TJSONObject.ParseJSONValue(Params.Data) as TJSONObject;
  if not Assigned(LDataObj) then
    raise Exception.Create('Invalid JSON data format');

  try
    if LDataObj.Count = 0 then
      raise Exception.Create('Data object cannot be empty');

    // Check connection
    if not Assigned(nxmodule) or not nxmodule.EnsureConnection then
      raise Exception.Create('Not connected to NexusDB');

    // Build SET clause
    LSetClause := '';

    for LPair in LDataObj do
    begin
      if LSetClause <> '' then
        LSetClause := LSetClause + ', ';

      LSetClause := LSetClause + '"' + LPair.JsonString.Value + '" = ';

      // Format value based on type
      if LPair.JsonValue is TJSONNull then
        LSetClause := LSetClause + 'NULL'
      else if LPair.JsonValue is TJSONNumber then
        LSetClause := LSetClause + LPair.JsonValue.Value
      else if LPair.JsonValue is TJSONBool then
      begin
        if TJSONBool(LPair.JsonValue).AsBoolean then
          LSetClause := LSetClause + 'TRUE'
        else
          LSetClause := LSetClause + 'FALSE';
      end
      else
        // String value - escape single quotes
        LSetClause := LSetClause + '''' + StringReplace(LPair.JsonValue.Value, '''', '''''', [rfReplaceAll]) + '''';
    end;

    LSql := 'UPDATE "' + Params.TableName + '" SET ' + LSetClause + ' WHERE ' + Params.WhereClause;

    // Execute (auto-reconnects and retries once on lost connection;
    // UPDATE with the same WHERE clause is generally safe to repeat)
    nxmodule.ExecuteWithReconnect(
      procedure
      begin
        nxmodule.nxQuery1.Close;
        nxmodule.nxQuery1.SQL.Text := LSql;
        nxmodule.nxQuery1.ExecSQL;
      end);
    LRowsAffected := nxmodule.nxQuery1.RowsAffected;

    // Build result
    LResultObj := TJSONObject.Create;
    try
      LResultObj.AddPair('success', TJSONBool.Create(True));
      LResultObj.AddPair('rowsAffected', TJSONNumber.Create(LRowsAffected));
      LResultObj.AddPair('tableName', Params.TableName);
      Result := LResultObj.ToJSON;
    finally
      LResultObj.Free;
    end;
  finally
    LDataObj.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('update_records',
    function: IMCPTool
    begin
      Result := TUpdateRecordsTool.Create;
    end
  );

end.
