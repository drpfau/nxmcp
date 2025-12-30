program nxmcp;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  MCPServer.Types,
  MCPServer.IdHTTPServer,
  MCPServer.Settings,
  MCPServer.ManagerRegistry,
  MCPServer.CoreManager,
  MCPServer.ToolsManager,
  MCPServer.ResourcesManager,
  dmnx in 'dmnx.pas' {nxmodule: TDataModule},
  nxmcp.Resource.Server in 'nxmcp.Resource.Server.pas',
  nxmcp.Resource.Tables in 'nxmcp.Resource.Tables.pas',
  nxmcp.Resource.Schema in 'nxmcp.Resource.Schema.pas',
  nxmcp.Tool.ExecuteQuery in 'nxmcp.Tool.ExecuteQuery.pas',
  nxmcp.Tool.GetTableSchema in 'nxmcp.Tool.GetTableSchema.pas',
  // Phase 3 - Data Manipulation
  nxmcp.Tool.ExecuteSQL in 'nxmcp.Tool.ExecuteSQL.pas',
  nxmcp.Tool.GetTableData in 'nxmcp.Tool.GetTableData.pas',
  nxmcp.Tool.InsertRecord in 'nxmcp.Tool.InsertRecord.pas',
  nxmcp.Tool.UpdateRecords in 'nxmcp.Tool.UpdateRecords.pas',
  nxmcp.Tool.DeleteRecords in 'nxmcp.Tool.DeleteRecords.pas',
  // Phase 4 - Schema Management
  nxmcp.Tool.CreateTable in 'nxmcp.Tool.CreateTable.pas',
  nxmcp.Tool.DropTable in 'nxmcp.Tool.DropTable.pas',
  nxmcp.Tool.CopyTable in 'nxmcp.Tool.CopyTable.pas',
  nxmcp.Tool.RenameTable in 'nxmcp.Tool.RenameTable.pas',
  nxmcp.Tool.AddColumn in 'nxmcp.Tool.AddColumn.pas',
  nxmcp.Tool.DropColumn in 'nxmcp.Tool.DropColumn.pas',
  nxmcp.Tool.ModifyColumn in 'nxmcp.Tool.ModifyColumn.pas',
  nxmcp.Tool.CreateIndex in 'nxmcp.Tool.CreateIndex.pas',
  nxmcp.Tool.DropIndex in 'nxmcp.Tool.DropIndex.pas',
  // Phase 5 - Table Maintenance
  nxmcp.Tool.EmptyTable in 'nxmcp.Tool.EmptyTable.pas',
  nxmcp.Tool.PackTable in 'nxmcp.Tool.PackTable.pas',
  nxmcp.Tool.ReindexTable in 'nxmcp.Tool.ReindexTable.pas',
  nxmcp.Tool.RecoverTable in 'nxmcp.Tool.RecoverTable.pas',
  nxmcp.Tool.ChangePassword in 'nxmcp.Tool.ChangePassword.pas',
  nxmcp.Tool.GetAutoIncValue in 'nxmcp.Tool.GetAutoIncValue.pas',
  // Phase 6 - Transactions
  nxmcp.Tool.BatchExecute in 'nxmcp.Tool.BatchExecute.pas',
  // Phase 7 - Utility
  nxmcp.Tool.CountRecords in 'nxmcp.Tool.CountRecords.pas',
  nxmcp.Tool.ListIndexes in 'nxmcp.Tool.ListIndexes.pas',
  nxmcp.Tool.ExplainQuery in 'nxmcp.Tool.ExplainQuery.pas';

var
  Server: TMCPIdHTTPServer;
  Settings: TMCPSettings;
  ManagerRegistry: IMCPManagerRegistry;

begin
  Writeln('nxmcp - NexusDB MCP Server');
  Writeln('==========================');
  Writeln;

  // Initialize NexusDB datamodule
  Writeln('Initializing NexusDB connection...');
  nxmodule := Tnxmodule.Create(nil);
  try
    if nxmodule.IsConnected then
      Writeln('Connected to NexusDB: ', nxmodule.AliasName, ' @ ', nxmodule.ServerHost, ':', nxmodule.ServerPort)
    else
    begin
      Writeln('WARNING: Not connected to NexusDB');
      if nxmodule.GetLastError <> '' then
        Writeln('  Error: ', nxmodule.GetLastError);
    end;
    Writeln;

    // Initialize MCP server
    Settings := TMCPSettings.Create;
    try
      ManagerRegistry := TMCPManagerRegistry.Create;
      ManagerRegistry.RegisterManager(TMCPCoreManager.Create(Settings));
      ManagerRegistry.RegisterManager(TMCPToolsManager.Create);
      ManagerRegistry.RegisterManager(TMCPResourcesManager.Create);

      Server := TMCPIdHTTPServer.Create(nil);
      try
        Server.Settings := Settings;
        Server.ManagerRegistry := ManagerRegistry;
        Server.Start;

        Writeln('MCP Server running on http://', Settings.Host, ':', Settings.Port, Settings.Endpoint);
        Writeln;
        Writeln('Press ENTER to stop...');
        Readln;

        Server.Stop;
      finally
        Server.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    nxmodule.Free;
  end;
end.
