; ===========================================================================
; Inno Setup script for SimpleChat - a standalone group chat for a private
; circle of friends: an Eiffel server you host yourself and an Eiffel thick
; client, both from the same source tree.
;
; Build:    installer\stage_payload.sh          (stages installer\src\)
; Compile:  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\SimpleChat.iss
; Output:   installer\SimpleChat-Setup.exe
;
; ---------------------------------------------------------------------------
; THE TWO ROLES, AND WHY THE SERVER IS UNTICKED BY DEFAULT
;
;   Everybody gets the client. It is the same executable for the host and for
;   every friend; the only difference between them is which address the window
;   talks to (SERVICE_LOCATOR, D-016).
;
;   The server is an OPTION, off by default, because most installs are a friend
;   who only wants to use the chat. Larry - or a standby host - ticks it.
;   Re-running this installer later with the box ticked ADDS the server to an
;   existing client-only install: that is how a friend is promoted to standby.
;   Inno restores the previously installed component selection on a reinstall,
;   so the user only has to tick the extra one.
;
; ---------------------------------------------------------------------------
; WHY THE SERVER'S WORKING FOLDER IS {commonappdata}\SimpleChat
;
;   Not cosmetic - it is forced by the code, in two places:
;
;   1. CADDY_FRONT_DOOR.make computes
;          executable := current_working_path.extended ("caddy.exe")
;      so caddy.exe is found in the server's WORKING DIRECTORY, not beside the
;      server executable. caddy.exe is therefore installed into that working
;      folder, and every launcher cd's there first.
;
;   2. The same feature computes
;          caddyfile_path := current_working_path.extended (data_dir)
;                                                .extended ("Caddyfile")
;      and PATH.extended carries the precondition `a_name_has_no_root'. An
;      absolute data_dir would violate it - silently, in this lean build, since
;      contracts are compiled out. So data_dir MUST stay relative ("data"), and
;      the working folder is what makes it land somewhere writable.
;
;   Program Files cannot be the working folder: a standard user cannot create
;   the store there. {commonappdata} can be written by the server without
;   elevation and survives uninstall, which is exactly what the room needs.
; ===========================================================================

#define AppVersion     "0.1.3"
#define AppPublisher   "Larry Rix"
#define AppExe         "SimpleChat.exe"
#define ServerExe      "SimpleChatServer.exe"

; ---------------------------------------------------------------------------
; VERIFICATION BUILD - ISCC /DVERIFY=1
;
; A test install MUST NOT share ANY identity with the real product. On
; 2026-09-02 a verification run and Larry's own interactive install of the same
; installer were live on this PC at the same moment; they shared an AppId, so
; they shared one uninstall registration, and the test's uninstall took his
; registration with it. Nothing of his was lost - the data folder is never
; deleted - but the installed product was de-registered underneath him.
;
; Everything two installs could collide over is therefore switched here:
; the AppId (the uninstall key), the visible name, the install directory, the
; Start Menu group, the server's data root, the scheduled task name, the
; per-user client config folder, and the output filename. A verify build is a
; different product that happens to be built from the same source.
;
; The REAL installer is built with no define at all. Never ship a /DVERIFY
; build, and never point a verification at the real names.
; ---------------------------------------------------------------------------
#ifdef VERIFY
  #define AppName      "SimpleChat (verify)"
  #define AppIdGuid    "{{9D4E7B15-3C82-4A6F-B0E9-5F1A28C7D634}"
  #define DirName      "SimpleChat-verify"
  #define ServerRoot   "{commonappdata}\SimpleChat-verify"
  #define TaskName     "SimpleChat Server (verify)"
  #define ClientCfgDir "simple_chat-verify"
  #define OutBase      "SimpleChat-Setup-VERIFY"
#else
  #define AppName      "SimpleChat"
  #define AppIdGuid    "{{B7F42A19-6C3E-4D85-9A0F-1E5C8D2B7436}"
  #define DirName      "SimpleChat"
  #define ServerRoot   "{commonappdata}\SimpleChat"
  #define TaskName     "SimpleChat Server"
  #define ClientCfgDir "simple_chat"
  #define OutBase      "SimpleChat-Setup"
#endif

[Setup]
AppId={#AppIdGuid}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#DirName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
; Per-machine into {autopf}, elevated - the fleet precedent (RixGPT.iss,
; RixQwen.iss both install this way).
PrivilegesRequired=admin
; ...but allow the person to say otherwise, on the command line or in the
; startup dialog. Two reasons this is worth having:
;   - a friend on a locked-down work PC with no admin rights can still install
;     the client, into {localappdata}\Programs\SimpleChat;
;   - it is what makes the installer verifiable without a human clicking a UAC
;     prompt (see installer\VERIFICATION-2026-09-02.md).
; The DEFAULT is unchanged: a plain double-click still elevates and installs
; per-machine. Nothing about the server layout needs elevation either - the
; server writes only under {commonappdata}, which a standard user may create
; and write in.
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
OutputDir=.
OutputBaseFilename={#OutBase}
LicenseFile=src\common\LICENSE-SIMPLECHAT.txt
ShowComponentSizes=yes

; This is an administrative (per-machine) install that ALSO drops one
; convenience file into a per-user area: %APPDATA%\simple_chat\client.toml.
; Inno warns about that, rightly, because in an admin install {userappdata} is
; the profile of whoever elevated - which is not necessarily the person who
; will use the chat.
;
; It is acknowledged rather than avoided, because the consequence is nil: the
; file is written with `onlyifdoesntexist', it holds nothing but an address
; list and a window position, and CLIENT_CONFIG writes its own copy in the
; right profile the first time that user closes the window. The same template
; is installed as {app}\client.toml.template for anyone who wants to place it
; by hand. Nothing is lost if it lands in the wrong profile.
UsedUserAreasWarning=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

