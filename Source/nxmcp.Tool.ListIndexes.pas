unit nxmcp.Tool.ListIndexes;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the list_indexes tool
  /// </summary>
  TListIndexesParams = class
  private
    FTableName: string;
  public
    [SchemaDescription('Name of the table to list indexes for')]
    property TableName: string read FTableName write FTableName;
  end;

  /// <summary>
  /// MCP Tool that lists all indexes for a table.
  /// </summary>
  TListIndexesTool = class(TMCPToolBase<TListIndexesParams>)
  protected
    function ExecuteWithParams(const Params: TListIndexesParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  Data.DB,
  DataSet.Serialize,
  MCPServer.Registration,
  dmnx;

{ TListIndexesTool }

constructor TListIndexesTool.Create;
begin
  inherited;
  FName := 'list_indexes';
  FTitle := 'List Table Indexes';
  FDescription := 'List all indexes defined on a table, including name, uniqueness, and whether it is the default index.';
end;

function TListIndexesTool.ExecuteWithParams(const Params: TListIndexesParams): string;
var
  LResultObj: TJSONObject;
  LIndexesArray: TJSONArray;
  LIndexObj: TJSONObject;
  LIndexCount: Integer;
begin
  // Validate parameters
  if Trim(Params.TableName) = '' then
    raise Exception.Create('Table name cannot be empty');

  // Check connection
  if not Assigned(nxmodule) or not nxmodule.IsConnected then
    raise Exception.Create('Not connected to NexusDB');

  // Query system table for indexes
  nxmodule.nxQuery1.Close;
  nxmodule.nxQuery1.SQL.Text :=
    'SELECT INDEX_NAME, INDEX_ALLOWSDUPS, INDEX_ISDEFAULT, CONSTRAINT_NAME ' +
    'FROM #INDEXES WHERE TABLE_NAME = ''' + Params.TableName + ''' ' +
    'ORDER BY INDEX_INDEX';
  nxmodule.nxQuery1.Open;

  LResultObj := TJSONObject.Create;
  try
    LIndexesArray := TJSONArray.Create;
    LIndexCount := 0;

    while not nxmodule.nxQuery1.Eof do
    begin
      LIndexObj := TJSONObject.Create;
      LIndexObj.AddPair('name', nxmodule.nxQuery1.FieldByName('INDEX_NAME').AsString);
      LIndexObj.AddPair('unique', TJSONBool.Create(
        nxmodule.nxQuery1.FieldByName('INDEX_ALLOWSDUPS').AsString = 'NO'));
      LIndexObj.AddPair('isDefault', TJSONBool.Create(
        nxmodule.nxQuery1.FieldByName('INDEX_ISDEFAULT').AsBoolean));
      LIndexObj.AddPair('constraint', nxmodule.nxQuery1.FieldByName('CONSTRAINT_NAME').AsString);
      LIndexesArray.AddElement(LIndexObj);

      Inc(LIndexCount);
      nxmodule.nxQuery1.Next;
    end;

    // Build result
    LResultObj.AddPair('tableName', Params.TableName);
    LResultObj.AddPair('indexCount', TJSONNumber.Create(LIndexCount));
    LResultObj.AddPair('indexes', LIndexesArray);
    Result := LResultObj.ToJSON;
  finally
    nxmodule.nxQuery1.Close;
    LResultObj.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('list_indexes',
    function: IMCPTool
    begin
      Result := TListIndexesTool.Create;
    end
  );

end.
