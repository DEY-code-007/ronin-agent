# NOTICE

ronin-agent is a layer on top of open-source work by **Jared Rhodenizer** (@jaredrhod). This file explains what comes from where and under which license.

## 1. Our own code: MIT
`install.ps1`, `config.example.json`, `ronin-app/`, `ronin-hud/`, `ronin-island/`, `ronin-guard/`, `ronin-telegram/`, `ronin-reminders/`, `ronin-sync/`, `ronin-remote/`. Written for this project; it contains no code copied from the upstream repositories. It talks to the upstream tools only by starting them as separate programs or reading/serving local HTTP and files. License: MIT, see `LICENSE`.

## 2. Templates: CC BY-SA 4.0 (adapted, ShareAlike)
`templates/CLAUDE.md`, `templates/MEMORY.md` and everything in `vault-template/` are adapted from the starter templates in **ai-memory-vault** (https://github.com/jaredrhod/ai-memory-vault, `templates/`), Copyright (c) 2026 Jared Rhodenizer, licensed CC BY-SA 4.0. The adapted versions stay under CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/). What was changed is listed in `templates/LICENSE.md`; each adapted file also carries a short credit comment.

## 3. Upstream projects: not included, cloned at install time
`install.ps1` runs `git clone` on these original repositories. Nothing from them is stored in this repository:

| Project | URL | License |
|---|---|---|
| fullstack-agent | https://github.com/jaredrhod/fullstack-agent | AGPL-3.0 |
| backtalk | https://github.com/jaredrhod/backtalk | AGPL-3.0 |
| ai-visualizer | https://github.com/jaredrhod/ai-visualizer | AGPL-3.0 |
| ai-memory-vault | https://github.com/jaredrhod/ai-memory-vault | CC BY-SA 4.0 |

If you modify those projects and offer them to others (including over a network, for the AGPL ones), their license terms apply to your modified versions.

## 4. Third parties used at runtime
Electron (MIT, installed by npm), the official Claude Code Telegram channel plugin, the Telegram Bot API, Open-Meteo (optional weather) and ElevenLabs (optional voice) are used as external services or dependencies and are not part of this repository.
