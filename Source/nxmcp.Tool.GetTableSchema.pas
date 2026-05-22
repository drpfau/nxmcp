unit nxmcp.Tool.GetTableSchema;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the get_table_schema tool
  /// </summary>
  TGetTableSchemaParams = class
  private
    FTableName: string;
  public
    [SchemaDescription('Name of the table to get schema for')]
    property TableName: string read FTableName write FTableName;
  end;

  /// <summary>
  /// MCP Tool that returns detailed schema information for a table
  /// </summary>
  TGetTableSchemaTool = class(TMCPToolBase<TGetTableSchemaParams>)
  protected
    function ExecuteWithParams(const Params: TGetTableSchemaParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  Data.DB,
  MCPServer.Registration,
  dmnx;

{ TGetTableSchemaTool }

constructor TGetTableSchemaTool.Create;
begin
  inherited;
  FName := 'get_table_schema';
  FTitle := 'Get Table Schema';
  FDescription := 'Get detailed schema information for a specific table including columns, data types, and indexes.';
end;

function TGetTableSchemaTool.ExecuteWithParams(const Params: TGetTableSchemaParams): string;
var
  LResultObj: TJSONObject;
  LColumnsArray: TJSONArray;
  LIndexesArray: TJSONArray;
  LColumnObj: TJSONObject;
  LIndexObj: TJSONObject;
  LRecordCount: Integer;
  LTableNameField: TField;
  LFieldNameField: TField;
  LIndexNameField: TField;
  I: Integer;

  function FindFieldByPatterns(const Patterns: array of string): TField;
  var
    J, K: Integer;
  begin
    Result := nil;
    // First try FindField (case-insensitive)
    for J := 0 to High(Patterns) do
    begin
      Result := nxmodule.nxQuery1.FindField(Patterns[J]);
      if Result <> nil then
        Exit;
    end;
    // Fallback: iterate through all fields
    for K := 0 to nxmodule.nxQuery1.FieldCount - 1 do
    begin
      for J := 0 to High(Patterns) do
      begin
        if SameText(nxmodule.nxQuery1.Fields[K].FieldName, Patterns[J]) then
        begin
          Result := nxmodule.nxQuery1.Fields[K];
          Exit;
        end;
      end;
    end;
  end;

begin
  // Validate parameters
  if Trim(Params.TableName) = '' then
    raise Exception.Create('Table name cannot be empty');

  // Check connection
  if not Assigned(nxmodule) or not nxmodule.EnsureConnection then
    raise Exception.Create('Not connected to NexusDB');

  LResultObj := TJSONObject.Create;
  try
    LResultObj.AddPair('tableName', Params.TableName);

    // Get column information from #FIELDS system table
    LColumnsArray := TJSONArray.Create;
    LResultObj.AddPair('columns', LColumnsArray);

    nxmodule.nxQuery1.Close;
    nxmodule.nxQuery1.SQL.Text := 'SELECT * FROM "#FIELDS"';
    nxmodule.nxQuery1.Open;
    try
      // Find tableName field using multiple patterns
      LTableNameField := FindFieldByPatterns(['tableName', 'TABLENAME', 'TABLE_NAME', 'Table_Name']);
      // Fallback to field index 1 if not found (index 0 is usually tableIndex)
      if LTableNameField = nil then
        LTableNameField := nxmodule.nxQuery1.Fields[1];

      while not nxmodule.nxQuery1.Eof do
      begin
        if SameText(LTableNameField.AsString, Params.TableName) then
        begin
          LColumnObj := TJSONObject.Create;
          LFieldNameField := FindFieldByPatterns(['fieldName', 'FIELDNAME', 'FIELD_NAME']);
          if LFieldNameField = nil then LFieldNameField := nxmodule.nxQuery1.Fields[3];
          LColumnObj.AddPair('name', LFieldNameField.AsString);

          LFieldNameField := FindFieldByPatterns(['fieldTypeSql', 'FIELDTYPESQL', 'FIELD_TYPE_SQL']);
          if LFieldNameField <> nil then
            LColumnObj.AddPair('typeSql', LFieldNameField.AsString);

          LFieldNameField := FindFieldByPatterns(['fieldTypeNexus', 'FIELDTYPENEXUS', 'FIELD_TYPE_NEXUS']);
          if LFieldNameField <> nil then
            LColumnObj.AddPair('typeNexus', LFieldNameField.AsString);

          LFieldNameField := FindFieldByPatterns(['fieldLength', 'FIELDLENGTH', 'FIELD_LENGTH']);
          if LFieldNameField <> nil then
            LColumnObj.AddPair('length', TJSONNumber.Create(LFieldNameField.AsInteger));

          LFieldNameField := FindFieldByPatterns(['fieldUnits', 'FIELDUNITS', 'FIELD_UNITS']);
          if LFieldNameField <> nil then
            LColumnObj.AddPair('units', TJSONNumber.Create(LFieldNameField.AsInteger));

          LFieldNameField := FindFieldByPatterns(['fieldDecimals', 'FIELDDECIMALS', 'FIELD_DECIMALS']);
          if LFieldNameField <> nil then
            LColumnObj.AddPair('decimals', TJSONNumber.Create(LFieldNameField.AsInteger));

          LFieldNameField := FindFieldByPatterns(['fieldRequired', 'FIELDREQUIRED', 'FIELD_REQUIRED']);
          if LFieldNameField <> nil then
            LColumnObj.AddPair('required', TJSONBool.Create(LFieldNameField.AsBoolean));

          LColumnsArray.AddElement(LColumnObj);
        end;
        nxmodule.nxQuery1.Next;
      end;
    finally
      nxmodule.nxQuery1.Close;
    end;

    LResultObj.AddPair('columnCount', TJSONNumber.Create(LColumnsArray.Count));

    // Get index information from #INDEXES system table
    LIndexesArray := TJSONArray.Create;
    LResultObj.AddPair('indexes', LIndexesArray);

    nxmodule.nxQuery1.Close;
    nxmodule.nxQuery1.SQL.Text := 'SELECT * FROM "#INDEXES"';
    nxmodule.nxQuery1.Open;
    try
      LTableNameField := FindFieldByPatterns(['tableName', 'TABLENAME', 'TABLE_NAME', 'Table_Name']);
      if LTableNameField = nil then
        LTableNameField := nxmodule.nxQuery1.Fields[1];

      while not nxmodule.nxQuery1.Eof do
      begin
        if SameText(LTableNameField.AsString, Params.TableName) then
        begin
          LIndexObj := TJSONObject.Create;
          LIndexNameField := FindFieldByPatterns(['indexName', 'INDEXNAME', 'INDEX_NAME']);
          if LIndexNameField = nil then LIndexNameField := nxmodule.nxQuery1.Fields[2];
          LIndexObj.AddPair('name', LIndexNameField.AsString);

          LFieldNameField := FindFieldByPatterns(['indexAllowsdups', 'INDEXALLOWSDUPS', 'INDEX_ALLOWS_DUPS']);
          if LFieldNameField <> nil then
            LIndexObj.AddPair('unique', TJSONBool.Create(SameText(LFieldNameField.AsString, 'NO')));

          LIndexesArray.AddElement(LIndexObj);
        end;
        nxmodule.nxQuery1.Next;
      end;
    finally
      nxmodule.nxQuery1.Close;
    end;

    LResultObj.AddPair('indexCount', TJSONNumber.Create(LIndexesArray.Count));

    // Get record count
    nxmodule.nxQuery1.Close;
    nxmodule.nxQuery1.SQL.Text := 'SELECT COUNT(*) FROM "' + Params.TableName + '"';
    try
      nxmodule.nxQuery1.Open;
      LRecordCount := nxmodule.nxQuery1.Fields[0].AsInteger;
    except
      LRecordCount := -1;
    end;
    nxmodule.nxQuery1.Close;

    LResultObj.AddPair('recordCount', TJSONNumber.Create(LRecordCount));

    Result := LResultObj.ToJSON;
  except
    LResultObj.Free;
    raise;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('get_table_schema',
    function: IMCPTool
    begin
      Result := TGetTableSchemaTool.Create;
    end
  );

end.
