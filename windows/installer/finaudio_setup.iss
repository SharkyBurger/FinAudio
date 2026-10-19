; -----------------------------------------------------------------------------
; FinAudio Windows Installer Script (Inno Setup 6 / 7)
; -----------------------------------------------------------------------------
; Generates a modern setup wizard with Start Menu shortcuts,
; desktop shortcut task, custom app icon, and uninstaller.
; -----------------------------------------------------------------------------

#define MyAppName "FinAudio"
#define MyAppVersion "0.3.1"
#define MyAppPublisher "SharkyBurger"
#define MyAppURL "https://github.com/SharkyBurger/FinAudio"
#define MyAppExeName "finaudio.exe"
#define MyAppId "{{E19735F3-08B2-4D9F-9258-39ACA52AADEE}}"

#define ReleaseDir "..\..\build\windows\x64\runner\Release"
#define AppIconFile "..\runner\resources\app_icon.ico"
#define OutputDir "..\..\build\installer"

[Setup]
; Unique application identifier
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Destination directories
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
DisableProgramGroupPage=yes

; Installer output configuration
OutputDir={#OutputDir}
OutputBaseFilename=FinAudio-Setup-v{#MyAppVersion}
SetupIconFile={#AppIconFile}
UninstallDisplayIcon={app}\{#MyAppExeName}

; Compression and styling
SolidCompression=yes
Compression=lzma2/ultra64
WizardStyle=modern

; Architecture constraints (Flutter Windows Desktop is 64-bit x64)
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Permissions: Supports both per-user (no admin required) and system-wide
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Clean update handling
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Main executable
Source: "{#ReleaseDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Dynamic link libraries and plugins
Source: "{#ReleaseDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion

; Native assets manifest (if present)
Source: "{#ReleaseDir}\native_assets.json"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; Flutter assets, ICUDTL data, and fonts
Source: "{#ReleaseDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu shortcut
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"

; Desktop shortcut
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; IconFilename: "{app}\{#MyAppExeName}"

[Run]
; Option to launch FinAudio immediately after setup
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

