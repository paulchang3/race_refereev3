[Setup]
AppName=Race Referee
AppVersion=1.0
DefaultDirName={autopf}\RaceReferee
DefaultGroupName=Race Referee
OutputDir=..\out
OutputBaseFilename=race-referee-setup
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\race_referee.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Race Referee"; Filename: "{app}\race_referee.exe"
Name: "{autodesktop}\Race Referee"; Filename: "{app}\race_referee.exe"; Tasks: desktopicon

[Run]
; Allow phones on the LAN to reach the built-in server
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""Race Referee"" dir=in action=allow program=""{app}\race_referee.exe"" enable=yes profile=any"; Flags: runhidden; StatusMsg: "Configuring firewall..."
Filename: "{app}\race_referee.exe"; Description: "Launch Race Referee"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""Race Referee"""; Flags: runhidden; RunOnceId: "DelFirewallRule"
