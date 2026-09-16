# Claude Code Prompt — HUD buttons: TouchScreenButton→Control conversion (PauseButton + PlayerCharacter) + recenter-button visibility

**Enter Plan Mode first.** Present the full diff for review before touching any files.

**This supersedes the previous version of this prompt (PlayerCharacter-only).** Neither button
has been converted yet in the live project, so this single prompt now covers both.

## Context

`scenes/hud/HUD.tscn` has two `TouchScreenButton` nodes under `Root`: `PauseButton`
(top-right, hardcoded `position = Vector2(1070, 0)`) and `PlayerCharacter` (no position set —
becoming the map-recenter button, wired via `HUD.recenter_camera_requested` →
`ArenaCamera.recenter_on_player()`, already implemented and untouched by this prompt).

Both convert from `TouchScreenButton` (`Node2D`, no anchors) to `TextureButton` (`Control`),
for two concrete reasons:

1. The project uses `window/stretch/aspect = "expand"` — the visible canvas rect's *shape*
   changes across device aspect ratios (unlike `"keep"`, which forces a fixed shape via
   letterboxing). A hardcoded pixel position (`PauseButton`'s `Vector2(1070, 0)`, or a
   hypothetical hardcoded Y for `PlayerCharacter`) is only exactly correct on a
   1170×540-shaped screen and drifts on other aspect ratios. Anchors track the actual runtime
   viewport rect on any device.
2. `TouchScreenButton` does not consume its own touch event, which is why
   `HUD._on_player_character_pressed()` currently calls `InputR.suppress_next_release()` to
   stop the tap from also triggering `arena.gd`'s tap-to-move. A `Control`-based button
   consumes GUI input automatically (default `mouse_filter = MOUSE_FILTER_STOP`), so that
   workaround can be removed for `PlayerCharacter`. (`PauseButton` doesn't have an equivalent
   workaround today, so there's nothing to remove there — just confirm in VERIFY that pausing
   still works cleanly.)

Note found in `HUD.gd`: a commented-out `@onready var pause_button: TextureButton = ...` line
and a commented-out `_apply_safe_area()` function that references `pause_button.offset_left/
right/top/bottom` (`Control`-only properties) suggest `PauseButton` may have been a
`TextureButton` at some earlier point and was reverted to `TouchScreenButton`. The reason for
that revert is unknown — could be unrelated, could be a real touch-input issue found on
device. This prompt does not resurrect `_apply_safe_area()` (out of scope, wasn't asked for),
but flag anything that looks like a repeat of whatever caused that original revert during
testing.

`PlayerCharacter`'s recenter button also gets its final visibility behavior in this prompt:
hidden when `Settings.lock_camera == true`, visible at a fixed anchored position (vertical
middle of the left screen border) when `false`. No third/default position — it is only ever
one of those two states.

## Files to inspect first (Plan Mode — read before editing)

- `scenes/hud/HUD.tscn`
- `scripts/hud/HUD.gd`

Confirm current content matches what's described below before applying — if the live files
differ, stop and flag the mismatch instead of guessing.

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

Replace the `PlayerCharacter` node block:

```
[node name="PlayerCharacter" type="TouchScreenButton" parent="Root" unique_id=1146393216]
scale = Vector2(0.5, 0.5)
texture_normal = ExtResource("4_6lywo")
texture_pressed = ExtResource("5_dui1j")
```

with:

```
[node name="PlayerCharacter" type="TextureButton" parent="Root" unique_id=1146393216]
anchors_preset = 4
anchor_top = 0.5
anchor_bottom = 0.5
offset_left = 12.0
offset_top = -42.5
offset_right = 107.0
offset_bottom = 42.5
texture_normal = ExtResource("4_6lywo")
texture_pressed = ExtResource("5_dui1j")
ignore_texture_size = true
stretch_mode = 5
```

Notes: `UI_user.png` is 190×170px. Old scaled size was 95×85px — reproduced via the same
`ignore_texture_size` + `stretch_mode = 5` technique (95×85 matches the 190×170 aspect ratio
exactly, 1.1176). `anchors_preset = 4` is `PRESET_CENTER_LEFT` (`anchor_left`/`anchor_right`
stay at their default 0). `offset_left = 12.0` matches the Minimap panel's `offset_left = 12`
for edge alignment with the other HUD-edge elements. `offset_top = -42.5` /
`offset_bottom = 42.5` centers the 85px-tall box exactly on the parent's vertical center.

Leave every other node in this file untouched.

### 2. `scripts/hud/HUD.gd`

Replace the two onready-var lines (this also removes the stale commented-out alternate
declaration for `pause_button`):

```gdscript
#@onready var pause_button: TextureButton = $Root/PauseButton
@onready var pause_button: TouchScreenButton = $Root/PauseButton
@onready var setting_overlay: SettingsOverlay = $SettingOverlay
@onready var player_character_button: TouchScreenButton = $Root/PlayerCharacter
```
→
```gdscript
@onready var pause_button: TextureButton = $Root/PauseButton
@onready var setting_overlay: SettingsOverlay = $SettingOverlay
@onready var player_character_button: TextureButton = $Root/PlayerCharacter
```

In `_ready()`, add the settings subscription for the recenter button's visibility (mirrors the
existing `Settings.settings_changed.connect(...)` pattern already used in
`arena_camera.gd`):

