---
status: active
project: meta
type: index
---
<!-- Adapted from templates/VAULT-INDEX.md in "ai-memory-vault" by Jared Rhodenizer (@jaredrhod), https://github.com/jaredrhod/ai-memory-vault , CC BY-SA 4.0. This adapted template is CC BY-SA 4.0 too (see LICENSE.md in the ronin-agent repo, templates/LICENSE.md). You may delete this comment once the vault is yours. -->
# VAULT INDEX

Read this file at the start of every conversation. It has two jobs: **the profile of the person you work for** (who I am, how I think, how to work with me) and **the map of this vault** (the structure, the indexes, and the rules for maintaining it). The agent's own identity is not here — that lives in the boot file (CLAUDE.md), which survives compaction.

(**AI:** if any [FILL IN: ...] markers remain, this vault isn't set up yet — offer to interview {{OWNER_NAME}} and complete it. Ask about one topic at a time, conversationally. Explain in one line why a section helps before asking about it, make clear that every personal section is optional, and never press for personal details — if they hesitate or skip anything, move on and delete that section. Replace every marker with their real information, written in the first person as if they wrote it, and delete this block and every other parenthetical instruction when done.)

---

## Vault location

This vault lives at `{{VAULT_PATH}}`. If you use Claude Desktop, claude.ai, or any AI other than Claude Code, point it at this path (an MCP / filesystem connector) and tell it "my vault is here". An AI can't read or maintain a vault it can't find.

---

## Who I Am

[FILL IN: your name and whatever context you want the AI to have — what you do, what you're working toward. First person, conversational, concise. Nothing here is required.]

## Key People

[FILL IN: one line per important person in your work and life:]
- **[[Name]]** — [FILL IN: who they are to you]

## [FILL IN: Project 1 name (02 - Projects)]

[FILL IN: what it is, what stage it's in, the key tools it uses. First person.]
- **Status:** [FILL IN: Active / Maintenance / Planning]

## Vault Structure

```
00 - Inbox          ← Capture everything, sort later
01 - Daily Notes    ← Dated logs of what got done, one file per day
02 - Projects       ← One note (or subfolder) per project
03 - Personal       ← Life outside work
04 - Archive        ← Completed projects and old notes
05 - Resources      ← Reference material, templates, the {{AGENT_NAME}} Systems map
Active Priorities.md   ← The single queue of open work
Weekly Schedule.md     ← The recurring week (feeds the HUD, the Island and the daily summary)
```

(Rename or add project folders freely; when you do, update this map, the folder indexes and the project mapping under "How to Determine Each Field" in the same pass.)

## What's Active Right Now

All open work lives in one note: [[Active Priorities]]. Tag each item with its project where it isn't obvious. Check it at the start of every conversation; verify an item's real state before acting on it (a listed item may already be done).

(Optional sections — these get personal, and they're entirely opt-in. Skip or delete any of them freely. The Preferences section after them is worth keeping for everyone.)

## How I Think
[FILL IN: bullets, first person.]

## Health
[FILL IN: only what you want the AI to factor in — routines, goals, constraints. Or delete this section.]

## Daily Routine
[FILL IN: bullets, first person. Fixed commitments go in [[Weekly Schedule]].]

## What I Want
[FILL IN: what you're actually building toward. The AI can only weigh tradeoffs the way you would if it knows this.]

## My Preferences for Working with AI

(Defaults worth keeping. Edit them to match how you actually like to work.)

- **Talk to me in {{LANGUAGE}}.** Notes in this vault can be in whatever language fits; replies to me are in {{LANGUAGE}}.
- **Plain language, no jargon, and be direct.** Don't hedge or over-qualify. Be honest and upfront, always.
- **Don't settle for half-finished work.** Do it right the first time. "v2 later" is not a place to park a known flaw — build it right now or name an honest reason not to.
- **Be a partner, not a yes-man.** Argue your position when you think I'm wrong. When I push back, don't just cave. Make your case, show the tradeoffs, then let me decide. Only change your answer if my argument actually changes your mind.
- **Take it straight.** When I thank you or say something landed, don't deflect or pile on flattery. Just keep building.
- **When I ask "why do you need that?", it's a spec-check, not confusion.** Re-examine the plan, then either fix it or explain with examples.
- **Recommend for my actual setup, not a generic beginner.** Weight what I already use and own.
- **Pull me back from rabbit holes.** When a tangent shows up, decide if it serves the current goal. If not, flag it ("that's a tangent from X — pursue or park?").
- **Restating isn't approving.** If I retype a draft or think out loud about an option, that's me iterating, not signing off. Don't save it as final until I clearly say "lock it". When unsure, ask.
- **Hand me big structured data as a file, not a chat paste.**
- **Most of my guidance is guidelines, not laws.** Use judgment and flag only the divergences that matter. Reserve "Locked" for the rare true invariants.
- **I drive the trust-and-access ramp.** Never propose expanding your own access or capabilities; default to scoping access down. More access comes from me, not from you.

---

## How My Memory Works (for the AI)

This vault is your memory. It is external and effectively unlimited. Do not try to hold all of it at once. Hold only what the current task needs, and trust that everything else is one search away. To find something, start at this index, follow the folder indexes and wikilinks, or search. Knowing a note exists is as good as holding it, because you can retrieve it in one step.

---

## Vault Rules for AI

These rules apply to any AI that reads or writes to this vault.

### Frontmatter and Wikilinks

Every note MUST have YAML frontmatter. When you create a note, include it. When you edit an existing note that's missing or has incomplete frontmatter, fix it as part of that write. Don't stop to add frontmatter to files you're only reading. Code files are the exception — no frontmatter or wikilinks in code.

Never ask me what the frontmatter values should be. Infer them.

### Note format

Simple, legible, readable. No random emojis. Checkboxes are real Markdown checkboxes (`- [ ]` / `- [x]`), never emoji stand-ins. **Append before you create:** default to adding to an existing note rather than spinning up a new one — fewer, fuller notes beat many thin ones.

```yaml
---
status: active
project: [project-slug]
type: plan
---
```

When creating or editing a note, add `wikilinks`:

**Always link:** anyone in Key People · named businesses, products, and platforms · any note this one directly references, extends, or depends on.
**Never link:** generic words just because a note shares the name · the same target twice in one note · the note's own title.

### How to Determine Each Field

**status** — Default `active`. For existing notes infer from content: in progress / has unchecked items → `active`; all done → `completed`; a future "maybe" → `idea`; was active but gone quiet → `parked`; in the Archive folder → `archived`.

**project** — What the note *serves* (folder is the default, but content wins). Mapping:
- `02 - Projects/*` → `projects` (or a per-project slug once you have several: lowercase, hyphenated)
- `03 - Personal/*` → `personal`
- `01 - Daily Notes/*` → `personal`
- `04 - Archive/*` → infer from content / original project
- `05 - Resources/*` → `meta`
- `00 - Inbox/*` → infer from content, else `personal`
- Root-level files → `meta`

**type** — What KIND of document it is (not its topic):
- `index` — a folder index / map-of-content note (or this root index)
- `reference` — a static document meant to be looked up later
- `guide` — step-by-step how-to, runbook, or build instructions
- `plan` — a strategy, phased build, or multi-step project plan (Active Priorities is a plan)
- `log` — a dated session capture or working note (daily notes are logs)

### Valid Field Values

**status:** `active` | `completed` | `parked` | `idea` | `archived`
**project:** `projects` | `personal` | `meta` (add your project slugs here)
**type:** `index` | `reference` | `guide` | `plan` | `log`

### Folder Indexes (keep them in sync)

Every folder that holds substantial content gets an index note named after the folder: `<Folder Name>.md`, frontmatter `type: index`, listing each note in the folder with a one-line description. The index is a contract: when you create, rename, move, or materially change a note, update its folder's index in the same pass.

**When a new folder is created:** create its `<Folder Name>.md` index at the same time, add an entry to the parent folder's index if it has one, and update the **Vault Structure** map in this file in the same pass.

### Renaming and moving notes

- **Moving** a note to another folder is safe — wikilinks resolve by note name. Update both folders' indexes in the same pass.
- **Renaming** a note breaks the `[[links]]` pointing to it unless the rename is done **inside the Obsidian app** ("auto-update internal links"). If the AI must rename a file directly, it has to find and fix every `[[old name]]` reference by hand.

### Checkpoint Persistence

Whenever something changes that a future session would need to know, persist it without being asked: update the relevant note, today's daily note, and (only for a new always-on rule) CLAUDE.md. Then scan the touched folder's index and any cross-referenced notes for drift and fix it in the same pass.

### Archiving

When I say something is done or ask to archive a note: (1) set its frontmatter `status: archived` and save; (2) move it to the Archive folder, same filename; (3) confirm what was archived and where. Always confirm before archiving. Never archive on your own initiative.

### Writing Rules

- **No em-dashes in marketing or published copy you draft for me** (sales pages, emails, posts) — they are a strong "an AI wrote this" tell. Hyphens in normal compound words are fine.
- [FILL IN: your own tone, formatting, and word rules. Delete this line if you have none.]

### Daily Notes

Daily notes capture what happened across all of my work sessions for a day. They live in `01 - Daily Notes/`, in month subfolders named `NN - Month YYYY` (`01 - Daily Notes/06 - June 2026/`) from the very first note. Filename `YYYY-MM-DD.md`. Frontmatter `status: active`, `project: personal`, `type: log`.

Start the body with a human-readable date heading (`# Monday, June 8, 2026`). Then an **`## Index`** block: one bold-topic line per session/entry with a one-sentence outcome. Then the entry body follows `01 - Daily Notes/Daily Note Template.md` (What Got Done · What's Still In Progress · Decisions Made · Notes Touched · Profile Updates). Create every daily note FROM that template; never hand-roll one. The HUD reads the "What Got Done" and "What's Still In Progress" sections, so keep those headings exact.

If today's note already exists from an earlier session, append a new session section (`## Session 2`) and add a line to the Index block — don't overwrite. Timestamp each entry with my local time.

#### Trigger 1: Wrap-Up Signal
Never ask me if I'm done working. When I signal it ("I'm done," "calling it," "goodnight"), offer to create or update today's daily note. Always check the actual current date and time first.

#### Trigger 2: Review Yesterday's Note at Start of Conversation
At the start of every conversation, after reading this index, check yesterday's daily note (or the most recent weekday if today is Monday).
- **If it doesn't exist:** create it from whatever context you have, and say it's reconstructed and may be incomplete. Zero context for that day → assume a day off and skip it. Don't create empty daily notes.
- **If it exists:** read it; if you have context it's missing, append a session section; otherwise leave it alone.

### Living Profile

This file is a living document. Update the profile sections as you learn new things about me through conversation. Updates happen silently and are logged in the daily note under "Profile Updates."

**You can update:** Key People · How I Think · Health · Daily Routine.
**You must NOT update:** Who I Am (only I change it) · the project sections · What's Active Right Now (lives in Active Priorities) · My Preferences for Working with AI · Vault Rules for AI.
**Vault Structure is a special case:** never rewrite it on your own initiative, but when a folder is actually created, renamed, or removed, updating the map is part of that change.

Judgment: a passing mention is not a personality trait. If new info contradicts an entry, update that entry rather than adding a second. Never remove an entry unless explicitly contradicted. Fewer, higher-quality updates.
