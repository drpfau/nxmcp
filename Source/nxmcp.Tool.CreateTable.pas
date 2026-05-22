unit nxmcp.Tool.CreateTable;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the create_table tool
  /// </summary>
  TCreateTableParams = class
  private
    FTableName: string;
    FColumns: string;
  public
    [SchemaDescription('Name of the table to create')]
    property TableName: string read FTableName write FTableName;

    [SchemaDescription('JSON array of column definitions, e.g. [{"name": "ID", "type": "AutoInc"}, {"name": "Name", "type": "ShortString", "size": 50}]. Supported types: Boolean, Char, WideChar, Byte, Word, Word32, Int8, Int16, Integer, Int64, AutoInc, Single, Float, Extended, Currency, Date, Time, DateTime, Blob, Memo, Graphic, ByteArray, ShortString, NullString, WideString, RecRev, Guid, BCD, WideMemo, FmtBCD, RefNr')]
    property Columns: string read FColumns write FColumns;
  end;

  /// <summary>
  /// MCP Tool that creates a new table
  /// </summary>
  TCreateTableTool = class(TMCPToolBase<TCreateTableParams>)
  protected
    function ExecuteWithParams(const Params: TCreateTableParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  Data.DB,
  nxsdTypes,
  nxsdDataDictionary,
  MCPServer.Registration,
  dmnx,
  nxmcp.FieldTypes;

{ TCreateTableTool }

constructor TCreateTableTool.Create;
begin
  inherited;
  FName := 'create_table';
  FTitle := 'Create Table';
  FDescription := 'Create a new table with the specified columns. Pass column definitions as a JSON array.';
end;

function TCreateTableTool.ExecuteWithParams(const Params: TCreateTableParams): string;
var
  LResultObj: TJSONObject;
  LColumnsArr: TJSONArray;
  LColObj: TJSONObject;
  LDict: TnxDataDictionary;
  LColName, LColType: string;
  LColSize: Integer;
  LFieldType: TnxFieldType;
  I: Integer;
begin
  // Validate parameters
  if Trim(Params.TableName) = '' then
    raise Exception.Create('Table name cannot be empty');

  if Trim(Params.Columns) = '' then
    raise Exception.Create('Columns definition cannot be empty');

  // Parse columns JSON
  LColumnsArr := TJSONObject.ParseJSONValue(Params.Columns) as TJSONArray;
  if not Assigned(LColumnsArr) then
    raise Exception.Create('Invalid columns JSON format - expected array');

  try
    if LColumnsArr.Count = 0 then
      raise Exception.Create('At least one column is required');

    // Check connection
    if not Assigned(nxmodule) or not nxmodule.EnsureConnection then
      raise Exception.Create('Not connected to NexusDB');

    // Create data dictionary
    LDict := TnxDataDictionary.Create;
    try
      // Add columns
      for I := 0 to LColumnsArr.Count - 1 do
      begin
        LColObj := LColumnsArr.Items[I] as TJSONObject;
        if not Assigned(LColObj) then
          raise Exception.CreateFmt('Column %d is not a valid JSON object', [I]);

        // Get column name
        if not Assigned(LColObj.GetValue('name')) then
          raise Exception.CreateFmt('Column %d missing "name" property', [I]);
        LColName := LColObj.GetValue('name').Value;

        // Get column type
        if not Assigned(LColObj.GetValue('type')) then
          raise Exception.CreateFmt('Column %d missing "type" property', [I]);
        LColType := LColObj.GetValue('type').Value;
        LFieldType := StringToFieldType(LColType);

        // Get column size (optional, default 0)
        LColSize := 0;
        if Assigned(LColObj.GetValue('size')) then
          LColSize := StrToIntDef(LColObj.GetValue('size').Value, 0);

        // Add field to dictionary
        LDict.FieldsDescriptor.AddField(LColName, '', LFieldType, LColSize, 0, False);
      end;

      // Create the table (auto-reconnects and retries once on lost connection)
      nxmodule.ExecuteWithReconnect(
        procedure
        begin
          nxmodule.nxDatabase1.CreateTable(False, Params.TableName, '', LDict);
        end);

      // Build result
      LResultObj := TJSONObject.Create;
      try
        LResultObj.AddPair('success', TJSONBool.Create(True));
        LResultObj.AddPair('tableName', Params.TableName);
        LResultObj.AddPair('columnCount', TJSONNumber.Create(LColumnsArr.Count));
        Result := LResultObj.ToJSON;
      finally
        LResultObj.Free;
      end;
    finally
      LDict.Free;
    end;
  finally
    LColumnsArr.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('create_table',
    function: IMCPTool
    begin
      Result := TCreateTableTool.Create;
    end
  );

end.
