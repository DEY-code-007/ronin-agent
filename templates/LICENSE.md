# License for `templates/` and `vault-template/`

The files in `templates/` (CLAUDE.md, MEMORY.md) and in `vault-template/` (VAULT-INDEX.md, the Daily Note Template and the other skeleton notes) are adapted from the starter templates of **ai-memory-vault** by **Jared Rhodenizer** (@jaredrhod):

- Source: https://github.com/jaredrhod/ai-memory-vault (folder `templates/`)
- Original license: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
- Copyright (c) 2026 Jared Rhodenizer

What was changed: the shipped personality was replaced with `{{AGENT_NAME}}` / `{{OWNER_NAME}}` / `{{LANGUAGE}}` / `{{TONE}}` placeholders filled in by `install.ps1`; a Windows install layout, tool notes for the ronin-agent layer (HUD, Island, Guard, Telegram, reminders, vault sync), a confirm-before-sending rule for connected accounts and a "you are the mechanic" section were added; the vault skeleton got generic starter folders, folder indexes, an Active Priorities note, a Weekly Schedule note and a Systems note. Some passages were shortened.

These adapted files are licensed under **CC BY-SA 4.0** as well: https://creativecommons.org/licenses/by-sa/4.0/

That means: you may copy, adapt and use them, including commercially, as long as you credit the original author (and this project), indicate changes, and license your adapted versions under the same license. The ShareAlike condition applies when you share (publish) adapted versions of the template text; a private vault you never share is just your own use. (This is a plain-language summary, not legal advice; the license text is what counts.)

The rest of this repository (the code) is under the MIT License, see `../LICENSE`.
