# Claude Code prompt — Scrolls step 6: debug cleanup + CLAUDE.md refresh

**Start in Plan Mode. Do not edit anything until I approve the plan.**

**Precondition:** step 5e is merged (`scripts/arena/ui/synergy_icon.gd` exists). If not, stop and tell me.

## Goal

1. **Quiet console.** The Scrolls steps left six always-on debug prints (`[pack]`, `[profile]` ×2, `[synergy]`, `[spawn]` ×2). Route them through one switchable logger that is **off by default**.
2. **Debug-build-only tools.** The arena debug keys stop working in release builds, and the main menu gets three debug keys for the profile (reset, grant copies, toggle the log).
3. **Refresh `CLAUDE.md`**, which still describes the project as it was before the Scrolls work.

No gameplay, data or save-format change. Code comments: the project's mixed Slovak/English style, no diacritics.

## 1. New file `scripts/debug_log.gd`

```gdscript
extends RefCounted
class_name DebugLog

# DebugLog — jeden vypinac pre diagnosticke vypisy Scrolls systemu
# ([pack], [profile], [synergy], [spawn]). Defaultne VYPNUTE, aby konzola
# ostala cista; v debug builde sa zapina klavesom F11 v hlavnom menu.
# Ziadne nody, ziadne autoloady — staticky stav.

static var enabled: bool = false

static func info(tag: String, text: String) -> void:
	if enabled:
		print("[%s] %s" % [tag, text])
```

## 2. Replace the six prints

Same information, same wording after the tag — only the call changes. Build the text with the existing format string.

| File : line | Today | Becomes |
|---|---|---|
| `scripts/ui/shop_overlay.gd` : 66 | `print("[pack] %s -> %s" % [...])` | `DebugLog.info("pack", "%s -> %s" % [...])` |
| `scripts/PlayerProfile.gd` : 232 | `print("[profile] migrated save v1 -> v2")` | `DebugLog.info("profile", "migrated save v1 -> v2")` |
| `scripts/PlayerProfile.gd` : 344 | `print("[profile] active_hero=…")` | `DebugLog.info("profile", "active_hero=…")` |
| `scripts/BattleManager.gd` : 98 | `print("[synergy] team=…")` | `DebugLog.info("synergy", "team=…")` |
| `scripts/BattleManager.gd` : 497 | `print("[spawn] %s team=…")` (unit) | `DebugLog.info("spawn", "%s team=…")` |
| `scripts/BattleManager.gd` : 574 | `print("[spawn] %s team=…")` (god) | `DebugLog.info("spawn", "%s team=…")` |

`push_warning` / `push_error` calls everywhere stay exactly as they are — they report real problems, not diagnostics.

## 3. `scripts/arena/arena.gd` — debug keys only in debug builds

In `_input()` (the block handling **U / I / Y / P / H / J**):

- Add at the very top of the function: `if not OS.is_debug_build(): return`.
- Fix the stale comment `# --- DEBUG energia (docasne, kym nie je energy bar — krok 2) ---` → `# --- DEBUG energia (len debug build) ---`. Same "(len debug build)" wording on the death and audio debug comments.
- The six `print(...)` lines inside this block stay plain `print` — they are direct answers to a key press, not background noise.

Nothing else in `arena.gd` changes.

## 4. `scripts/ui/main_menu.gd` — three profile debug keys

Add an `_unhandled_key_input(event: InputEvent)` (the file has no key handling today):

```gdscript
# --- DEBUG profil (len debug build) ---
# F9  = reset profilu na starter
# F10 = +1 kopia kazdej ziskatelnej karty a kazdeho boha
# F11 = zapni/vypni DebugLog vypisy
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F9:
			PlayerProfile.reset_profile()
			print("[debug] profile reset to starter")
		KEY_F10:
			var ids: Array[StringName] = []
			for id in CardDB.list_card_ids():
				if CardDB.get_card(id).obtain_source != 0:
					ids.append(id)
			ids.append_array(CardDB.list_hero_ids())
			PlayerProfile.grant_cards(ids)
			print("[debug] granted +1 copy of %d cards/gods" % ids.size())
		KEY_F11:
			DebugLog.enabled = not DebugLog.enabled
			print("[debug] DebugLog %s" % ("ON" if DebugLog.enabled else "OFF"))
```

These go through the existing public profile API only (`reset_profile`, `grant_cards`). Nothing else in `main_menu.gd` changes.

## 5. Refresh `CLAUDE.md`

`CLAUDE.md` is your own technical reference for this repo. Bring it in line with the code as it is **now** — read the code, do not copy from this prompt blindly. Keep the document's existing structure, tone and level of detail; edit sections in place, add new subsections under "Implemented and working", and remove statements that are no longer true. Do not shorten or rewrite sections that are still accurate.

Known stale statements to fix (verify each against the code):

