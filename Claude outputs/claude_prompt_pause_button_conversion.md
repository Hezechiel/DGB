# Claude Code Prompt — PauseButton: TouchScreenButton→Control conversion

**Enter Plan Mode first.** Present the full diff for review before touching any files.

## Context

`PlayerCharacter` has already been converted from `TouchScreenButton` to `TextureButton` (done
via a separate prompt, already applied — confirmed live in the project). This prompt does the
same conversion for the remaining `TouchScreenButton` in the HUD: `PauseButton`
(`scenes/hud/HUD.tscn`, top-right corner, hardcoded `position = Vector2(1070, 0)`).

Reason for converting: the project uses `window/stretch/aspect = "expand"` — the visible
canvas rect's *shape* changes across device aspect ratios (unlike `"keep"`, which forces a
fixed shape via letterboxing). `PauseButton`'s hardcoded `Vector2(1070, 0)` is only exactly
correct on a 1170×540-shaped screen and drifts on other aspect ratios. Anchoring to the
top-right corner tracks the actual runtime viewport rect on any device — this is a correctness
fix, not just a style-consistency one.

Note already flagged and still unresolved: `HUD.gd` currently has a stale commented-out line
`#@onready var pause_button: TextureButton = $Root/PauseButton` sitting directly above the live
`TouchScreenButton` declaration, plus a commented-out `_apply_safe_area()` function that
references `pause_button.offset_left/right/top/bottom` (`Control`-only properties). This
suggests `PauseButton` may have been a `TextureButton` before and was reverted back to
`TouchScreenButton` at some point, for an unknown reason — could be unrelated, could be a real
touch-input issue found on device. This prompt does not resurrect `_apply_safe_area()` (out of
scope), but watch closely during VERIFY for anything that looks like a repeat of whatever
caused that original revert.

## Files to inspect first (Plan Mode — read before editing)

- `scenes/hud/HUD.tscn`
- `scripts/hud/HUD.gd`

Confirm current content matches what's described below before applying — if the live files
differ (particularly: confirm `PlayerCharacter` is already `TextureButton` and `PauseButton` is
still `TouchScreenButton`), stop and flag the mismatch instead of guessing.

## Changes

### 1. `scenes/hud/HUD.tscn`

Replace the `PauseButton` node block:

```
[node name="PauseButton" type="TouchScreenButton" parent="Root" unique_id=915885119]
position = Vector2(1070, 0)
scale = Vector2(0.5, 0.5)
texture_normal = ExtResource("2_6lywo")
texture_pressed = ExtResource("3_dui1j")
```

with:

```
[node name="PauseButton" type="TextureButton" parent="Root" unique_id=915885119]
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -100.0
offset_top = 0.0
offset_right = -5.0
offset_bottom = 82.5
texture_normal = ExtResource("2_6lywo")
texture_pressed = ExtResource("3_dui1j")
ignore_texture_size = true
stretch_mode = 5
```

Notes on the numbers (do not change without re-deriving): `UI_pause_btn.png` is 190×165px
(verified). The old `scale = 0.5` rendered it at 95×82.5px, positioned with its right edge 5px
from the canvas right edge (`1170 - (1070+95) = 5`) and flush with the top. This reproduces
that exact box via anchors instead of absolute position: `anchors_preset = 1` is
`PRESET_TOP_RIGHT` (`anchor_top`/`anchor_bottom` stay at their default 0). 95×82.5 preserves
the 190×165 aspect ratio (1.1515) exactly, so `stretch_mode = 5`
(`STRETCH_KEEP_ASPECT_CENTERED`) fills the box with no letterbox gap.

Leave every other node in this file untouched (including `PlayerCharacter`, already converted).

### 2. `scripts/hud/HUD.gd`

Replace:

```gdscript
#@onready var pause_button: TextureButton = $Root/PauseButton
@onready var pause_button: TouchScreenButton = $Root/PauseButton
```

with:

```gdscript
@onready var pause_button: TextureButton = $Root/PauseButton
```

(This both converts the type and removes the now-redundant stale commented-out line above it.)

Leave everything else in this file untouched — `_ready()`, `_update_recenter_button()`,
`_on_pause_pressed()`, `_on_close_requested()`, `_on_exit_requested()`,
`_on_player_character_pressed()`, the commented-out `_apply_safe_area()` block, the
`BUTTON_SIZE`/`MARGIN` constants, and the `player_character_button` declaration are all already
correct and out of scope for this change.

## DO NOT TOUCH

- `PlayerCharacter` node in `HUD.tscn` — already converted, do not modify.
- `player_character_button` onready var, `_update_recenter_button()`,
  `_on_player_character_pressed()` in `HUD.gd` — already correct, do not modify.
- The commented-out `_apply_safe_area()` function and `BUTTON_SIZE`/`MARGIN` constants — do not
  uncomment or wire it up, even though it would now technically work again on a Control. Not
  part of this request.
- `_on_pause_pressed()` — behavior stays exactly as-is, only the node/var type changes.
- `scripts/settings.gd`, `scripts/arena/arena_camera.gd`, `scripts/arena/arena.gd` — no changes
  needed.
- Any other HUD child node (`CardHand`, `EnergyBar`, `Minimap`, `MatchInfoBar`,
  `DeathTelegraph`, `SettingOverlay`) or their scripts.

## Out of scope

- Do NOT resurrect the safe-area inset logic.
- Do NOT touch `PlayerCharacter`/recenter-button logic — already done, separate change.

## VERIFY

1. `grep -n "PauseButton" scenes/hud/HUD.tscn` — confirm the node line reads
   `type="TextureButton"` with the new anchor/offset/stretch properties, and that
   `PlayerCharacter`'s block is unchanged.
2. `grep -n "pause_button" scripts/hud/HUD.gd` — confirm exactly one declaration line, typed
   `TextureButton`, with no leftover commented-out duplicate above it.
3. Run the arena scene: confirm `PauseButton` renders at the same visual size/position as
   before (top-right corner, same margins from the edge, no stretching) and still opens the
   settings overlay and pauses the game on tap — no regressions from the type change.
4. Drag/resize the Godot debug window (F5) to a few different aspect ratios: confirm
   `PauseButton` stays flush against the top-right corner rather than drifting — this is the
   actual regression test for the anchor-vs-hardcoded-position fix.
5. Confirm `PlayerCharacter`/recenter button and every other HUD element are visually unchanged
   (no side effects from this diff).
