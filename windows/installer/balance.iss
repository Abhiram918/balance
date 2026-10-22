
#define AppName "Balance"
#define AppVersion "1.0.0"
#define AppPublisher "Balance"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{9C7F2A1B-4D63-48F2-A851-6B3E7D20C941}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppCopyright=Copyright (C) 2026 Balance
DefaultDirName={localappdata}\Programs\Balance
DefaultGroupName=Balance
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\balance.exe
OutputDir=..\..\dist
OutputBaseFilename=BalanceSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: ".dart_tool\*"

[Icons]
Name: "{group}\Balance"; Filename: "{app}\balance.exe"
Name: "{autodesktop}\Balance"; Filename: "{app}\balance.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\balance.exe"; Description: "Launch Balance"; Flags: postinstall nowait skipifsilent
