# RONIN Guard

Laptop theft alarm for Windows (inspired by the Mac app "MacGuard"). Arm it in a café or library, walk away, and anyone who touches the laptop gets a siren, a webcam photo, and you get a Telegram ping.

## Use
- Install: `npm install` in this folder (install.ps1 does it for you). Electron lands in `node_modules/electron/dist/electron.exe`.
- Start: `npm start`, or `node_modules\electron\dist\electron.exe . --arm` from this folder.
- First start asks for a 4-8 digit PIN (stored as a salted scrypt hash in `data/pin.json`; delete that file to set a new one).
- 10 s grace ("Arming"), then "LOCKED DOWN".
- Trigger = any keyboard/touchpad/mouse input (system idle time drops to 0, plus in-window events), lid closed, charger pulled, trying to switch window / lock the screen / close the window, or a wrong PIN.
- Trigger -> 8 s "Enter PIN" countdown with beeps + a webcam photo. Correct PIN = silent unlock.
- No PIN -> ALARM: red strobe screen, siren (WebAudio) with system volume forced to 100 % unmuted every second, Telegram message + the first-touch photo + more photos. 3 wrong PINs during the countdown = immediate alarm.
- Remote off: `electron.exe "<this folder>" --disarm`. Your agent can run this when you ask it to on Telegram. Telegram pings on arm, alarm and disarm.

## Telegram
Set two Windows **user** environment variables (never put them in a file):
- `TELEGRAM_BOT_TOKEN` - your bot's token from @BotFather.
- `TELEGRAM_CHAT_ID` - your own numeric chat id with the bot.

Without both, Guard still works locally and just logs `tg skipped`.

## How
- `main.cjs`: Electron state machine (setup -> grace -> armed -> countdown -> alarm -> done), kiosk window kept on top, `powerMonitor` (idle time, on-battery, lock-screen), `powerSaveBlocker`, Telegram Bot API.
- `helper.ps1`: Windows PowerShell 5.1 helper. Prints `lid 0/1` from `GUID_LIDSWITCH_STATE_CHANGE` notifications; `max` on stdin sets the default speaker to 100 % and unmutes (Core Audio COM).
- Lid: while armed, the lid close action is set to "Do nothing" (AC+DC, `powercfg`), so closing the lid doesn't sleep the laptop. The original values are backed up in `data/lid-backup.json` and restored on disarm, on quit and on the next start after a crash.
- `GUARD_QUIET=1`: test mode with no siren, no volume change and no Telegram.
- Logs: `data/guard.log`. Photos: `data/shots/`. The whole `data/` folder is git-ignored and must never be published.

## Limits
- Ctrl+Alt+Del can't be blocked by any app; using it still counts as input first, so the countdown/photo starts.
- Killing the process from Task Manager stops the siren, but needs keyboard input first, which already triggered the alarm and photo.
- The laptop must stay awake; the Telegram ping needs internet.
- Taking photos of people may be regulated where you live. Check your local law before relying on the webcam feature.
