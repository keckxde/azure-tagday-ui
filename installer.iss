; Inno Setup Script for Azure TagDay & DevOps UI
#define MyAppName "Azure TagDay & DevOps UI"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "keckx"
#define MyAppExeName "azure-tagday-ui.exe"

[Setup]
AppId={{D97F648A-85C1-4C5C-9A52-7D7A04A0DF64}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={userappdata}\Programs\AzureTagDayUI
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=AzureTagDayUI-InnoSetup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "dist\azure-tagday-ui\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
