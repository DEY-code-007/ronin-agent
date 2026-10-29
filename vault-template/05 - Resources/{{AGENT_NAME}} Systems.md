---
status: active
project: meta
type: reference
---
# {{AGENT_NAME}} Systems

The map of what runs where on this machine. Install folder: `{{INSTALL_DIR}}`. Keep this note current: every time a piece is turned on, off, moved or fixed, update its line with an honest status.

| Piece | Where | Status |
|---|---|---|
| Boot config | `{{INSTALL_DIR}}\CLAUDE.md` | installed |
| Shared settings (no secrets) | `{{INSTALL_DIR}}\config.json` | installed |
| Launcher | `ronin-app\RONIN.ps1` (desktop / Startup shortcut optional) | installed |
| HUD sidecar | `ronin-hud\hud_server.py`, http://127.0.0.1:8797/hud and /sys | installed |
| Face | `ai-visualizer` (upstream), port 8790 | cloned |
| Voice | `backtalk` (upstream), lock port 8791 | cloned, needs setup |
| Telegram | `ronin-telegram\start_telegram.cmd` + official Telegram channel plugin | off until configured |
| Remote Control | `ronin-remote\start_remote.cmd` | off |
| Island | `ronin-island` (Electron) + Claude Code hooks | off until hooks are added |
| Guard | `ronin-guard` (Electron) | installed, run on demand |
| Reminders | `ronin-reminders\remind.py`, events in config.json | off until tasks are registered |
| Daily summary | `ronin-telegram\daily_summary.py` | off |
| Vault backup | `ronin-sync\sync.py` to a PRIVATE git remote | off until a remote is set |

## Secrets (names only, never values)
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` — Windows user environment variables.
- `ELEVENLABS_API_KEY` — Windows user environment variable (optional).

## Known working methods
- Port 8791 belongs to backtalk's single-instance lock. Nothing else may bind it, or the voice refuses to start.
- The Telegram plugin stays disabled at user scope; only the dedicated Telegram session enables it.
