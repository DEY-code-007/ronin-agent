<!-- Adapted from templates/MEMORY.md in "ai-memory-vault" by Jared Rhodenizer (@jaredrhod),
https://github.com/jaredrhod/ai-memory-vault , CC BY-SA 4.0. This adapted file is CC BY-SA 4.0 too.

This is Claude Code's OWN auto-loaded memory file. It does NOT go in your vault: it lives in
%USERPROFILE%\.claude\projects\<your install folder with \ and : turned into dashes>\memory\MEMORY.md
(the easiest way to find it: ask Claude Code "where is your MEMORY.md file?").
Replacing its contents with the pointer below redirects Claude Code's native memory into your vault,
so you never end up with two memory layers that drift apart. Move anything already in it into the
vault FIRST, then paste this. install.ps1 prints the exact path. -->

There is no separate memory layer here. The single source of truth is the Obsidian vault, located at:

    {{VAULT_PATH}}

Read the vault from there at the start of every session. Sources of truth, in load order:
- CLAUDE.md (in the working folder you run Claude Code from — NOT in the vault) — boot config: startup sequence + the rules that can't lapse.
- VAULT-INDEX.md (at the vault root) — profile, full rules, the system map.
- Everything else lives in its contextual home in the vault.

To remember something, write it to its place in the vault, never here.
