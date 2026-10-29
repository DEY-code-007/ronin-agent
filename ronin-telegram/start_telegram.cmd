@echo off
rem Your agent on Telegram: a Claude Code session with the official Telegram channel plugin.
rem Started minimized by ronin-app\RONIN.ps1 (or double-click this file). Close the window to take the agent off Telegram.
rem The plugin must stay DISABLED globally (every session would otherwise poll the bot and fight over it);
rem telegram-settings.json enables it for this session only.
rem
rem SECURITY: this session runs with --permission-mode bypassPermissions because nobody can click
rem "allow" on a phone. That is only safe when the plugin's allowlist contains your own Telegram
rem user id and nobody else's. Run /telegram:access in a normal Claude Code session to check it.
title Agent telegram
set NoDefaultCurrentDirectoryInExePath=
rem The plugin's MCP server runs on Bun; make sure common install locations are on PATH.
set "PATH=%USERPROFILE%\.bun\bin;%LOCALAPPDATA%\Microsoft\WinGet\Packages\Oven-sh.Bun_Microsoft.Winget.Source_8wekyb3d8bbwe\bun-windows-x64;%USERPROFILE%\.local\bin;%PATH%"
if not exist "%~dp0telegram-prompt.md" (
  echo telegram-prompt.md is missing. Run install.ps1 again, or copy telegram-prompt.template.md and fill in the placeholders.
  pause
  exit /b 1
)
cd /d "%~dp0.."
claude --channels plugin:telegram@claude-plugins-official ^
  --settings "%~dp0telegram-settings.json" ^
  --permission-mode bypassPermissions ^
  --append-system-prompt-file "%~dp0telegram-prompt.md" ^
  --name "Agent telegram"
if errorlevel 1 pause
