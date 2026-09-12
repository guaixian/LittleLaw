; LittleLaw Windows 安装程序(Inno Setup 6)
; CI: & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" tool\installer\littlelaw.iss

[Setup]
AppName=LittleLaw
AppVersion=1.0.0
AppPublisher=guaixian
DefaultDirName={autopf}\LittleLaw
DefaultGroupName=LittleLaw
OutputDir=..\..\app\build\windows-installer
OutputBaseFilename=littlelaw-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\littlelaw.exe

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\LittleLaw"; Filename: "{app}\littlelaw.exe"
Name: "{autodesktop}\LittleLaw"; Filename: "{app}\littlelaw.exe"

[Run]
Filename: "{app}\littlelaw.exe"; Description: "启动 LittleLaw"; Flags: postinstall nowait skipifsilent
