@echo off
rem Your agent on a phone or tablet: a Claude Code session with Remote Control, driven from the
rem Claude app (Code tab) or claude.ai/code. Optional; started minimized by ronin-app\RONIN.ps1
rem when config.json -> launcher.start_remote_control is true.
rem The laptop must stay on; sleep pauses the session and it reconnects on wake. Close this window to end it.
title Agent remote
set NoDefaultCurrentDirectoryInExePath=
rem If started from inside another Claude session, inherited markers disable transcript saving; clear them.
set CLAUDE_CODE_CHILD_SESSION=
set CLAUDECODE=
set "PATH=%USERPROFILE%\.local\bin;%PATH%"
cd /d "%~dp0.."
rem Normal permission mode on purpose: risky tool calls ask for approval on the remote device.
claude --remote-control "Agent" --name "Agent remote"
if errorlevel 1 pause
