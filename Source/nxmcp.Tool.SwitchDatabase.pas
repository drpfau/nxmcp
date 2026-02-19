unit nxmcp.Tool.SwitchDatabase;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the switch_database tool
  /// </summary>
  TSwitchDatabaseParams = class
  private
    FAliasName: string;
    FTablePassword: string;
  public
    [SchemaDescription('Database alias name to switch to (as configured on the NexusDB server)')]
    property AliasName: string read FAliasName write FAliasName;

    [Optional]
    [SchemaDescription('Table password for the new database (leave empty if not needed)')]
    property TablePassword: string read FTablePassword write FTablePassword;
  end;

  /// <summary>
  /// MCP Tool that switches the active database to a different alias
  /// </summary>
  TSwitchDatabaseTool = class(TMCPToolBase<TSwitchDatabaseParams>)
  protected
    function ExecuteWithParams(const Params: TSwitchDatabaseParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  MCPServer.Registration,
  dmnx;

{ TSwitchDatabaseTool }

constructor TSwitchDatabaseTool.Create;
begin
  inherited;
  FName := 'switch_database';
  FTitle := 'Switch Database';
  FDescription := 'Switch the active database to a different alias on the NexusDB server. ' +
                  'The transport and session remain connected; only the database is changed. ' +
                  'If switching fails, the server attempts to reconnect to the previous database. ' +
                  'Use list_aliases to see available aliases.';
end;

function TSwitchDatabaseTool.ExecuteWithParams(const Params: TSwitchDatabaseParams): string;
var
  LResultObj: TJSONObject;
  LOldAlias: string;
begin
  // Validate parameters
  if Trim(Params.AliasName) = '' then
    raise Exception.Create('Alias name cannot be empty');

  // Check that nxmodule is assigned
  if not Assigned(nxmodule) then
    raise Exception.Create('NexusDB module not initialized');

  // Session must be active (server connection must exist)
  if not nxmodule.nxSession1.Active then
    raise Exception.Create('Not connected to NexusDB server. Session is not active.');

  // Check if already on this alias
  if SameText(Params.AliasName, nxmodule.AliasName) and nxmodule.IsConnected then
  begin
    LResultObj := TJSONObject.Create;
    try
      LResultObj.AddPair('success', TJSONBool.Create(True));
      LResultObj.AddPair('message', 'Already connected to this alias');
      LResultObj.AddPair('aliasName', nxmodule.AliasName);
      Result := LResultObj.ToJSON;
    finally
      LResultObj.Free;
    end;
    Exit;
  end;

  // Remember previous alias for reporting
  LOldAlias := nxmodule.AliasName;

  // Perform the switch (SwitchDatabase handles rollback on failure)
  nxmodule.SwitchDatabase(Params.AliasName, Params.TablePassword);

  // Build success result
  LResultObj := TJSONObject.Create;
  try
    LResultObj.AddPair('success', TJSONBool.Create(True));
    LResultObj.AddPair('previousAlias', LOldAlias);
    LResultObj.AddPair('currentAlias', nxmodule.AliasName);
    LResultObj.AddPair('connected', TJSONBool.Create(nxmodule.IsConnected));
    if Params.TablePassword <> '' then
      LResultObj.AddPair('passwordSet', TJSONBool.Create(True));
    Result := LResultObj.ToJSON;
  finally
    LResultObj.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('switch_database',
    function: IMCPTool
    begin
      Result := TSwitchDatabaseTool.Create;
    end
  );

end.
