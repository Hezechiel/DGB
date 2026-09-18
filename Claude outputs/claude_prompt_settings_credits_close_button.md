# Claude Code Prompt — Main menu: fix overlay z-order + convert Close buttons to TextureButton

**Enter Plan Mode first.** Present the full diff for review before touching any files.

## Context

Two related bugs found while investigating "settings overlay and credits do not show on main
menu, but the close button's touch area still works":

### Bug 1 (root cause of "doesn't show at all") — draw order

`scenes/menu/MainMenu.tscn`'s top-level children are, in this order: `SettingOverlay`,
`CreditsOverlay`, `Background`. `Background` is a full-screen opaque `Panel`
(`StyleBoxTexture` using `main_menu.webp`). Godot draws same-parent siblings in child order,
later siblings on top — so `Background`, being last, renders over both overlays regardless of
their own `visible` state. Neither `setting_overlay.gd` nor `credits_overlay.gd` nor
`main_menu.gd` currently does anything (`move_to_front()`, `z_index`, or otherwise) to bring
the overlay above `Background` when it opens — confirmed by reading all three scripts. This is
why the whole panel (background art, labels, slider, everything) is invisible when opened, yet
`CloseSettings`' tap zone still responds: `TouchScreenButton` hit-testing is a manual
point-in-shape check on the touch event, independent of Control draw order / `mouse_filter`
chains, so occlusion doesn't block it.

### Bug 2 (why the close buttons are invisible even once Bug 1 is fixed)

`SettingsPanel/CloseSettings` (`scenes/menu/setting_overlay.tscn`) and
`CreditsPanel/CloseCredits` (`scenes/menu/credits_overlay.tscn`) are both `TouchScreenButton`
nodes with **no `texture_normal` set at all** — only a bare `CircleShape2D` (default radius,
`scale = Vector2(4, 4)`) used purely for hit-testing. They were never going to render anything,
by construction, independent of Bug 1.

### Fix

- Bug 1: call `move_to_front()` on the overlay in `main_menu.gd` right before opening it —
  smallest possible fix, doesn't touch scene tree structure or child indices anything else
  might rely on.
- Bug 2: convert both close buttons from `TouchScreenButton` to `TextureButton`, using
  `res://assets/menu/UI_pause_btn.png` (as asked) plus its existing `_pressed` companion
  (`UI_pause_btn_pressed.png`) for press feedback — matching the exact technique already used
  for `PauseButton`/`PlayerCharacter` on `arena.tscn`'s HUD (`ignore_texture_size = true`,
  `stretch_mode = 5` i.e. `STRETCH_KEEP_ASPECT_CENTERED`, anchored instead of hardcoded
  position).

Note on placement: the old `CloseSettings`/`CloseCredits` position (`Vector2(1090, 268)`,
roughly mid-right of the 1170×540 canvas) was likely never visually validated, since the whole
panel has been invisible behind `Background` — there's no way to know if it was meant to land
on some feature of the `UI_note_large_landscape.png` art. This prompt places the new button in
the **top-right corner** of each panel instead (same corner convention as `PauseButton`,
matching "in the way of pause button" literally) with a modest margin, since that's the most
defensible default and sits inside each panel's existing right-side margin band. Treat the
exact offsets as a starting point to hand-tune visually once you can actually see the panel —
same as you've tuned other things (card font size) yourself before.

This prompt has two parts. **Part 1** is what you asked for (`CloseSettings` + the z-order
fix it depends on to matter). **Part 2** is the twin fix for `CloseCredits` — not explicitly
requested, included because it's the identical bug, but easy to skip in Plan Mode review if you
want it as a separate change later.

## Files to inspect first (Plan Mode — read before editing)

- `scenes/menu/MainMenu.tscn`
- `scenes/menu/setting_overlay.tscn`
- `scenes/menu/credits_overlay.tscn`
- `scripts/ui/main_menu.gd`
- `scripts/ui/setting_overlay.gd`
- `scripts/ui/credits_overlay.gd`

Confirm current content matches what's described below before applying — if the live files
differ, stop and flag the mismatch instead of guessing.

## Part 1 — z-order fix + CloseSettings conversion

### 1a. `scripts/ui/main_menu.gd`

In `_on_settings_button_pressed()`, add `setting_overlay.move_to_front()` before `.open(...)`:

```gdscript
func _on_settings_button_pressed() -> void:
	# overlay version
	#get_tree().paused = true
	main_buttons.visible = false
	exit_button.visible = false
	# Background je posledne dieta MainMenu (kreslene navrchu) — bez tohto
	# by overlay ostal skryty za nim aj pri visible = true.
	setting_overlay.move_to_front()
	setting_overlay.open(false)
```

Leave every other function in this file untouched for now (Part 2 adds one more line to
`_on_credits_button_pressed()`).

### 1b. `scenes/menu/setting_overlay.tscn`

Replace the `CloseSettings` node block:

```
[node name="CloseSettings" type="TouchScreenButton" parent="SettingsPanel" unique_id=159458134]
process_mode = 3
position = Vector2(1090, 268)
scale = Vector2(4, 4)
shape = SubResource("CircleShape2D_3g7hk")
```

with:

```
[node name="CloseSettings" type="TextureButton" parent="SettingsPanel" unique_id=159458134]
process_mode = 3
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -115.0
offset_top = 15.0
offset_right = -20.0
offset_bottom = 97.5
texture_normal = ExtResource("20_pausebtn")
texture_pressed = ExtResource("21_pausebtnp")
ignore_texture_size = true
stretch_mode = 5
```

Add the two new `ext_resource` lines near the top of the file, alongside the existing ones
(after the last existing `ext_resource` line, before the `[sub_resource ...]` lines):

```
[ext_resource type="Texture2D" uid="uid://dv8mpu640lf7v" path="res://assets/menu/UI_pause_btn.png" id="20_pausebtn"]
[ext_resource type="Texture2D" uid="uid://c865n2j5w8div" path="res://assets/menu/UI_pause_btn_pressed.png" id="21_pausebtnp"]
```

