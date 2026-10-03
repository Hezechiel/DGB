# Scrolls — Build Log

Status of the Scrolls (card collection) implementation steps. Design decisions live in `claude/scrolls_decisions.md`; this file only tracks progress. Prompts are saved in the repo under `Claude outputs/`.

| Step | What | Prompt file | Status (2026-10-03) |
|---|---|---|---|
| 1 | Data fields on CardData/HeroData, `LevelCurve`, tags on existing data | `prompt_scrolls_step1_data.md` | Implemented |
| 1b | Type/pantheon folders, recursive `CardDB`, named cards, `era`→`faction`, `faction`→`domain` | `prompt_scrolls_step1b_restructure.md` | Implemented |
| 2 | `PlayerProfile` autoload, starter grant, one deck source for hand and AI | `prompt_scrolls_step2_player_profile.md` | Implemented; Bakula reported it landed well (runtime checks 2–6 were still his to run) |
| 3 | Levels and synergy in matches: per-team match manifest in `BattleManager`, scaling in `configure()` | `prompt_scrolls_step3_levels_in_matches.md` | Prompt written, not yet implemented |
| 4 | `PackData` + `PackRoller` + Shop screen | — | Not started |
| 5 | Collection + Deck screen, `upgrade_card()`, `DeckRules` | — | Not started |
| 6 | Debug panel (reset profile, grant copies; remove `[spawn]` / `[profile]` debug prints) | — | Not started |

## Step 3 design notes

- Spawn messages stay `{card_id, position, team}`. Levels come from a per-team manifest (`BattleManager.set_team_manifest()`), set once by `arena.gd` from `MatchConfig`, which `PreMatchFlow` fills from `PlayerProfile`. The AI mirrors the player's levels.
- Units: level scales HP and damage; synergy (when the card's `domain` equals the god's) can also scale move speed and attack speed. Spells: damage only. Gods: HP, damage, attack speed.
- Attack speed is the simple version (shorter cooldown / recovery after the hit); the rework is postponed.
- No card has a `domain` set yet, so Zeus's synergy affects nothing until an Olympus card (Pegasus, Bronze Automaton) exists.
- Synergy is always on for matching domains; the god passive-condition gate is not built.

## Testing notes

- `profile.json` lives in the Godot user data folder (editor: Project → Open User Data Folder). Until the collection screen exists, levels are tested by editing this file by hand.
- Opening `arena.tscn` directly (F6) has no map, deck or gods; start matches from the main menu.

## Docs to update once the steps are confirmed working

- `architecture.md` §2 (`PlayerProfile` autoload), §3 (folder layout, new fields, recursive scan, deck source, match manifest).
- `game_design.md` §3.1 (deck size), §3.10 (AI deck parity hack retired), §5 and §6.
- `cards_greek.md` §2, §6 and §8 (Open Questions 1 and 2, vocabulary).
- `claude/unit_authoring_guide.md`, `claude/hero_authoring_guide.md` (paths, card naming, `configure()` third argument).
- Repo `CLAUDE.md` (mentions `card_05`, the 12-card deck and the hand-synced AI list).