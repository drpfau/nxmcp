unit dmnx;

interface

uses
  System.SysUtils, System.Classes, System.IniFiles,
  nxsdServerEngine, nxreRemoteServerEngine, nxdb, Data.DB, nxllComponent,
  nxllTransport, nxptBasePooledTransport, nxthHttpTransport, nxtwWinsockTransport,
  System.JSON, DataSet.Serialize, DataSet.Serialize.Config, System.Generics.Collections;

type
  Tnxmodule = class(TDataModule)
    nxDatabase1: TnxDatabase;
    nxSession1: TnxSession;
    nxTable1: TnxTable;
    nxQuery1: TnxQuery;
    nxRemoteServerEngine1: TnxRemoteServerEngine;
    nxWinsockTransport1: TnxWinsockTransport;
    dsTable1: TDataSource;
    dsQuery1: TDataSource;
    procedure DataModuleCreate(Sender: TObject);
    procedure DataModuleDestroy(Sender: TObject);
  private
    FServerHost: string;
    FServerPort: Integer;
    FAliasName: string;
    FDefaultAliasName: string;
    FDefaultServerHost: string;
    FDefaultServerPort: Integer;
    FTablePassword: string;
    FUsername: string;
    FPassword: string;
    FAutoConnect: Boolean;
    FTimeout: Integer;
    FConfigPath: string;
    procedure LoadConfig;
    procedure CreateDefaultConfig;
    procedure ConfigureComponents;
    procedure ConfigureSerializer;
  public
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function GetLastError: string;
    function GetConfigPath: string;
    function GetAliasNames: TStringList;
    function SwitchDatabase(const AAliasName: string;
      const ATablePassword: string = ''): Boolean;
    function SwitchServer(const AServerHost: string; AServerPort: Integer;
      const AAliasName: string = ''; const ATablePassword: string = ''): Boolean;
    property ServerHost: string read FServerHost;
    property ServerPort: Integer read FServerPort;
    property AliasName: string read FAliasName;
    property DefaultAliasName: string read FDefaultAliasName;
    property DefaultServerHost: string read FDefaultServerHost;
    property DefaultServerPort: Integer read FDefaultServerPort;
    property TablePassword: string read FTablePassword;
  end;

var
  nxmodule: Tnxmodule;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

var
  GLastError: string;

procedure Tnxmodule.DataModuleCreate(Sender: TObject);
begin
  GLastError := '';
  LoadConfig;
  ConfigureSerializer;
  ConfigureComponents;

  if FAutoConnect then
    Connect;
end;

procedure Tnxmodule.DataModuleDestroy(Sender: TObject);
begin
  Disconnect;
end;

procedure Tnxmodule.LoadConfig;
var
  LIniFile: TMemIniFile;
begin
  // Default values
  FServerHost := 'localhost';
  FServerPort := 16000;
  FAliasName := '';
  FTablePassword := '';
  FUsername := 'Administrator';
  FPassword := 'NexusDB';
  FAutoConnect := True;
  FTimeout := 3000;

  // Unified config file path
  FConfigPath := ChangeFileExt(ParamStr(0), '.ini');

  // Auto-create config file if it doesn't exist
  if not FileExists(FConfigPath) then
    CreateDefaultConfig;

  LIniFile := TMemIniFile.Create(FConfigPath);
  try
    // Connection section
    FServerHost := LIniFile.ReadString('Connection', 'ServerHost', FServerHost);
    FServerPort := LIniFile.ReadInteger('Connection', 'ServerPort', FServerPort);
    FDefaultServerHost := FServerHost;
    FDefaultServerPort := FServerPort;

    // Database section
    FAliasName := LIniFile.ReadString('Database', 'AliasName', FAliasName);
    FDefaultAliasName := FAliasName;
    FTablePassword := LIniFile.ReadString('Database', 'TablePassword', FTablePassword);

    // Authentication section
    FUsername := LIniFile.ReadString('Authentication', 'Username', FUsername);
    FPassword := LIniFile.ReadString('Authentication', 'Password', FPassword);

    // Options section
    FAutoConnect := LIniFile.ReadBool('Options', 'AutoConnect', FAutoConnect);
    FTimeout := LIniFile.ReadInteger('Options', 'Timeout', FTimeout);
  finally
    LIniFile.Free;
  end;
end;

procedure Tnxmodule.CreateDefaultConfig;
var
  LIniFile: TMemIniFile;