```gdscript
func _ready() -> void:
	#_apply_safe_area()
	pause_button.pressed.connect(_on_pause_pressed)
	player_character_button.pressed.connect(_on_player_character_pressed)
	setting_overlay.closed_requested.connect(_on_close_requested)
	setting_overlay.exit_requested.connect(_on_exit_requested)
	Settings.settings_changed.connect(_update_recenter_button)
	_update_recenter_button()
```

Add the new function (placement: right after `_ready()`, before the commented-out
`_apply_safe_area()` block):

```gdscript
# Recenter-na-hraca button je viditelny len ked kamera NIE je zamknuta na
# hrdinu (v lock rezime je recentrovanie zbytocne — kamera uz hrdinu sleduje).
# Ziadna ina pozicia neexistuje — button je bud skryty, alebo na fixnej
# ukotvenej pozicii zo sceny (stred laveho okraja obrazovky).
func _update_recenter_button() -> void:
	player_character_button.visible = not Settings.lock_camera
```

Update `_on_player_character_pressed()` — remove the now-unnecessary suppress call:

```gdscript
func _on_player_character_pressed() -> void:
	# TextureButton (Control) spotrebuje touch event sam (mouse_filter = STOP),
	# narozdiel od povodneho TouchScreenButton uz netreba
	# InputR.suppress_next_release()
	recenter_camera_requested.emit()
```

Leave everything else in this file untouched (`_on_pause_pressed`, `_on_close_requested`,
`_on_exit_requested`, the commented-out `_apply_safe_area`, the placeholder comments at the
bottom, the `BUTTON_SIZE`/`MARGIN` constants).

## DO NOT TOUCH

- `scripts/arena/arena_camera.gd` — `recenter_on_player()` is already correct, no changes.
- `scripts/InputR.gd` (or wherever `InputR` is defined) — do not remove or alter
  `suppress_next_release()` itself; only its call site in `HUD.gd` is removed. It's still used
  elsewhere (e.g. `base.gd` uses the related `suppress_release_of_touch()`).
- `scripts/settings.gd` — no changes needed, `lock_camera`/`settings_changed` already exist.
- The commented-out `_apply_safe_area()` function and `BUTTON_SIZE`/`MARGIN` constants — do not
  uncomment or wire it up, even though it would now technically work again on a Control. Not
  part of this request.
- Any other HUD child node (`CardHand`, `EnergyBar`, `Minimap`, `MatchInfoBar`,
  `DeathTelegraph`, `SettingOverlay`) or their scripts.
- `scripts/arena/arena.gd` — no changes needed; a `Control` consuming its own input requires
  no cooperation from `arena.gd`'s tap-to-move handler.

## Out of scope

- Do NOT resurrect the safe-area inset logic.
- Do NOT add any animation/transition to the recenter button's show/hide (instant `visible`
  toggle only, matching how `ArenaCamera._apply_mode()` snaps instantly rather than tweening).
- Do NOT change `PauseButton`'s behavior beyond the node type/positioning — `_on_pause_pressed()`
  stays exactly as-is.

## VERIFY

1. `grep -n "PauseButton\|PlayerCharacter" scenes/hud/HUD.tscn` — confirm both node lines read
   `type="TextureButton"` with the new anchor/offset/stretch properties.
2. `grep -n "pause_button\|player_character_button" scripts/hud/HUD.gd` — confirm both type
   annotations are now `TextureButton`, and the stale commented-out `pause_button` line is
   gone.
3. `grep -n "suppress_next_release" scripts/hud/HUD.gd` — confirm no match. A separate
   `grep -rn "suppress_next_release" scripts/` should still find the function's
   definition/other usages untouched.
4. Run the arena scene: confirm `PauseButton` renders at the same visual size/position as
   before (top-right corner, same margins, no stretching) and still opens the settings overlay
   and pauses the game on tap — no regressions from the type change.
5. Confirm `PlayerCharacter`/recenter button renders at the vertical middle of the left screen
   edge (default `Settings.lock_camera == false`), same visual size as before, no stretching.
6. Tap the recenter button: confirm the camera recenters on the hero AND the hero does **not**
   also receive a duplicate tap-to-move order at the button's screen position (regression check
   for removing `suppress_next_release()`).
7. Open Settings mid-match and toggle "Lock camera" on: confirm the recenter button disappears
   immediately (no scene reload) and the camera snaps to the hero. Toggle back off: confirm the
   button reappears at the same middle-left position.
8. Drag/resize the Godot debug window (F5) to a few different aspect ratios: confirm both
   buttons stay flush against their respective edges (`PauseButton` top-right,
   `PlayerCharacter` vertically centered on the left) rather than drifting — this is the actual
   regression test for the anchor-vs-hardcoded-position fix.
9. Confirm no other HUD element shifted position or size as a side effect (Minimap, EnergyBar,
   CardHand, MatchInfoBar all visually unchanged).
