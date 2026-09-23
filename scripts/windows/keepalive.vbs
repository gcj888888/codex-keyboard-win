' keepalive.vbs -- Windows-side keepalive: poke WSL periodically so the
' distro is not reclaimed while idle.
'
' Why: WSL2 reclaims an idle distro, vmmem exits, the systemd services inside
'      WSL disappear with it, and the Host goes offline. The .wslconfig option
'      instanceIdleTimeout=-1 does not reliably work, so this script pokes WSL
'      every 5 minutes instead.
'
' Usage:
'   1) Put this file in your Startup folder (Win+R -> shell:startup)
'   2) Or just double-click it
' Stop: end wscript.exe in Task Manager
'
' NOTE: kept ASCII-only on purpose. Windows Script Host reads .vbs as ANSI
'       unless the file is UTF-16LE, so non-ASCII comments here can break it.
'       Chinese documentation lives in docs/Windows-repro-guide.

Set sh = CreateObject("WScript.Shell")
Do While True
    ' Silent run (0 = hidden window, False = do not wait)
    On Error Resume Next
    sh.Run "wsl.exe -d Ubuntu -- exec true", 0, False
    On Error GoTo 0
    WScript.Sleep 300000   ' 5 minutes
Loop