begin
  LIniFile := TMemIniFile.Create(FConfigPath);
  try
    // Header comment
    LIniFile.WriteString('Connection', '; nxmcp - NexusDB MCP Server Configuration', '');

    // Connection section
    LIniFile.WriteString('Connection', '; NXserver host address', '');
    LIniFile.WriteString('Connection', 'ServerHost', 'localhost');
    LIniFile.WriteString('Connection', '; NXserver port (default: 16000)', '');
    LIniFile.WriteInteger('Connection', 'ServerPort', 16000);

    // Database section
    LIniFile.WriteString('Database', '; Database alias as configured on the NXserver', '');
    LIniFile.WriteString('Database', 'AliasName', 'YourAlias');
    LIniFile.WriteString('Database', '; Table passwords, comma separated (leave empty if not used)', '');
    LIniFile.WriteString('Database', 'TablePassword', '');

    // Authentication section
    LIniFile.WriteString('Authentication', '; NexusDB username', '');
    LIniFile.WriteString('Authentication', 'Username', 'your_username');
    LIniFile.WriteString('Authentication', '; NexusDB password', '');
    LIniFile.WriteString('Authentication', 'Password', 'your_password');

    // Options section
    LIniFile.WriteString('Options', '; Automatically connect on startup (1=yes, 0=no)', '');
    LIniFile.WriteBool('Options', 'AutoConnect', True);
    LIniFile.WriteString('Options', '; Connection timeout in milliseconds', '');
    LIniFile.WriteInteger('Options', 'Timeout', 3000);

    // MCP Server section
    LIniFile.WriteString('Server', '; MCP server configuration', '');
    LIniFile.WriteInteger('Server', 'Port', 3000);
    LIniFile.WriteString('Server', 'Host', 'localhost');
    LIniFile.WriteString('Server', 'Name', 'nxmcp');
    LIniFile.WriteString('Server', 'Version', '1.0.0');
    LIniFile.WriteString('Server', 'Endpoint', '/mcp');

    // CORS section
    LIniFile.WriteString('CORS', '; Cross-Origin Resource Sharing configuration', '');
    LIniFile.WriteBool('CORS', 'Enabled', True);
    LIniFile.WriteString('CORS', '; Comma-separated list of allowed origins', '');
    LIniFile.WriteString('CORS', 'AllowedOrigins', 'http://localhost,http://127.0.0.1,https://localhost,https://127.0.0.1');

    // SSL section
    LIniFile.WriteString('SSL', '; SSL/TLS configuration (optional)', '');
    LIniFile.WriteBool('SSL', 'Enabled', False);
    LIniFile.WriteString('SSL', 'CertFile', '');
    LIniFile.WriteString('SSL', 'KeyFile', '');
    LIniFile.WriteString('SSL', 'RootCertFile', '');

    LIniFile.UpdateFile;
  finally
    LIniFile.Free;
  end;
end;

function Tnxmodule.GetConfigPath: string;
begin
  Result := FConfigPath;
end;

procedure Tnxmodule.ConfigureComponents;
begin
  // Configure transport
  nxWinsockTransport1.ServerName := FServerHost;
  nxWinsockTransport1.Port := FServerPort;

  // Configure session
  nxSession1.UserName := FUsername;
  nxSession1.Password := FPassword;

  // Configure database
  nxDatabase1.AliasName := FAliasName;
end;

procedure Tnxmodule.ConfigureSerializer;
begin
  // Configure dataset.serialize for JSON compatibility
  with TDataSetSerializeConfig.GetInstance do
  begin
    // ISO 8601 date/time formats
    Export.FormatDate := 'yyyy-mm-dd';
    Export.FormatTime := 'hh:nn:ss';
    Export.FormatDateTime := 'yyyy-mm-dd"T"hh:nn:ss';

    // Include null values in JSON output
    Export.ExportNullValues := True;
    Export.ExportEmptyDataSet := True;

    // Use lowercase field names for JSON
    CaseNameDefinition := TCaseNameDefinition.cndLowerCamelCase;

    // Import settings
    DateInputIsUTC := False;
  end;
end;