- **Debug keys:** `card_05` is gone (the keys use `card_greek_hoplite`); they now work only in debug builds; add the main-menu keys F9 / F10 / F11.
- **Card hand:** no longer a "12-card deck"; the deck is the player's active deck (7 cards) read from `MatchConfig.local_deck_card_ids`. `CardHand.tscn` holds no deck.
- **EnemyCardAI:** no hardcoded deck-id list "kept in sync by hand"; it reads `MatchConfig.opponent_deck_card_ids`.
- **`configure(data, team)`** for units and both hero scripts now takes a third argument, `stat_mods`; `SpellZone.configure()` takes a damage multiplier.
- **HUD:** says "No minimap exists" — a `Minimap` node is in `HUD.tscn`; also add `SynergyIcon`. Remove "Minimap" from "Not yet implemented" if the code confirms it works.
- **Arena root:** the direct children list and `_ready()` description — add the match manifest calls, the synergy energy modifier and `hud.synergy_icon.configure("player")`.
- **Heroes are no longer hardcoded** constants in `arena.gd`; they come from `MatchConfig`.

New things `CLAUDE.md` does not mention at all — add concise entries in the same style as the existing ones:

- Data layout `data/<type>/<pantheon>/` and the recursive `CardDB` scan that skips `frames/`; named cards (`card_greek_<name>`); `data/packs/`, `data/progression/level_curve.tres`.
- `CardData` / `HeroData` Scrolls fields: `rarity`, `obtain_source`, `faction` (pantheon), `domain`, `tags`, `description`; gods: `forbidden_tags`, `synergy_tag`, `synergy_count`, `synergy_bonuses`.
- Autoload `PlayerProfile` (`user://profile.json`, save version 2, a deck per god + active god, the mutation API) and its place in the autoload order.
- `LevelCurve`, `PackData`, `PackRoller`, `DeckRules`, `DebugLog` — the pure/static helpers, with the rule that they hold no nodes and call no autoloads.
- `BattleManager` match manifest (`set_team_manifest`, levels, synergy evaluated once at match start, `get_synergy_status`).
- Menu screens: `ShopOverlay`, `DeckOverlay` + `DeckTile`, `EncyclopediaOverlay`, `CardFlashcard`, and which main-menu button opens which.
- Key Conventions: add "spawn messages stay `{card_id, position, team}` — levels and synergy are looked up from the per-team manifest, never passed per spawn"; "the player collection changes only through `PlayerProfile`'s mutation API"; "UI that needs match state the HUD cannot have at its own `_ready()` gets a `configure()` call from `arena.gd`".

Do **not** touch `AGENTS.md`.

## DO NOT TOUCH

- Every gameplay script not named above: `unit.gd`, `player.gd`, `hero_dummy.gd`, `spell_zone.gd`, `card_hand.gd`, `enemy_card_ai.gd`, `EnergySystem.gd`, `HealingSystem.gd`, `HeroAI.gd`, `MatchConfig.gd`, `CardDB.gd`, `deck_rules.gd`, `pack_roller.gd`, `level_curve.gd`.
- In `PlayerProfile.gd`, `BattleManager.gd` and `shop_overlay.gd`: everything except the listed print lines.
- All UI overlays other than `main_menu.gd`; every `.tscn`.
- Everything under `data/` and `assets/`, `project.godot`, `docs/`, `AGENTS.md`, `Claude outputs/`.

## OUT OF SCOPE (do not build, even partially)

- An on-screen debug panel or cheat menu; debug keys on Android; a setting in the options screen.
- Log levels, categories you can switch individually, writing logs to a file.
- Removing or changing `push_warning` / `push_error` calls, or the arena debug keys' behaviour.
- Any refactor "while you are there"; any change to gameplay, data or the save format.
- Updating `docs/` or `AGENTS.md`.

## VERIFY

Static checks (run and report output):

1. `grep -rn "print(" --include=*.gd scripts/ | grep -v "^\s*#\|#print\|# print"` — the only remaining hits are the six in `arena.gd::_input()`, the three in `main_menu.gd::_unhandled_key_input()` and the one inside `debug_log.gd`.
2. `grep -rn "DebugLog.info" --include=*.gd scripts/` — exactly six calls: `shop_overlay.gd` (1), `PlayerProfile.gd` (2), `BattleManager.gd` (3).
3. `grep -n "is_debug_build" scripts/arena/arena.gd scripts/ui/main_menu.gd` — one in each.
4. `grep -n "card_05\|12-card\|kept in sync by hand\|No minimap exists" CLAUDE.md` — no match.
5. `grep -n "PlayerProfile\|DeckRules\|PackRoller\|LevelCurve\|DebugLog\|synergy" CLAUDE.md` — each is documented.
6. `git diff --stat` — only `debug_log.gd` (new), `shop_overlay.gd`, `PlayerProfile.gd`, `BattleManager.gd`, `arena.gd`, `main_menu.gd`, `CLAUDE.md`; the three logic files change by the print lines only.

Runtime checks (I run these in the Godot editor — list them for me, do not claim them as done):

1. Launch and play a match: the console shows no `[profile]`, `[synergy]`, `[spawn]` or `[pack]` lines.
2. In the main menu press **F11**, then start a match: the lines are back. Press F11 again: silent.
3. **F10** in the main menu: every card and god gains a copy (check the Encyclopedia — several cards show "Ready").
4. **F9**: the profile is back to Zeus + the seven starter cards at level 1.
5. Arena keys **U / I / Y / P / H / J** still work in the editor.
6. Read the refreshed `CLAUDE.md` once: nothing in it contradicts what the game does.
