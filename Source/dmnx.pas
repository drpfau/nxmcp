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
    FTablePassword: string;
    FUsername: string;
    FPassword: string;
    FAutoConnect: Boolean;
    FTimeout: Integer;
    procedure LoadConfig;
    procedure ConfigureComponents;
    procedure ConfigureSerializer;
  public
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function GetLastError: string;
    property ServerHost: string read FServerHost;
    property ServerPort: Integer read FServerPort;
    property AliasName: string read FAliasName;
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
  LConfigPath: string;
begin
  // Default values
  FServerHost := 'localhost';
  FServerPort := 16000;
  FAliasName := '';
  FTablePassword := '';
  FUsername := 'SYSDBA';
  FPassword := 'masterkey';
  FAutoConnect := True;
  FTimeout := 30000;

  // Find config file next to executable
  LConfigPath := ExtractFilePath(ParamStr(0)) + 'nxconfig.ini';

  if not FileExists(LConfigPath) then
  begin
    GLastError := 'Configuration file not found: ' + LConfigPath;
    Exit;
  end;

  LIniFile := TMemIniFile.Create(LConfigPath);
  try
    // Connection section
    FServerHost := LIniFile.ReadString('Connection', 'ServerHost', FServerHost);
    FServerPort := LIniFile.ReadInteger('Connection', 'ServerPort', FServerPort);

    // Database section
    FAliasName := LIniFile.ReadString('Database', 'AliasName', FAliasName);
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

end.