function Tnxmodule.Connect: Boolean;
begin
  Result := False;
  GLastError := '';

  try
    // Activate transport
    if not nxWinsockTransport1.Active then
      nxWinsockTransport1.Active := True;

    // Activate server engine
    if not nxRemoteServerEngine1.Active then
      nxRemoteServerEngine1.Active := True;

    // Open session
    if not nxSession1.Active then
      nxSession1.Open;

    // Open database
    if not nxDatabase1.Connected then
      nxDatabase1.Open;

    // Set table password if configured
    if (FTablePassword <> '') and nxDatabase1.Connected then
    begin
      nxQuery1.Close;
      nxQuery1.SQL.Text := 'SET PASSWORDS ADD ''' + FTablePassword + '''';
      nxQuery1.ExecSQL;
    end;

    Result := nxDatabase1.Connected;
  except
    on E: Exception do
    begin
      GLastError := E.Message;
      Result := False;
    end;
  end;
end;

procedure Tnxmodule.Disconnect;
begin
  try
    // Close in reverse order
    if nxDatabase1.Connected then
      nxDatabase1.Close;

    if nxSession1.Active then
      nxSession1.Close;

    if nxRemoteServerEngine1.Active then
      nxRemoteServerEngine1.Active := False;

    if nxWinsockTransport1.Active then
      nxWinsockTransport1.Active := False;
  except
    on E: Exception do
      GLastError := E.Message;
  end;
end;

function Tnxmodule.IsConnected: Boolean;
begin
  Result := nxDatabase1.Connected;
end;

function Tnxmodule.GetLastError: string;
begin
  Result := GLastError;
end;

function Tnxmodule.GetAliasNames: TStringList;
begin
  Result := TStringList.Create;
  try
    // Session must be active to list aliases (database does not need to be connected)
    if not nxSession1.Active then
      raise Exception.Create('Session is not active. Cannot list aliases.');

    nxSession1.GetAliasNames(Result);
  except
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

function Tnxmodule.SwitchDatabase(const AAliasName: string;
  const ATablePassword: string): Boolean;
var
  LOldAlias: string;
  LOldPassword: string;
begin
  Result := False;
  GLastError := '';

  if Trim(AAliasName) = '' then
  begin
    GLastError := 'Alias name cannot be empty';
    raise Exception.Create(GLastError);
  end;

  // Save current state for rollback
  LOldAlias := FAliasName;
  LOldPassword := FTablePassword;

  try
    // Close open datasets that depend on the database
    if nxQuery1.Active then
      nxQuery1.Close;
    if nxTable1.Active then
      nxTable1.Close;

    // Release cached table handles
    nxSession1.CloseInactiveTables;

    // Close the database connection
    if nxDatabase1.Connected then
      nxDatabase1.Close;

    // Switch to new alias
    FAliasName := AAliasName;
    FTablePassword := ATablePassword;
    nxDatabase1.AliasName := AAliasName;

    // Reopen the database
    nxDatabase1.Open;

    // Apply table password if provided
    if (ATablePassword <> '') and nxDatabase1.Connected then
    begin
      nxQuery1.Close;
      nxQuery1.SQL.Text := 'SET PASSWORDS ADD ''' + ATablePassword + '''';
      nxQuery1.ExecSQL;
    end;

    Result := nxDatabase1.Connected;
  except
    on E: Exception do
    begin
      GLastError := 'Failed to switch to alias "' + AAliasName + '": ' + E.Message;

      // Attempt to rollback to previous alias
      try
        FAliasName := LOldAlias;
        FTablePassword := LOldPassword;
        nxDatabase1.AliasName := LOldAlias;
        nxDatabase1.Open;

        // Reapply previous password if needed
        if (LOldPassword <> '') and nxDatabase1.Connected then
        begin
          nxQuery1.Close;
          nxQuery1.SQL.Text := 'SET PASSWORDS ADD ''' + LOldPassword + '''';
          nxQuery1.ExecSQL;
        end;
      except
        on E2: Exception do
          GLastError := GLastError + ' Rollback also failed: ' + E2.Message;
      end;

      raise Exception.Create(GLastError);
    end;
  end;
end;

function Tnxmodule.SwitchServer(const AServerHost: string; AServerPort: Integer;
  const AAliasName: string; const ATablePassword: string): Boolean;
var
  LOldHost: string;
  LOldPort: Integer;
  LOldAlias: string;
  LOldPassword: string;
begin
  Result := False;
  GLastError := '';

  if Trim(AServerHost) = '' then
  begin
    GLastError := 'Server host cannot be empty';
    raise Exception.Create(GLastError);
  end;

  // Use current port if not specified
  if AServerPort <= 0 then
    AServerPort := FServerPort;

  // Save current state for rollback
  LOldHost := FServerHost;
  LOldPort := FServerPort;
  LOldAlias := FAliasName;
  LOldPassword := FTablePassword;

  try
    // Close open datasets
    if nxQuery1.Active then
      nxQuery1.Close;
    if nxTable1.Active then
      nxTable1.Close;

    // Release cached table handles
    nxSession1.CloseInactiveTables;

    // Full disconnect (database -> session -> engine -> transport)
    Disconnect;

    // Update server connection properties
    FServerHost := AServerHost;
    FServerPort := AServerPort;
    nxWinsockTransport1.ServerName := AServerHost;
    nxWinsockTransport1.Port := AServerPort;

    // Update alias if provided
    if AAliasName <> '' then
    begin
      FAliasName := AAliasName;
      nxDatabase1.AliasName := AAliasName;
    end;

    // Update table password
    FTablePassword := ATablePassword;

    // Full reconnect (transport -> engine -> session -> database + password)
    if not Connect then
      raise Exception.Create(GLastError);

    Result := nxDatabase1.Connected;
  except
    on E: Exception do
    begin
      GLastError := 'Failed to switch to server "' + AServerHost + ':' +
                    IntToStr(AServerPort) + '": ' + E.Message;

      // Attempt to rollback to previous server
      try
        FServerHost := LOldHost;
        FServerPort := LOldPort;
        FAliasName := LOldAlias;
        FTablePassword := LOldPassword;
        nxWinsockTransport1.ServerName := LOldHost;
        nxWinsockTransport1.Port := LOldPort;
        nxDatabase1.AliasName := LOldAlias;

        Connect;
      except
        on E2: Exception do
          GLastError := GLastError + ' Rollback also failed: ' + E2.Message;
      end;

      raise Exception.Create(GLastError);
    end;
  end;
end;

end.
