unit nxmcp.Tool.ListAliases;

interface

uses
  System.SysUtils,
  System.JSON,
  MCPServer.Types,
  MCPServer.Tool.Base;

type
  /// <summary>
  /// Parameters for the list_aliases tool (no parameters needed)
  /// </summary>
  TListAliasesParams = class
  end;

  /// <summary>
  /// MCP Tool that lists all available database aliases on the NexusDB server
  /// </summary>
  TListAliasesTool = class(TMCPToolBase<TListAliasesParams>)
  protected
    function ExecuteWithParams(const Params: TListAliasesParams): string; override;
  public
    constructor Create; override;
  end;

implementation

uses
  System.Classes,
  MCPServer.Registration,
  dmnx;

{ TListAliasesTool }

constructor TListAliasesTool.Create;
begin
  inherited;
  FName := 'list_aliases';
  FTitle := 'List Database Aliases';
  FDescription := 'List all available database aliases on the connected NexusDB server. ' +
                  'Shows the current active alias and the default alias from configuration.';
end;

function TListAliasesTool.ExecuteWithParams(const Params: TListAliasesParams): string;
var
  LResultObj: TJSONObject;
  LAliasesArray: TJSONArray;
  LAliasList: TStringList;
  I: Integer;
begin
  // Check that nxmodule is assigned
  if not Assigned(nxmodule) then
    raise Exception.Create('NexusDB module not initialized');

  // Session must be active to list aliases (database does not need to be connected)
  if not nxmodule.nxSession1.Active then
    raise Exception.Create('Not connected to NexusDB server. Session is not active.');

  LAliasList := nxmodule.GetAliasNames;
  try
    LAliasesArray := TJSONArray.Create;
    for I := 0 to LAliasList.Count - 1 do
      LAliasesArray.Add(LAliasList[I]);

    LResultObj := TJSONObject.Create;
    try
      LResultObj.AddPair('aliasCount', TJSONNumber.Create(LAliasList.Count));
      LResultObj.AddPair('aliases', LAliasesArray);
      LResultObj.AddPair('currentAlias', nxmodule.AliasName);
      LResultObj.AddPair('defaultAlias', nxmodule.DefaultAliasName);
      Result := LResultObj.ToJSON;
    finally
      LResultObj.Free;
    end;
  finally
    LAliasList.Free;
  end;
end;

initialization
  TMCPRegistry.RegisterTool('list_aliases',
    function: IMCPTool
    begin
      Result := TListAliasesTool.Create;
    end
  );

end.
