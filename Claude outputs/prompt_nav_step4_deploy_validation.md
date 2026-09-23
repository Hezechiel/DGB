# Claude Code prompt — Navigation step 4: unit deploy must land on the navmesh

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

Navigation steps 1–3 are done: heroes and units follow each map's baked navmesh. Both maps (`GreekPlateauMap.tscn`, `NordPlainsMap.tscn`) now have a correctly baked `NavigationRegion2D`. Its walkable area is the inside of `MapBorder`, minus holes around patches and structures.

The deploy rules don't know about the navmesh yet. `BattleManager.is_deploy_position_valid(pos, team)` only checks `deploy_bounds` (a plain `Rect2`) and the enemy's protection zones. So today a unit card can be dropped:
- **inside a patch**: the squad spawns inside a solid obstacle
- **outside the map border but inside the `bounds` rectangle**: the funnel-shaped border leaves big corners of that rectangle outside the arena

Goal: a unit drop is valid only if the drop point is **on the navmesh**. That one check covers both cases. Spells are **unchanged**; they stay targetable anywhere inside `deploy_bounds`, including over patches.

`is_deploy_position_valid()` is already the single source of truth. `card_hand.gd` calls it (through `is_card_target_valid()`) both for the live ghost colour and on release, and so does `enemy_card_ai.gd`. So the new rule goes **only** into BattleManager, and the red/green ghost updates for free.

## Files to read first

- `scripts/BattleManager.gd`: `deploy_bounds`, `has_navigation()`, `snap_to_navigation()`, `is_deploy_position_valid()`, `is_card_target_valid()`, `spawn_unit()`, `_formation_offset()`
- `scripts/arena/ui/card_hand.gd`: read only, to confirm both call sites go through `is_card_target_valid()`
- `scripts/arena/enemy_card_ai.gd`: `_resolve_play_position()`, `_jittered_deploy_pos()`, `_try_play_cards()`
- `scripts/arena/deploy_ghost.gd`: read only

## Changes

### 1. `scripts/BattleManager.gd`: new helper `is_on_navigation(pos)`

Add it next to `snap_to_navigation()`:

```gdscript
# Tolerancia pre "bod lezi na navmeshi" — map_get_closest_point vrati pre bod
# vnutri polygonu ten isty bod, rozdiel je len float sum.
const NAV_ON_MESH_TOLERANCE_SQ := 1.0 * 1.0

# Lezi bod na navmeshi? False vnutri prekazky (diera v navmeshi) aj mimo
# MapBorder. Bez navmeshu (prvy frame / mapa bez NavigationRegion2D) vrati
# true — ziadne pravidlo na kontrolu, deploy sa sprava ako predtym.
func is_on_navigation(pos: Vector2) -> bool:
	if not has_navigation():
		return true
	return snap_to_navigation(pos).distance_squared_to(pos) <= NAV_ON_MESH_TOLERANCE_SQ
```

### 2. `scripts/BattleManager.gd`: `is_deploy_position_valid()`

Right after the existing `deploy_bounds.has_point(pos)` rejection, add:

```gdscript
	# musi lezat na navmeshi — odmietne drop do patchu aj mimo MapBorder
	if not is_on_navigation(pos):
		return false
```

Update the function's header comment: replace the "future rules: obstacles and structures on the map" line with a note that the navmesh check covers them now. Leave the protection-zone loop and `is_card_target_valid()` exactly as they are. Spells must keep bypassing this function.

Note for the plan (no code needed): the navmesh is inset by the agent radius (10 px), so drops within about 10 px of a patch, structure or the border are also rejected. That's intended, because a unit placed there couldn't path anyway.

### 3. `scripts/BattleManager.gd`: `spawn_unit()` snaps each squad member

The drop point is now validated, but squad members are placed at `pos + _formation_offset(...)`, and a ring offset can still land inside a patch or outside the border when the drop is near an edge. Snap each member's final position:

```gdscript
		unit.global_position = snap_to_navigation(pos + _formation_offset(i, count, card.formation_radius))
```

Add one Slovak comment explaining why, and that this is deterministic: the same navmesh plus the same `{card_id, pos, team}` gives the same positions on both clients, so the network-by-ID principle still holds. `snap_to_navigation()` returns the point unchanged without a navmesh, so nothing changes on a map without one. `_formation_offset()` itself stays untouched.

### 4. `scripts/arena/enemy_card_ai.gd`: snap AI unit positions before validating

The AI picks a random jittered point around its hero. Near a patch, many of those points will now be rejected, and the slot would idle until a later tick happens to roll a valid point. In `_resolve_play_position()`, unit-card branch only, pass the jittered point through `BattleManager.snap_to_navigation(...)` before returning it. The existing `is_card_target_valid()` gate in `_try_play_cards()` stays as the final check. It still rejects a snapped point that lands in a protection zone.

Leave the spell branch unchanged.

## DO NOT TOUCH

- `is_card_target_valid()`: the spell rule stays `deploy_bounds` only.
- `card_hand.gd`, `deploy_ghost.gd`, `denial_zone_overlay.gd`, `arena.gd`: their behavior follows from BattleManager and needs no edits.
- The protection-zone logic, `_protection_zones`, `get_active_protection_zones()`, `reset_match_state()`. There is no new per-match state; `NAV_ON_MESH_TOLERANCE_SQ` is a const.
- `_formation_offset()`, `spawn_hero()`, `cast_spell()`.
- `has_navigation()` / `snap_to_navigation()`: reuse them, don't change them.
- `player.gd`, `hero_dummy.gd`, `unit.gd` and all scenes, including map scenes and NavigationPolygons.
- `enemy_card_ai.gd` beyond the one snap in the unit branch: decision interval, jitter constants, deck, cycle logic.

## Explicitly OUT of scope

- Snapping the **player's** drop instead of rejecting it. The player gets a red ghost and the card stays in hand, same as a protection-zone rejection today.
- Drawing patches or other invalid areas on `DenialZoneOverlay`.
- Any navmesh-based rule for spells.
- Hero spawn / respawn positions.

## VERIFY

Static checks:
- `grep -n "is_on_navigation" scripts/` → defined once in `BattleManager.gd`, used exactly once, inside `is_deploy_position_valid()`.
- `grep -n "snap_to_navigation" scripts/BattleManager.gd` → the definition, its use in `is_on_navigation()`, and one new use in `spawn_unit()`.
- `grep -n "snap_to_navigation" scripts/arena/enemy_card_ai.gd` → one hit, in the unit branch of `_resolve_play_position()`.
- `is_card_target_valid()` is byte-identical to before.
- `git diff --stat` shows only `BattleManager.gd` and `enemy_card_ai.gd`.

Runtime tests. Run on **both** Greek Plateau and Nord Plains, with Debug → Visible Navigation on:
1. Drag a unit card over a patch on your own half → the ghost is red; release → the card stays in hand, no energy spent, nothing spawns.
2. Drag a unit card outside the map border but inside the camera area (e.g. a corner beside the funnel) → the ghost is red; release does nothing.
3. Drag a unit card onto open ground on your half → the ghost is green and the squad spawns there, same as before.
4. Drop a squad card just next to a patch or the border, where the centre is valid → every squad member ends up on walkable ground; none spawns inside the patch or outside the border.
5. The protection zones still work: dropping into an active enemy zone is still red, and destroying a turret still opens exactly its slice.
6. Spell cards: drag a Storm over a patch and outside the border (inside the camera area) → the ghost is green and the cast works, unchanged.
7. Enemy AI: let it play several unit cards while its hero stands near a patch → its units never spawn inside a patch or outside the border, and it keeps playing cards at its usual pace (slots don't stall).
8. No new errors or warnings in the Output panel during a full match.

Stop after this step and report: the diff summary, anything in the plan you changed, and any test you couldn't run.