Remove the now-unused `CircleShape2D_3g7hk` sub_resource (grep first to confirm nothing else in
this file references it — it shouldn't, `CloseSettings` was its only user):

```
[sub_resource type="CircleShape2D" id="CircleShape2D_3g7hk"]
```

Notes on the numbers: `UI_pause_btn.png` is 190×165px (already verified for the arena
`PauseButton` conversion). 95×82.5 preserves that aspect ratio exactly (1.1515), so
`stretch_mode = 5` fills the box with no letterbox gap — identical technique/size to arena's
`PauseButton`. `anchors_preset = 1` is `PRESET_TOP_RIGHT`.

### 1c. `scripts/ui/setting_overlay.gd`

Change the onready var type:

```gdscript
@onready var close_settings: TouchScreenButton = $SettingsPanel/CloseSettings
```
→
```gdscript
@onready var close_settings: TextureButton = $SettingsPanel/CloseSettings
```

Leave everything else in this file untouched — `exit_button` (`$ExitButton`, the separate
"Main Menu" button with its own existing texture) is a different node, not part of this bug,
do not touch it or its type.

## Part 2 — CloseCredits conversion (twin of Part 1b/1c, same bug)

### 2a. `scripts/ui/main_menu.gd`

In `_on_credits_button_pressed()`, add `credits_overlay.move_to_front()` before `.open()`:

```gdscript
func _on_credits_button_pressed() -> void:
	# overlay version
	main_buttons.visible = false
	exit_button.visible = false
	credits_overlay.move_to_front()
	credits_overlay.open()
```

### 2b. `scenes/menu/credits_overlay.tscn`

Replace the `CloseCredits` node block:

```
[node name="CloseCredits" type="TouchScreenButton" parent="CreditsPanel" unique_id=2122519792]
position = Vector2(1090, 267)
scale = Vector2(4, 4)
shape = SubResource("CircleShape2D_74oyc")
```

with:

```
[node name="CloseCredits" type="TextureButton" parent="CreditsPanel" unique_id=2122519792]
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -115.0
offset_top = 15.0
offset_right = -20.0
offset_bottom = 97.5
texture_normal = ExtResource("20_pausebtn")
texture_pressed = ExtResource("21_pausebtnp")
ignore_texture_size = true
stretch_mode = 5
```

Add the same two `ext_resource` lines (fresh ids scoped to this file — it has its own
ext_resource namespace, separate from `setting_overlay.tscn`):

```
[ext_resource type="Texture2D" uid="uid://dv8mpu640lf7v" path="res://assets/menu/UI_pause_btn.png" id="20_pausebtn"]
[ext_resource type="Texture2D" uid="uid://c865n2j5w8div" path="res://assets/menu/UI_pause_btn_pressed.png" id="21_pausebtnp"]
```

Remove the now-unused `CircleShape2D_74oyc` sub_resource (grep first to confirm no other
reference in this file):

```
[sub_resource type="CircleShape2D" id="CircleShape2D_74oyc"]
```

Note: `CreditsPanel` has `clip_contents = true`. The new button's box (offsets above) sits well
within `CreditsPanel`'s full-rect bounds, so it will not get clipped — just flagging why this
detail matters here specifically, unlike `SettingsPanel` which has no `clip_contents`.

### 2c. `scripts/ui/credits_overlay.gd`

Change the onready var type:

```gdscript
@onready var close_credits: TouchScreenButton = $CreditsPanel/CloseCredits
```
→
```gdscript
@onready var close_credits: TextureButton = $CreditsPanel/CloseCredits
```

## DO NOT TOUCH

- `scenes/menu/MainMenu.tscn`'s node tree structure/order — do NOT reorder `Background`,
  `SettingOverlay`, `CreditsOverlay` in the scene file itself. The fix is `move_to_front()` at
  runtime, not a scene-file reorder.
- `SettingsOverlay.exit_button` / `$ExitButton` in `setting_overlay.tscn` — already has a
  texture (`UI_note.png`), unrelated to this bug, do not touch its type or texture.
- `main_buttons`, `start_arena_buton`, `settings_button`, `credits_button`, `exit_button` in
  `main_menu.gd`/`MainMenu.tscn` — untouched.
- `AudioControl`, `LockCameraToggle`, and all label/content nodes in both overlay scenes —
  untouched.
- `scenes/hud/HUD.tscn`, `scripts/hud/HUD.gd`, and anything under `scenes/arena/` — this prompt
  is main-menu-only; the arena `PauseButton`/`PlayerCharacter` conversions already done are the
  reference pattern, not something to re-touch.
- `scripts/settings.gd`, `Settings` autoload — no changes needed.

## Out of scope

- Do NOT add any transition/animation to the overlay open/close — instant `visible` toggle
  stays as-is, only the draw-order and button-texture bugs are being fixed.
- Do NOT redesign the settings/credits panel layout, art, or content.
- Do NOT try to make the close-button position "smart"/responsive beyond the anchor — a fixed
  anchored box in the top-right corner, same as the rest of this prompt's precedent.
- If you decide you don't want Part 2 (`CloseCredits`) applied right now, it can be skipped
  independently in Plan Mode review — Part 1 stands alone.

## VERIFY

1. `grep -n "move_to_front" scripts/ui/main_menu.gd` — confirm both calls are present (one in
   each handler, if both parts applied).
2. `grep -n "CloseSettings" scenes/menu/setting_overlay.tscn` — confirm `type="TextureButton"`
   with the new anchor/texture/stretch properties, and that `CircleShape2D_3g7hk` no longer
   appears anywhere in the file.
3. If Part 2 applied: `grep -n "CloseCredits" scenes/menu/credits_overlay.tscn` — same checks,
   confirm `CircleShape2D_74oyc` is gone too.
4. `grep -n "close_settings\|close_credits" scripts/ui/setting_overlay.gd scripts/ui/credits_overlay.gd`
   — confirm both onready vars are now typed `TextureButton`.
5. Run the main menu: tap "Settings" — confirm the full settings panel (background art, title,
   audio slider, lock-camera toggle) is now actually visible (this is the real regression test
   for Bug 1; before this fix, nothing rendered here at all).
6. Confirm the new close-button icon renders in the top-right corner of the settings panel, at
   the expected 95×82.5 size with no stretching, and tapping it closes the overlay and restores
   the main menu buttons (`_on_setting_overlay_close_requested` still fires correctly).
7. If Part 2 applied: repeat steps 5–6 for "Credits" — confirm the full credits list is visible
   and the close button works the same way.
8. Confirm `main_buttons`/`exit_button` visibility toggling (hidden while an overlay is open,
   restored on close) still works correctly for both Settings and Credits, unchanged by this
   diff.
9. Confirm the `ExitButton` (ending back to Main Menu button, mid-match, different from the two
   close buttons above) is visually and functionally unchanged.
