' ===========================================================================
' start_server_hidden.vbs - start the SimpleChat server with NO console window.
'
' This is what the "Start the server when Windows starts" scheduled task runs.
' It launches run_server.cmd hidden and returns at once, so nothing flashes on
' screen at logon and there is no console window for anyone to close by
' accident. The server's own output still goes to server.log, never to a pipe.
' ===========================================================================
Option Explicit

Dim fso, shell, here, command
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

here = fso.GetParentFolderName(WScript.ScriptFullName)
command = shell.ExpandEnvironmentStrings("%ComSpec%") & " /c """ & here & "\run_server.cmd"""

' 0 = hidden window, False = do not wait for it to finish.
shell.Run command, 0, False
