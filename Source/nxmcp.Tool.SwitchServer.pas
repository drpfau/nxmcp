unit nxmcp.Tool.SwitchServer;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the switch_server tool
  /// </summary>
  TSwitchServerParams = class
  private
    FServerHost: string;
    FServerPort: Integer;
    FAliasName: string;
    FTablePassword: string;
  public
    [SchemaDescription('NexusDB server hostname or IP address to connect to')]
    property ServerHost: string read FServerHost write FServerHost;

    [Optional]
    [SchemaDescription('NexusDB server port (default: keeps current port)')]
    property ServerPort: Integer read FServerPort write FServerPort;

    [Optional]
    [SchemaDescription('Database alias to open on the new server (default: reuses current alias)')]
    property AliasName: string read FAliasName write FAliasName;

    [Optional]
    [SchemaDescription('Table password for the database (leave empty if not needed)')]
    property TablePassword: string read FTablePassword write FTablePassword;
  end;

  /// <summary>
  /// MCP Tool that switches the connection to a different NexusDB server
  /// </summary>
  TSwitchServerTool = class(TMCPToolBase<TSwitchServerParams>)
  protected
    function ExecuteWithParams(const Params: TSwitchServerParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  MCPServer.Registration,
  dmnx;

{ TSwitchServerTool }

constructor TSwitchServerTool.Create;
begin
  inherited;
  FName := 'switch_server';
  FTitle := 'Switch Server';
  FDescription := 'Switch the connection to a different NexusDB server. ' +
                  'Fully disconnects from the current server and reconnects to the new one. ' +
                  'Optionally specify a database alias to open on the new server. ' +
                  'If switching fails, the server attempts to reconnect to the previous server.';
end;

function TSwitchServerTool.ExecuteWithParams(const Params: TSwitchServerParams): string;
var
  LResultObj: TJSONObject;
  LOldServer: string;
begin
  // Validate parameters
  if Trim(Params.ServerHost) = '' then
    raise Exception.Create('Server host cannot be empty');

  // Check that nxmodule is assigned
  if not Assigned(nxmodule) then
    raise Exception.Create('NexusDB module not initialized');

  // Check if already connected to same server (and same alias if provided)
  if SameText(Params.ServerHost, nxmodule.ServerHost) and
     ((Params.ServerPort = 0) or (Params.ServerPort = nxmodule.ServerPort)) and
     ((Params.AliasName = '') or SameText(Params.AliasName, nxmodule.AliasName)) and
     nxmodule.IsConnected then
  begin
    LResultObj := TJSONObject.Create;
    try
      LResultObj.AddPair('success', TJSONBool.Create(True));
      LResultObj.AddPair('message', 'Already connected to this server');
      LResultObj.AddPair('serverHost', nxmodule.ServerHost);
      LResultObj.AddPair('serverPort', TJSONNumber.Create(nxmodule.ServerPort));
      LResultObj.AddPair('aliasName', nxmodule.AliasName);
      Result := LResultObj.ToJSON;
    finally
      LResultObj.Free;
    end;
    Exit;
  end;

  // Remember previous server for reporting
  LOldServer := nxmodule.ServerHost + ':' + IntToStr(nxmodule.ServerPort);

  // Perform the switch (SwitchServer handles rollback on failure)
  nxmodule.SwitchServer(Params.ServerHost, Params.ServerPort,
    Params.AliasName, Params.TablePassword);

  // Build success result
  LResultObj := TJSONObject.Create;
  try
    LResultObj.AddPair('success', TJSONBool.Create(True));
    LResultObj.AddPair('previousServer', LOldServer);
    LResultObj.AddPair('currentServer', nxmodule.ServerHost + ':' +
                       IntToStr(nxmodule.ServerPort));
    LResultObj.AddPair('currentAlias', nxmodule.AliasName);
    LResultObj.AddPair('connected', TJSONBool.Create(nxmodule.IsConnected));
    Result := LResultObj.ToJSON;
  finally
    LResultObj.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('switch_server',
    function: IMCPTool
    begin
      Result := TSwitchServerTool.Create;
    end
  );

end.
