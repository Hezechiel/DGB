# Claude Code prompt — Slim CLAUDE.md + split docs/architecture.md

**Use Plan Mode.** Show the full plan (target file list + what moves where) before writing anything. This is a docs-only refactor: no `.gd`, `.tscn`, `.tres` or `project.godot` changes.

## Goal

1. `CLAUDE.md` (~51 KB, 351 lines) is loaded into every Claude Code session. Shrink it to **≤ 10 KB** of always-needed rules, and move the per-system catalogue out.
2. `docs/architecture.md` (~122 KB, 1762 lines) is too big to read whole. Split it into per-topic files under `docs/arch/`, and keep `docs/architecture.md` as a short index at the same path (other tools and the Claude Project instructions point at that path).

**Nothing may be lost.** Every fact in today's two files must end up in exactly one place afterwards. Move text; don't rewrite or "improve" it, beyond minimal edits to merge duplicates and fix cross-references.

## Step 1 — split `docs/architecture.md`

Current sections (line numbers from the current file):

| Section | Lines | New file |
|---|---|---|
| header + §1 Guiding principles | 1–51 | stays in `docs/architecture.md` |
| §2 Autoloads | 52–72 | stays in `docs/architecture.md` |
| §3 Data layer | 73–297 | `docs/arch/data_layer.md` |
| §4 Battle scene structure (incl. Key BattleManager signals) | 298–511 | `docs/arch/battle_scene.md` |
| §5 Combat & movement model | 512–737 | `docs/arch/combat_movement.md` |
| §6 Conventions & known pitfalls | 738–1219 | `docs/arch/conventions_pitfalls.md` |
| §7 Networking posture | 1220–1301 | `docs/arch/networking.md` |
| §8 Main menu / UI shell (Deck screen, Framed overlays, UI Theme, Card Detail) | 1302–1636 | `docs/arch/menu_ui.md` |
| §9 Audio | 1637–end | `docs/arch/audio.md` |

Re-check these boundaries against the actual file before moving anything. If a heading moved, follow the headings, not the line numbers.

Rules:
- Each new file starts with `# <Topic> — DGB architecture`, then one line `> Part of docs/architecture.md — see the index there.`, then the moved section body verbatim. Keep the old `## N.` heading text, minus the number.
- In the new `docs/architecture.md`, keep the header blockquote (update it: the canonical copy is the repo, and drop the "mirrored to the project knowledge" sentence because that mirror no longer exists). Keep §1 and §2 verbatim. Then add a section `## Index` with one line per file: relative link + a one-sentence "read this when…" description. Example: `- [docs/arch/combat_movement.md](arch/combat_movement.md) — unit/hero state machines, targeting, cast-point attacks, knockback; read before touching unit.gd, player.gd, hero_dummy.gd.`
- Fix internal cross-references like "see §5" / "see section 6" in all moved text so they name the new file instead.

## Step 2 — slim `CLAUDE.md`

**Keep in CLAUDE.md** (verbatim, trimmed only where it duplicates something else):
- `# CLAUDE.md` title + the Project Identity section
- Running the Project (incl. the debug key lists)
- Display & Scale Standards table
- Collision Layers table + the 3 lines under it
- Key Conventions (the whole bullet list)
- A new short section `## Where to find details`. It says that system-by-system documentation lives in `docs/architecture.md` (index) and `docs/arch/*.md`, and that design intent lives in `docs/game_design.md`. It tells Claude Code to read only the arch file relevant to the task, not all of them. List the arch files with their one-line descriptions, the same as the index.

**Move out of CLAUDE.md:**
- `## Current Codebase — What Exists` → `### Implemented and working` (lines ~90–261): for each `**Bold heading**` block, find the matching content in the new `docs/arch/*.md` files.
  - If the arch file already covers it, delete the block from CLAUDE.md (no merge needed).
  - If the CLAUDE.md block has facts the arch file lacks, append the **missing facts only** to the best-matching arch file, under a subheading `### <same bold heading> (from CLAUDE.md)`. Mapping hints: Player hero, Combat unit, Turrets, Projectile, Knockback, God skills → `combat_movement.md`. BattleManager, EnergySystem, HealingSystem, MapDB/MapData, ArenaCamera, Card hand, Obstacles, EnemyCardAI, Win/lose, Hero death gating, HUD, Arena root, Match manifest & synergy → `battle_scene.md`. Data layout & CardDB, Card types, Scrolls metadata, PlayerProfile, Pure helpers → `data_layer.md`. Menu screens → `menu_ui.md`. Health bars, Move marker: whichever fits; say which in the plan.
- `### Not yet implemented` → keep as a 2–3 line bullet list in CLAUDE.md (it is short and useful every session).
- `## Architecture — Direction` (lines ~269–330): same rule as above. Most of these subsections already just say "Implemented — see …", so delete those. Move the MOBA match structure tree, the Lane system paragraph, the Spawn protection zones paragraph and the Respawn system paragraph into `battle_scene.md`, unless they're already there.

**In the plan,** list every CLAUDE.md block and its fate: `deleted (already in X)`, `merged into X`, or `kept`.

## DO NOT TOUCH

- Any `.gd`, `.tscn`, `.tres`, `.gdshader`, `.import`, `project.godot`, `export_presets.cfg`
- `docs/game_design.md`, `docs/cards_*.md`, `docs/heroes_*.md`, `docs/scrolls_*.md`, `docs/*.docx`, `docs/*.png`
- `AGENTS.md` (handled separately later)
- Everything in `Claude outputs/`
- `.claude/` settings

## OUT OF SCOPE

- Rewording, reformatting or modernising doc content beyond the merge rules above
- Fixing outdated facts you notice. List them at the end of your report instead.
- Splitting `docs/arch/conventions_pitfalls.md` further (it stays one file for now)
- Any code-comment references to doc sections

## VERIFY (report each result)

1. `wc -c CLAUDE.md` → ≤ 10 240 bytes.
2. `wc -c docs/architecture.md` → ≤ 12 000 bytes; `ls docs/arch/` → exactly the 7 files above.
3. Nothing lost: `cat docs/architecture.md docs/arch/*.md | wc -l` ≥ 1700 (the original was 1762; small header/index changes are fine, but a big drop means text was lost).
4. Spot-check that key identifiers still appear somewhere in `CLAUDE.md` or `docs/`. Each must return ≥ 1 hit:
   `grep -rl "reset_match_state" CLAUDE.md docs/`
   `grep -rl "is_card_target_valid" CLAUDE.md docs/`
   `grep -rl "try_cast_skill" CLAUDE.md docs/`
   `grep -rl "hint_screen_texture" CLAUDE.md docs/`
   `grep -rl "set_team_manifest" CLAUDE.md docs/`
   `grep -rl "protection_zone" CLAUDE.md docs/`
   `grep -rl "SAVE_VERSION" CLAUDE.md docs/`
   `grep -rl "deploy_preview_started" CLAUDE.md docs/`
5. No dangling section refs: `grep -rnE "§[0-9]|section [0-9]" CLAUDE.md docs/architecture.md docs/arch/` → each hit, if any, must point to a file name, not a bare number.
6. Every relative link in `docs/architecture.md` and in `CLAUDE.md`'s "Where to find details" resolves to an existing file.
7. `git diff --stat` shows changes only in `CLAUDE.md`, `docs/architecture.md`, and the new `docs/arch/*.md`.
8. End your report with: the list of CLAUDE.md blocks and their fate, and any outdated facts you noticed but did not fix.