; ---------------------------------------------------------------------------
; The first type listed is the default, so a plain Next-Next-Next install is
; CLIENT ONLY. Ticking the server component switches the drop-down to the
; custom type Inno supplies automatically.
; ---------------------------------------------------------------------------
; HOSTING REQUIRES AN ADMINISTRATOR INSTALL. The server component and the
; "host" type both carry Check: IsAdminInstallMode, so in a per-user install
; (/CURRENTUSER, or the startup dialog's "just for me") they do not exist and
; /COMPONENTS=client,server quietly yields the client alone.
;
; That is BY DESIGN, and it is now stated rather than merely happening: the
; server writes to {commonappdata}, registers a machine-wide logon task with
; /rl highest, and puts caddy.exe where an elevated install makes it
; unwritable by a standard user - which is exactly what stops a standard user
; tampering with the executable that elevated task launches. A per-user
; "host" would put that binary somewhere its own user could rewrite.
; The client is per-user-installable precisely because it needs none of that.
; CurStepChanged says so out loud when someone asks for the server anyway.
[Types]
Name: "client"; Description: "Just use the chat (what most people want)"
Name: "host";   Description: "Use the chat AND host the room on this PC"; Check: IsAdminInstallMode

[Components]
Name: "client"; Description: "SimpleChat - the chat window"; \
    Types: client host; Flags: fixed
Name: "server"; Description: "This PC will host the chat room (installs the server, Caddy and the hosting tools)"; \
    Types: host; Check: IsAdminInstallMode

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut for the chat window"; \
    GroupDescription: "Additional shortcuts:"; Components: client; Flags: unchecked
Name: "autostart"; Description: "Start the chat server when Windows starts"; \
    GroupDescription: "Hosting:"; Components: server; Flags: unchecked

; ---------------------------------------------------------------------------
; @claude - the AI member of the room.
;
; TWO ROWS, ONE NAME. Inno allows the same task Name on more than one entry and
; `Check' decides which of them exists, so exactly one is ever shown: the
; ticked one when this PC has Claude Code, the unticked one when it has not.
; That is the whole trick, and it is worth stating because the obvious
; alternative does not work - WizardSelectTasks called from InitializeWizard is
; a no-op (measured on 2026-09-03: the wizard's task list has not been built
; yet, and /TASKS is applied afterwards, so the call is silently thrown away).
; Both rows answer to WizardIsTaskSelected('claudemember') and to
; /TASKS=claudemember.
;
; TICKING IT IS NOT ENOUGH BY ITSELF. The block is written into server.toml
; only when the installer CREATES that file - an existing config is never
; modified, which is this installer's standing rule (see [Files]). And
; SimpleChatServer.exe needs `claude' on the PATH of the account that STARTS
; the server, which is not necessarily the account that installed it: a logon
; scheduled task runs as whoever logs on.
; ---------------------------------------------------------------------------
Name: "claudemember"; \
    Description: "Add @claude to the room (uses this PC's Claude Code subscription; found on this PC: yes)"; \
    GroupDescription: "Hosting:"; Components: server; Check: ClaudeCommandFound
Name: "claudemember"; \
    Description: "Add @claude to the room (uses this PC's Claude Code subscription; found on this PC: no - tick this only if you will install Claude Code before starting the server)"; \
    GroupDescription: "Hosting:"; Components: server; Flags: unchecked; Check: ClaudeCommandMissing

[Dirs]
; The room's home. Never removed by the uninstaller.
Name: "{#ServerRoot}";        Components: server; Flags: uninsneveruninstall
; The server runs as an ordinary user and writes its store here; "Back up
; the room" writes there. Both need modify, and neither holds an executable.
Name: "{#ServerRoot}\data";   Components: server; Flags: uninsneveruninstall; Permissions: users-modify
Name: "{#ServerRoot}\backups"; Components: server; Flags: uninsneveruninstall; Permissions: users-modify

[Files]
; --- client -----------------------------------------------------------------
Source: "src\client\SimpleChat.exe";      DestDir: "{app}"; Components: client; Flags: ignoreversion
Source: "src\client\cairo.dll";           DestDir: "{app}"; Components: client; Flags: ignoreversion
Source: "src\client\LICENSE-ASSETS.md";   DestDir: "{app}"; Components: client; Flags: ignoreversion
Source: "src\common\README.txt";          DestDir: "{app}"; Components: client; Flags: ignoreversion isreadme
Source: "src\common\THIRD-PARTY.md";      DestDir: "{app}"; Components: client; Flags: ignoreversion
Source: "src\common\LICENSE-SIMPLECHAT.txt"; DestDir: "{app}"; Components: client; Flags: ignoreversion

; The Noto emoji artwork: 3,768 PNG files. SW_SHAPING.make looks for them
; beside the RUNNING EXECUTABLE, never in the working directory.
;
; COMPRESSED, not `nocompression' - measured, not assumed. See the compression
; note at the foot of this file: RixQwen.iss stores its payload raw because a
; quantized GGUF really is incompressible; PNG is only deflate, and under solid
; compression lzma2 still finds redundancy across 3,768 similar glyphs.
Source: "src\client\assets\noto-emoji\png\128\*"; DestDir: "{app}\assets\noto-emoji\png\128"; \
    Components: client; Flags: ignoreversion

; The client's own config template, and a copy placed where the client reads
; it. `onlyifdoesntexist' + `uninsneveruninstall': an existing config is never
; overwritten and never removed.
Source: "src\client\client.toml.in";      DestDir: "{app}"; DestName: "client.toml.template"; \
    Components: client; Flags: ignoreversion
Source: "src\client\client.toml.in";      DestDir: "{userappdata}\{#ClientCfgDir}"; DestName: "client.toml"; \
    Components: client; Flags: onlyifdoesntexist uninsneveruninstall

; --- server -----------------------------------------------------------------
Source: "src\server\SimpleChatServer.exe";     DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\run_server.cmd";           DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\start_server.cmd";         DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\start_server_hidden.vbs";  DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\stop_server.cmd";          DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\create_admin.cmd";         DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\create_user.cmd";          DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\reset_password.cmd";       DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\view_log.cmd";             DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\backup_room.cmd";          DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\restore_backup.cmd";       DestDir: "{app}"; Components: server; Flags: ignoreversion
Source: "src\server\HOSTING-GUIDE.html";       DestDir: "{app}"; Components: server; Flags: ignoreversion

; Caddy lives in the SERVER'S WORKING FOLDER, because that is where
; CADDY_FRONT_DOOR looks for it. Its licence ships beside it.
Source: "src\caddy\caddy.exe";    DestDir: "{#ServerRoot}"; Components: server; \
    Flags: ignoreversion uninsneveruninstall
Source: "src\caddy\LICENSE-CADDY"; DestDir: "{#ServerRoot}"; Components: server; \
    Flags: ignoreversion uninsneveruninstall

; The server config template. Never overwrite a host's edited settings, and
; never delete them on uninstall.
; PERMISSIONS. The hosting guide tells the host to edit two lines in this
; file - so the host has to be able to SAVE it. An elevated install leaves
; files under {commonappdata} owned by Administrators and merely READABLE
; by the person running, so "Edit server config" opened Notepad on a file
; that could not be saved: the host could not change the port, which is the
; one setting most likely to need changing.
;
; users-modify is granted HERE, on the config file alone - deliberately NOT
; on caddy.exe, which stays admin-only so a standard user cannot rewrite the
; executable that an elevated /rl highest logon task launches.
Source: "src\server\server.toml.in"; DestDir: "{#ServerRoot}"; DestName: "server.toml"; \
    Components: server; Flags: onlyifdoesntexist uninsneveruninstall; Permissions: users-modify

[Icons]
; --- client -----------------------------------------------------------------
Name: "{group}\{#AppName}";              Filename: "{app}\{#AppExe}"; WorkingDir: "{userappdata}\{#ClientCfgDir}"; \
    Comment: "Open the chat window"; Components: client
Name: "{group}\{#AppName} Read Me";      Filename: "{app}\README.txt"; Components: client
Name: "{autodesktop}\{#AppName}";        Filename: "{app}\{#AppExe}"; WorkingDir: "{userappdata}\{#ClientCfgDir}"; \
    Components: client; Tasks: desktopicon
Name: "{group}\Uninstall {#AppName}";    Filename: "{uninstallexe}"

; --- server -----------------------------------------------------------------
Name: "{group}\{#AppName} Server\Start server";        Filename: "{app}\start_server.cmd"; \
    WorkingDir: "{app}"; Comment: "Start hosting the room on this PC"; Components: server
Name: "{group}\{#AppName} Server\Stop server";         Filename: "{app}\stop_server.cmd"; \
    WorkingDir: "{app}"; Comment: "Stop the chat server"; Components: server
Name: "{group}\{#AppName} Server\Create first admin";  Filename: "{app}\create_admin.cmd"; \
    WorkingDir: "{app}"; Comment: "Make the first account - do this once, before anyone logs in"; Components: server
Name: "{group}\{#AppName} Server\Create user";         Filename: "{app}\create_user.cmd"; \
    WorkingDir: "{app}"; Comment: "Make an account for a friend - accounts are created by you, never self-registered"; Components: server
Name: "{group}\{#AppName} Server\Reset a password";    Filename: "{app}\reset_password.cmd"; \
    WorkingDir: "{app}"; Comment: "Give an existing member a new password - the way back in when somebody, possibly you, has forgotten theirs"; Components: server
Name: "{group}\{#AppName} Server\Server log";          Filename: "{app}\view_log.cmd"; \
    WorkingDir: "{app}"; Comment: "What the server printed"; Components: server
Name: "{group}\{#AppName} Server\Edit server config";  Filename: "{sys}\notepad.exe"; \
    Parameters: """{#ServerRoot}\server.toml"""; Comment: "Turn hosting on by editing two lines"; Components: server
Name: "{group}\{#AppName} Server\Back up the room";    Filename: "{app}\backup_room.cmd"; \
    WorkingDir: "{app}"; Comment: "Make a dated copy to send to your standby host"; Components: server
Name: "{group}\{#AppName} Server\Restore from backup"; Filename: "{app}\restore_backup.cmd"; \
    WorkingDir: "{app}"; Comment: "Put a backup in place as the room"; Components: server
Name: "{group}\{#AppName} Server\Hosting guide";       Filename: "{app}\HOSTING-GUIDE.html"; \
    Comment: "Router, DuckDNS, backups and standby hosts - written for a non-programmer"; Components: server

[Run]
; Register the logon task only when the host asked for it. /rl highest so the
; front door can bind its ports; /f so re-running the installer replaces it
; rather than failing on an existing task.
Filename: "{sys}\schtasks.exe"; \
    Parameters: "/create /tn ""{#TaskName}"" /tr ""wscript.exe \""{app}\start_server_hidden.vbs\"""" /sc onlogon /rl highest /f"; \
    Flags: runhidden waituntilterminated; Components: server; Tasks: autostart; \
    StatusMsg: "Registering the server to start with Windows..."

; ===========================================================================
; THE FINISH SEQUENCE - THE ORDER IS THE FEATURE
;
; WHY IT CHANGED. On 2026-09-02 Larry installed on a PC with no server running
; and no account on it, and the finish page did the one thing it knew how to
; do: it opened the chat window. He was met by a sign-in that could not
; possibly work - there was nothing listening to answer it, and no account to
; answer it with. For a HOST the window is the LAST thing that should happen,
; not the first. So, for a hosting install, pressing Finish now runs:
;
;     1. create the first administrator      (skipped when a room already exists)
;     2. start the server, and say whether it answered
;     3. open the chat window
;
; A client-only install has no step 1 or 2 and keeps "Open SimpleChat now"
; exactly as it was.
;
; WHY THIS IS A SEQUENCE AND NOT THREE THINGS AT ONCE. Inno processes [Run]
; entries IN THE ORDER THEY ARE LISTED, and `waituntilterminated' makes Setup
; wait for each one before going on to the next - Inno Setup help, "[Run] and
; [UninstallRun] sections", under Flags: waituntilterminated ("Setup will wait
; until the process terminates before proceeding to the next entry"). The
; ordering itself is stated in the same section's opening paragraph. Step 3 is
; `nowait' deliberately: the chat window is the last step, and nothing waits
; for the host to close it.
;
; WHY A .cmd NEEDS {cmd}. A batch file is not an executable and cannot be a
; [Run] Filename on its own; it is launched as `{cmd} /c "<script>"'. That also
; gives it a real console - which these two scripts need, because the server
; prints its own prompts to one and reads the answers back from it.
;
; WHY runasoriginaluser ON ALL OF THEM. The install is elevated; every Start
; Menu entry that runs these same scripts is not. The load-bearing case is step
; 2: a server started by the elevated installer could not afterwards be stopped
; by "Stop server" from the Start Menu, because a non-elevated taskkill cannot
; touch an elevated process. Steps 1 and 3 follow for the same reason - the
; room's store and the member's client.toml should belong to the person who
; will use them, not to whoever happened to answer the UAC prompt.
; ===========================================================================

; --- 1. the first administrator --------------------------------------------
; Check: only when the room has no store yet. Re-running the installer over an
; existing room must never offer to mint a second first-admin: the server does
; refuse one, but only AFTER asking for a display name and a password twice,
; and a wizard step whose only possible ending is a refusal is a dead end.
; create_admin.cmd carries the same test itself, for the Start Menu path and as
; a second lock on this one.
Filename: "{cmd}"; Parameters: "/c ""{app}\create_admin.cmd"""; WorkingDir: "{app}"; \
    Description: "Create the first administrator now (a console asks for a name and a password)"; \
    Flags: postinstall skipifsilent waituntilterminated runasoriginaluser; \
    Components: server; Check: RoomHasNoDatabase

; --- 2. start it, and confirm it answers ------------------------------------
; /nopause keeps the wizard moving. The console still prints what /health
; answered, still names whatever program is sitting on the port when there is a
; collision, and still holds itself open long enough to read - it just does not
; wait for a keypress. Without the switch, which is how the Start Menu entry
; runs it, it pauses: right when a human started it deliberately.
Filename: "{cmd}"; Parameters: "/c ""{app}\start_server.cmd"" /nopause"; WorkingDir: "{app}"; \
    Description: "Start the server now"; \
    Flags: postinstall skipifsilent waituntilterminated runasoriginaluser; \
    Components: server

; --- 3. ...and only now the window, with something to sign in to ------------
Filename: "{app}\{#AppExe}"; WorkingDir: "{userappdata}\{#ClientCfgDir}"; Description: "Open {#AppName} now"; \
    Flags: postinstall skipifsilent nowait runasoriginaluser; Components: client

; The hosting guide is reference material, not a step in the sequence. It is
; listed last on purpose: it opens a browser, and it belongs behind the chat
; window rather than in front of it.
Filename: "{app}\HOSTING-GUIDE.html"; Description: "Open the hosting guide"; \
    Flags: shellexec postinstall skipifsilent nowait runasoriginaluser; Components: server

[UninstallRun]
; Remove the logon task. Runs before files are deleted. It is harmless when no
; task was ever registered - schtasks simply reports there is nothing to delete.
Filename: "{sys}\schtasks.exe"; Parameters: "/delete /tn ""{#TaskName}"" /f"; \
    Flags: runhidden waituntilterminated; RunOnceId: "DelChatTask"

; Stop the server before pulling its executable out from under it.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#ServerExe}"; \
    Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "StopChatServer"

[UninstallDelete]
; A log dropped into {app} at run time is not a file the installer recorded,
; so Inno leaves it - and one stray file keeps the whole install folder alive
; after an otherwise clean uninstall. simple_widgets writes its session log to
; the RELATIVE name "sw_session.log", i.e. into the working directory; the
; client shortcuts now start in a per-user folder so nothing should ever land
; here, but a shortcut someone made by hand, or a run from Explorer, still
; could. Sweeping *.log costs nothing and makes the uninstall exact.
Type: files; Name: "{app}\*.log"

; server_root.cmd is written by [Code], not by [Files], so Inno has no record
; of it and would leave it behind - and one stray file keeps the whole install
; folder alive after an otherwise clean uninstall.
Type: files; Name: "{app}\server_root.cmd"

; ---------------------------------------------------------------------------
; NO OTHER [UninstallDelete] ENTRY, DELIBERATELY.
;
; The room - accounts, rooms, every message - lives in
; {commonappdata}\SimpleChat\data, the host's settings in server.toml beside
; it, the backups under backups\, and each member's own settings in
; %APPDATA%\simple_chat\client.toml. None of it is touched by an uninstall.
;
; This follows the fleet precedent: neither RixGPT.iss nor RixQwen.iss deletes
; user data, and an uninstaller that can silently destroy a year of a family's
; conversation is not worth the tidiness. A host who really wants it gone
; deletes C:\ProgramData\SimpleChat by hand, on purpose. The uninstall message
; below says so plainly.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; COMPRESSION: everything is compressed. Measured on 2026-09-02, same payload,
; same machine (see installer\VERIFICATION-2026-09-02.md):
;
;   assets + caddy stored raw (nocompression) ... 76,278,954 b   6.4 s
;   assets compressed, caddy raw ............... 75,577,228 b   6.5 s
;   everything compressed ...................... 37,920,223 b  13.3 s
;
; Halving the download for seven seconds of build time is not a close call.
; The fleet's `nocompression' precedent (RixQwen.iss) is sound for what it
; guards - a quantized GGUF is already at the entropy limit and gains ~5% for
; many minutes. Neither of this installer's big payloads is that: caddy.exe is
; an ordinary uncompressed Go binary, and PNG is only deflate, so solid lzma2
; still finds cross-file redundancy over 3,768 near-identical glyphs.
; ---------------------------------------------------------------------------

[Messages]
ConfirmUninstall=Remove %1 from this PC?%n%nYour chat history, accounts and settings will be KEPT (in C:\ProgramData\SimpleChat and in your own AppData folder), so reinstalling picks up where you left off.%n%nOnly the programs are removed.

[Code]

var
  { True when the server config was ALREADY on this PC before [Files]
    ran. Recorded at ssInstall, which Inno calls just before the installation
    proper starts - so it is the honest answer to "did WE create that file?",
    without depending on whether an AfterInstall runs for an entry that
    `onlyifdoesntexist' skipped. }
  ServerTomlExistedBefore: Boolean;

  { `claude' on the PATH: looked for once, then remembered. ClaudeCommandFound
    is a [Tasks] Check, so it is asked repeatedly. }
  ClaudeSearched, ClaudeIsHere: Boolean;

{ ---------------------------------------------------------------------------
  IS CLAUDE CODE ON THIS PC?

  Only ever used to decide whether the @claude checkbox starts ticked and which
  of its two descriptions is shown. A wrong answer costs nothing that cannot be
  undone by the person looking at the checkbox.

  Read as the INSTALLING user. Setup is normally elevated by UAC from that same
  user's session, so PATH, USERPROFILE and APPDATA are still that user's - but
  an administrator who elevates as a DIFFERENT account will be searched
  instead, and the answer will be about that account. The finding goes to the
  log either way.
  --------------------------------------------------------------------------- }
function ClaudeInFolder(const ADir: String): Boolean;
var
  D: String;
begin
  Result := False;
  if ADir = '' then
    Exit;
  D := RemoveBackslashUnlessRoot(ADir);
  Result := FileExists(D + '\claude.cmd') or FileExists(D + '\claude.exe')
         or FileExists(D + '\claude.bat') or FileExists(D + '\claude');
end;

function ClaudeStarInFolder(const ADir: String): Boolean;
var
  Rec: TFindRec;
begin
  Result := False;
  if ADir = '' then
    Exit;
  if FindFirst(RemoveBackslashUnlessRoot(ADir) + '\claude*', Rec) then
  begin
    try
      repeat
        if Rec.Attributes and FILE_ATTRIBUTE_DIRECTORY = 0 then
        begin
          Result := True;
          Break;
        end;
      until not FindNext(Rec);
    finally
      FindClose(Rec);
    end;
  end;
end;

function ClaudeCommandFound: Boolean;
var
  Rest, Part: String;
  I: Integer;
begin
  if not ClaudeSearched then
  begin
    ClaudeSearched := True;
    ClaudeIsHere := False;

    Rest := GetEnv('PATH');
    if Rest <> '' then
    begin
      Rest := Rest + ';';
      while (Rest <> '') and not ClaudeIsHere do
      begin
        I := Pos(';', Rest);
        if I = 0 then
        begin
          Part := Trim(Rest);
          Rest := '';
        end
        else
        begin
          Part := Trim(Copy(Rest, 1, I - 1));
          Rest := Copy(Rest, I + 1, Length(Rest));
        end;
        { A PATH entry may be quoted. }
        if (Length(Part) >= 2) and (Part[1] = '"') and (Part[Length(Part)] = '"') then
          Part := Copy(Part, 2, Length(Part) - 2);
        if (Part <> '') and ClaudeInFolder(Part) then
          ClaudeIsHere := True;
      end;
    end;

    { The two places Claude Code installs itself that are not always on the
      PATH an elevated process inherits. }
    if not ClaudeIsHere then
      ClaudeIsHere := ClaudeStarInFolder(GetEnv('USERPROFILE') + '\.local\bin');
    if not ClaudeIsHere then
      ClaudeIsHere := FileExists(GetEnv('APPDATA') + '\npm\claude.cmd');

    if ClaudeIsHere then
      Log('SimpleChat: Claude Code found for the installing user - the @claude checkbox starts ticked.')
    else
      Log('SimpleChat: no claude command found for the installing user - the @claude checkbox starts unticked.');
  end;
  Result := ClaudeIsHere;
end;

function ClaudeCommandMissing: Boolean;
begin
  Result := not ClaudeCommandFound;
end;

{ ---------------------------------------------------------------------------
  Does this PC already have a room? The store is the only honest witness: an
  administrator exists only inside it, and the installer never creates it.
  --------------------------------------------------------------------------- }
function RoomHasNoDatabase: Boolean;
begin
  Result := not FileExists(ExpandConstant('{#ServerRoot}\data\simple_chat.db'));
end;

{ ---------------------------------------------------------------------------
  server_root.cmd - the one place the room's home folder is stated.

  The launchers used to say  set "ROOT=%ProgramData%\SimpleChat"  outright, and
  that was survivable while a human ran them from the Start Menu. It stops
  being survivable now that the wizard runs two of them BY ITSELF: a /DVERIFY
  build would have created an administrator in, and started a server against,
  the REAL room - the exact class of collision the verify identity exists to
  prevent (VERIFICATION-2026-09-02.md, section 1).

  So the installer writes the root, and the three scripts it runs read it from
  here. Written at ssPostInstall, which Inno calls after the files are in place
  and BEFORE the postinstall [Run] entries fire, so it is always there in time -
  including for the logon scheduled task, which has no environment to inherit.
  --------------------------------------------------------------------------- }
procedure WriteServerRootFile;
var
  L: TArrayOfString;
  F: String;
begin
  F := ExpandConstant('{app}\server_root.cmd');
  SetArrayLength(L, 7);
  L[0] := '@echo off';
  L[1] := 'REM Written by the SimpleChat installer. Do not edit - it is rewritten';
  L[2] := 'REM on every install. It is the ONE place the room''s home folder is';
  L[3] := 'REM stated, which is what keeps a verification build''s launchers from';
  L[4] := 'REM ever reaching the real room.';
  L[5] := 'set "SIMPLECHAT_ROOT=' + ExpandConstant('{#ServerRoot}') + '"';
  L[6] := '';
  if SaveStringsToFile(F, L, False) then
    Log('SimpleChat: wrote ' + F)
  else
    Log('SimpleChat: COULD NOT write ' + F + ' - the launchers fall back to %ProgramData%\SimpleChat.');
end;

{ ---------------------------------------------------------------------------
  @claude, written into a config THIS INSTALL CREATED.

  Two designs were on the table: post-process the installed file, or ship a
  second template with the block already uncommented. Post-processing wins, and
  the reason is maintenance, not cleverness - one template instead of two that
  have to be kept in step, and the block the host reads afterwards is the SAME
  block the template documents, in the same place, under the same explanation.
  A second variant would have doubled the file that carries every hosting
  instruction in the product, for the sake of nine lines.

  AN EXISTING CONFIG IS NEVER MODIFIED. That is this installer's standing rule,
  and it is not negotiable for a file the host is told to edit by hand: the
  port, the DuckDNS name and the token all live in it.

  The file is pure ASCII as shipped, and this only ever runs on one the
  installer has just written from that template, so the ANSI round-trip through
  LoadStringsFromFile / SaveStringsToFile cannot lose anything.
  --------------------------------------------------------------------------- }
procedure EnableClaudeParticipant;
var
  Cfg, T: String;
  Lines: TArrayOfString;
  I, Start: Integer;
  Changed: Boolean;
begin
  Cfg := ExpandConstant('{#ServerRoot}\server.toml');

  if ServerTomlExistedBefore then
  begin
    Log('SimpleChat: @claude was asked for, but server.toml was already on this PC. ' +
        'An existing config is never modified; the participants block is left ' +
        'commented in place for the host to uncomment.');
    Exit;
  end;
  if not FileExists(Cfg) then
  begin
    Log('SimpleChat: @claude was asked for, but ' + Cfg + ' is not there. Nothing written.');
    Exit;
  end;
  if not LoadStringsFromFile(Cfg, Lines) then
  begin
    Log('SimpleChat: @claude was asked for, but ' + Cfg + ' could not be read. Nothing written.');
    Exit;
  end;

  Start := -1;
  for I := 0 to GetArrayLength(Lines) - 1 do
    if Trim(Lines[I]) = '# [[participants]]' then
    begin
      Start := I;
      Break;
    end;
  if Start < 0 then
  begin
    Log('SimpleChat: @claude was asked for, but the commented participants block was ' +
        'not found in ' + Cfg + '. Nothing written.');
    Exit;
  end;

  { Uncomment from  # [[participants]]  down to the first line that is not a
    "# " comment - which is the end of the block, and the end of the file. }
  Changed := False;
  I := Start;
  while I < GetArrayLength(Lines) do
  begin
    T := Trim(Lines[I]);
    if Copy(T, 1, 2) = '# ' then
    begin
      Lines[I] := Copy(T, 3, Length(T));
      Changed := True;
      I := I + 1;
    end
    else
      Break;
  end;

  if Changed and SaveStringsToFile(Cfg, Lines, False) then
    Log('SimpleChat: @claude enabled in ' + Cfg + ' (' + IntToStr(I - Start) + ' lines uncommented).')
  else
    Log('SimpleChat: @claude could not be written into ' + Cfg + '.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Msg: String;
begin
  { Before a single file is copied: did this PC already have a server config? }
  if CurStep = ssInstall then
    ServerTomlExistedBefore := FileExists(ExpandConstant('{#ServerRoot}\server.toml'));

  if (CurStep = ssPostInstall) and WizardIsComponentSelected('server') then
  begin
    WriteServerRootFile;
    if WizardIsTaskSelected('claudemember') then
      EnableClaudeParticipant;
  end;

  { Hosting was asked for, but this is a per-user install - so the server
    component does not exist and only the client went down. Say so plainly
    rather than letting the host discover an empty Start Menu folder. }
  if (CurStep = ssPostInstall) and not IsAdminInstallMode
     and not WizardIsComponentSelected('server')
     and (Pos('server', Lowercase(ExpandConstant('{param:COMPONENTS|}'))) > 0) then
  begin
    Log('SimpleChat: /COMPONENTS asked for the server, but this is a per-user ' +
        'install, where the server component does not exist. Only the chat ' +
        'window was installed. Hosting requires an administrator install.');
    if not WizardSilent then
      MsgBox('Only the chat window was installed.' + #13#10#13#10 +
             'Hosting the room requires an ADMINISTRATOR install, because the ' +
             'server writes to a machine-wide folder and registers a startup ' +
             'task for the whole PC.' + #13#10#13#10 +
             'To host: run this installer again, allow it to elevate when ' +
             'Windows asks, and tick the hosting box.',
             mbInformation, MB_OK);
  end;

  { The host's finish briefing. It used to list three things for the host to go
    and do by hand; the wizard now DOES the first two of them, so what this
    says is what is about to happen - and what is still theirs. }
  if (CurStep = ssPostInstall) and WizardIsComponentSelected('server')
     and not WizardSilent then
  begin
    Msg := 'The chat server is installed.' + #13#10#13#10 +
           'When you press Finish, this installer will, in order:' + #13#10#13#10;
    if RoomHasNoDatabase then
      Msg := Msg + '  1. open a console and ask you to create the first administrator' + #13#10
    else
      Msg := Msg + '  1. (skipped - this PC already has a room, so it already has ' +
                   'its first administrator)' + #13#10;
    Msg := Msg +
           '  2. start the server, and tell you whether it answered' + #13#10 +
           '  3. open the chat window, so you can sign in with that account' + #13#10#13#10 +
           'Each step waits for the one before it. You can untick any of them on ' +
           'the next page and do it yourself later from the Start Menu, under ' +
           '"SimpleChat Server".' + #13#10#13#10;

    if WizardIsTaskSelected('claudemember') then
    begin
      if ServerTomlExistedBefore then
        Msg := Msg + '@claude: this PC already had a server.toml, and the installer ' +
                     'never edits one. To add @claude, uncomment the [[participants]] ' +
                     'block at the foot of it yourself.' + #13#10#13#10
      else
        Msg := Msg + '@claude has been added to the room. It runs on THIS PC''s own ' +
                     'Claude Code subscription, so the claude command has to be on the ' +
                     'PATH of whichever account STARTS the server.' + #13#10#13#10;
    end;

    Msg := Msg +
           'STILL YOURS TO DO: the room is not reachable from the internet yet - ' +
           'that is deliberate. The hosting guide covers going public (your router ' +
           'and a DuckDNS name) and setting up a standby host; it opens last, ' +
           'behind the chat window.' + #13#10#13#10 +
           'Your settings are at ' + ExpandConstant('{#ServerRoot}') + '\server.toml.';

    MsgBox(Msg, mbInformation, MB_OK);
  end;
end;
