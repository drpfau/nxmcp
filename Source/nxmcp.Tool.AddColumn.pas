unit nxmcp.Tool.AddColumn;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the add_column tool
  /// </summary>
  TAddColumnParams = class
  private
    FTableName: string;
    FColumnName: string;
    FColumnType: string;
    FSize: Integer;
    FDefaultValueType: string;
    FApplyOnInsert: Boolean;
    FApplyOnModify: Boolean;
    FOverwriteNonNull: Boolean;
  public
    [SchemaDescription('Name of the table to add the column to')]
    property TableName: string read FTableName write FTableName;

    [SchemaDescription('Name of the new column')]
    property ColumnName: string read FColumnName write FColumnName;

    [SchemaDescription('Column type: AutoInc, ShortString, WideString, Integer, Int64, Word, Byte, Boolean, Float, Currency, DateTime, Date, Time, Blob, Memo')]
    property ColumnType: string read FColumnType write FColumnType;

    [Optional]
    [SchemaDescription('Size/length for string types (default: 0)')]
    property Size: Integer read FSize write FSize;

    [Optional]
    [SchemaDescription('Default value type: CurrentDateTime, CurrentDate, CurrentTime (optional)')]
    property DefaultValueType: string read FDefaultValueType write FDefaultValueType;

    [Optional]
    [SchemaDescription('Apply default value on insert (default: true)')]
    property ApplyOnInsert: Boolean read FApplyOnInsert write FApplyOnInsert;

    [Optional]
    [SchemaDescription('Apply default value on modify (default: true)')]
    property ApplyOnModify: Boolean read FApplyOnModify write FApplyOnModify;

    [Optional]
    [SchemaDescription('Overwrite existing non-null values with default (default: false)')]
    property OverwriteNonNull: Boolean read FOverwriteNonNull write FOverwriteNonNull;
  end;

  /// <summary>
  /// MCP Tool that adds a column to an existing table
  /// </summary>
  TAddColumnTool = class(TMCPToolBase<TAddColumnParams>)
  protected
    function ExecuteWithParams(const Params: TAddColumnParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  nxsdTypes,
  nxsdDataDictionary,
  nxsdTableMapperDescriptor,
  nxsdServerEngine,
  nxllException,
  MCPServer.Registration,
  dmnx;

function StringToFieldType(const AType: string): TnxFieldType;
var
  LType: string;
begin
  LType := LowerCase(AType);
  if LType = 'autoinc' then Result := nxtAutoInc
  else if LType = 'shortstring' then Result := nxtShortString
  else if LType = 'widestring' then Result := nxtWideString
  else if LType = 'integer' then Result := nxtInt32
  else if LType = 'int64' then Result := nxtInt64
  else if LType = 'word' then Result := nxtWord16
  else if LType = 'byte' then Result := nxtByte
  else if LType = 'boolean' then Result := nxtBoolean
  else if LType = 'float' then Result := nxtDouble
  else if LType = 'currency' then Result := nxtCurrency
  else if LType = 'datetime' then Result := nxtDateTime
  else if LType = 'date' then Result := nxtDate
  else if LType = 'time' then Result := nxtTime
  else if LType = 'blob' then Result := nxtBlob
  else if LType = 'memo' then Result := nxtBlobMemo
  else
    raise Exception.CreateFmt('Unknown field type: %s', [AType]);
end;

{ TAddColumnTool }

constructor TAddColumnTool.Create;
begin
  inherited;
  FName := 'add_column';
  FTitle := 'Add Column';
  FDescription := 'Add a new column to an existing table. Optionally set a default value type for automatic population.';
end;

function TAddColumnTool.ExecuteWithParams(const Params: TAddColumnParams): string;
var
  LResultObj: TJSONObject;
  LOldDict, LNewDict: TnxDataDictionary;
  LMapper: TnxTableMapperDescriptor;
  LTaskInfo: TnxAbstractTaskInfo;
  LCompleted: Boolean;
  LTaskStatus: TnxTaskStatus;
  LFieldType: TnxFieldType;
  LFieldIdx: Integer;
  LApplyOnInsert, LApplyOnModify: Boolean;
begin
  // Validate parameters
  if Trim(Params.TableName) = '' then
    raise Exception.Create('Table name cannot be empty');

  if Trim(Params.ColumnName) = '' then
    raise Exception.Create('Column name cannot be empty');

  if Trim(Params.ColumnType) = '' then
    raise Exception.Create('Column type cannot be empty');

  LFieldType := StringToFieldType(Params.ColumnType);

  // Check connection
  if not Assigned(nxmodule) or not nxmodule.IsConnected then
    raise Exception.Create('Not connected to NexusDB');

  // Close any open tables to avoid conflicts
  nxmodule.nxSession1.CloseInactiveTables;

  LOldDict := TnxDataDictionary.Create;
  try
    // Get existing dictionary
    nxCheck(nxmodule.nxDatabase1.GetDataDictionaryEx(Params.TableName, nxmodule.TablePassword, LOldDict));

    // Check if column already exists
    if LOldDict.FieldsDescriptor.GetFieldFromName(Params.ColumnName) >= 0 then
      raise Exception.CreateFmt('Column "%s" already exists in table "%s"', [Params.ColumnName, Params.TableName]);

    // Create new dictionary with added column
    LNewDict := TnxDataDictionary.Create;
    try
      LNewDict.Assign(LOldDict);

      // Add the new field
      LNewDict.FieldsDescriptor.AddField(Params.ColumnName, '', LFieldType, Params.Size, 0, False);

      // Set default value if specified
      if Trim(Params.DefaultValueType) <> '' then
      begin
        LFieldIdx := LNewDict.FieldsDescriptor.GetFieldFromName(Params.ColumnName);
        if LFieldIdx >= 0 then
        begin
          // Determine default value settings
          LApplyOnInsert := True;
          LApplyOnModify := True;
          if Params.ApplyOnInsert then LApplyOnInsert := Params.ApplyOnInsert;
          if Params.ApplyOnModify then LApplyOnModify := Params.ApplyOnModify;

          if SameText(Params.DefaultValueType, 'CurrentDateTime') then
            LNewDict.FieldsDescriptor.FieldDescriptor[LFieldIdx].AddDefaultValue(TnxCurrentDateTimeDefaultValueDescriptor)
          else if SameText(Params.DefaultValueType, 'CurrentUser') then
            LNewDict.FieldsDescriptor.FieldDescriptor[LFieldIdx].AddDefaultValue(TnxCurrentUserDefaultValueDescriptor)
          else
            raise Exception.CreateFmt('Unknown default value type: %s', [Params.DefaultValueType]);

          // Configure default value behavior
          with LNewDict.FieldsDescriptor.FieldDescriptor[LFieldIdx].fdDefaultValue do
          begin
            ApplyAt := [aaServer, aaClient];
            ApplyOnInsert := LApplyOnInsert;
            ApplyOnModify := LApplyOnModify;
            OverwriteNonNull := Params.OverwriteNonNull;
          end;
        end;
      end;

      // Check if restructure is needed
      if LOldDict.IsEqual(LNewDict) then
        raise Exception.Create('No changes detected');

      // Create mapper and restructure
      LMapper := TnxTableMapperDescriptor.Create;
      try
        LMapper.MapAllTablesAndFieldsByName(LOldDict, LNewDict);

        nxCheck(nxmodule.nxDatabase1.RestructureTableEx(Params.TableName, nxmodule.TablePassword,
          LNewDict, LMapper, LTaskInfo));

        // Wait for completion
        if Assigned(LTaskInfo) then
        try
          while True do
          begin
            LTaskInfo.GetStatus(LCompleted, LTaskStatus);
            if LCompleted then
              Break;
            Sleep(100);
          end;
          nxCheck(LTaskStatus.tsErrorCode);
        finally
          LTaskInfo.Free;
        end;
      finally
        LMapper.Free;
      end;
    finally
      LNewDict.Free;
    end;
  finally
    LOldDict.Free;
  end;

  // Build result
  LResultObj := TJSONObject.Create;
  try
    LResultObj.AddPair('success', TJSONBool.Create(True));
    LResultObj.AddPair('tableName', Params.TableName);
    LResultObj.AddPair('columnName', Params.ColumnName);
    LResultObj.AddPair('columnType', Params.ColumnType);
    if Trim(Params.DefaultValueType) <> '' then
      LResultObj.AddPair('defaultValueType', Params.DefaultValueType);
    Result := LResultObj.ToJSON;
  finally
    LResultObj.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('add_column',
    function: IMCPTool
    begin
      Result := TAddColumnTool.Create;
    end
  );

end.
