unit nxmcp.Resource.Server;

interface

uses
  System.SysUtils,
  MCPServer.Resource.Base;

type
  /// <summary>
  /// Data class for NexusDB server connection information
  /// </summary>
  TNexusDBServerInfo = class
  private
    FConnected: Boolean;
    FServerHost: string;
    FServerPort: Integer;
    FDatabaseAlias: string;
    FLastError: string;
  public
    property Connected: Boolean read FConnected write FConnected;
    property ServerHost: string read FServerHost write FServerHost;
    property ServerPort: Integer read FServerPort write FServerPort;
    property DatabaseAlias: string read FDatabaseAlias write FDatabaseAlias;
    property LastError: string read FLastError write FLastError;
  end;

  /// <summary>
  /// MCP Resource that exposes NexusDB connection status
  /// URI: nexusdb://server
  /// </summary>
  TNexusDBServerResource = class(TMCPResourceBase<TNexusDBServerInfo>)
  protected
    function GetResourceData: TNexusDBServerInfo; override;
  public
    constructor Create; override;
  end;

implementation

uses
  MCPServer.Registration,
  dmnx;

{ TNexusDBServerResource }

constructor TNexusDBServerResource.Create;
begin
  inherited;
  FURI := 'nexusdb://server';
  FName := 'nexusdb_server';
  FDescription := 'NexusDB server connection status and configuration';
  FMimeType := 'application/json';
end;

function TNexusDBServerResource.GetResourceData: TNexusDBServerInfo;
begin
  Result := TNexusDBServerInfo.Create;

  if Assigned(nxmodule) then
  begin
    Result.Connected := nxmodule.IsConnected;
    Result.ServerHost := nxmodule.ServerHost;
    Result.ServerPort := nxmodule.ServerPort;
    Result.DatabaseAlias := nxmodule.AliasName;
    Result.LastError := nxmodule.GetLastError;
  end
  else
  begin
    Result.Connected := False;
    Result.ServerHost := '';
    Result.ServerPort := 0;
    Result.DatabaseAlias := '';
    Result.LastError := 'NexusDB module not initialized';
  end;
end;

initialization
  TMCPRegistry.RegisterResource('nexusdb://server',
    function: IMCPResource
    begin
      Result := TNexusDBServerResource.Create;
    end
  );

end.
