# Claude Code Prompt — Main menu redesign, Step 3: left nav rail + Credits relocation

**Enter Plan Mode first.** Present the full diff for review before touching any files.

## Context

Third of 4 planned steps (Steps 1–2 — footer, top status bar — already landed and verified).
This step replaces the old `MainButtons` cluster (`Background/HBoxContainer`'s subtree — the
"Arena / Settings / Credits / Exit" button group, already missing Settings since Step 2 moved
it to the top bar) with a proper left-side vertical nav rail, matching the reference screenshot.

**One thing to flag before the diff: I contradicted myself across the last two messages on
where Credits ends up**, and I want to resolve it correctly rather than copy either sloppy
version. When we first discussed this I said Credits should nest *inside* the Settings overlay
as a button in its content (matching the convention that a hub's front page doesn't show a
standalone Credits entry — it lives under Settings/About in most mobile games), with only Exit
getting a nav-rail slot. But my own later phase-plan shorthand said "Credits/Exit (relocated
here)" as if both moved to the rail — that second version was just an imprecise recap, not a
reconsidered decision. This prompt implements the **first, more carefully-reasoned version**:
Credits moves into the Settings overlay's content list, not the nav rail. Flag now if you
actually wanted Credits in the rail instead — easy to redo either way, but better to catch it
before this lands.

Nav rail contents, top to bottom: **Arena** (real, relocated from the old cluster) →
**Deck** / **Heroes** / **Shop** / **Rewards** (placeholders, "Coming soon" toast on tap) →
[stretch] → **Exit** (real, relocated). A few notes on that list:

- `Deck` and `Heroes` are grounded in `game_design.md`'s own stated (if undesigned) roadmap —
  "Meta: deck building, collection, per-match deck selection" and the god-roster/era structure.
  `Shop` was one of your named examples. `Rewards` mirrors the reference screenshot's own rail
  and is generic enough to not overcommit to anything specific.
- **`Trade` is deliberately left out.** Force Arena's rail has it, but nothing in
  `game_design.md` mentions a trading feature at all — I didn't want to invent a feature with
  zero grounding just to match the reference image. Say the word if you actually want a `Trade`
  placeholder added.
- Same real-vs-placeholder visual split established in Step 2: `Arena`/`Exit` keep the
  `UI_note.png` parchment-button look (now scaled down to fit the narrower rail, same
  `ignore_texture_size`/`stretch_mode = 5` technique used throughout this redesign);
  `Deck`/`Heroes`/`Shop`/`Rewards` are flat-color `Button` placeholders reusing Step 2's toast
  mechanism, each a distinct muted color.

Also: the old `main_buttons`/`exit_button` were toggled as **two separate** visibility flags
when Settings/Credits opened — a leftover from when they lived in different containers. Now
that everything (Arena, 4 placeholders, Exit) lives in one `NavRail`, this step simplifies that
to a single `nav_rail.visible` toggle. `TopBar`/`FooterBar` are untouched by this open/close
logic, same as in Step 2 — the overlays are opaque full-screen panels, so anything underneath
is already fully hidden visually regardless of its own `visible` flag.

## Files to inspect first (Plan Mode — read before editing)

- `scenes/menu/MainMenu.tscn`
- `scripts/ui/main_menu.gd`
- `scenes/menu/setting_overlay.tscn`
- `scripts/ui/setting_overlay.gd`

Confirm current content matches what's described below (in particular: `TopBar`/`FooterBar`
should already exist from Steps 1–2, and `MainButtons` should still have `Arena`/`Credits`/`Exit`
but no `Settings`) — if the live files differ, stop and flag the mismatch instead of guessing.

---

## Part A — Nav rail (replaces `MainButtons`)

### A1. `scenes/menu/MainMenu.tscn`

Remove the entire `Background/HBoxContainer` node and everything under it — `MarginContainer`,
`MainButtons`, `VBoxContainer` (containing `StartArenaButon`+`Label`), `VBoxContainer2`
(containing `CreditsButton`+`CreditsLabel` and `ExitButton`+`ExitLabel`). That's every node
from the `[node name="HBoxContainer" ...]` block through the end of the `ExitLabel` block.

Add the four new `StyleBoxFlat` sub_resources for the placeholder buttons, alongside the
existing `StyleBoxFlat_toast`/`StyleBoxFlat_mail`/`StyleBoxFlat_gift` from Step 2:

```
[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_deck"]
bg_color = Color(0.45, 0.35, 0.55, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_heroes"]
bg_color = Color(0.3, 0.5, 0.35, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_shop"]
bg_color = Color(0.6, 0.45, 0.15, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_rewards"]
bg_color = Color(0.55, 0.25, 0.25, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4
```

Add the new `NavRail` subtree as a child of `Background` (placement: where `HBoxContainer` used
to be is fine — before `TopBar`/`ComingSoonToast`/`FooterBar`):

```
[node name="NavRail" type="VBoxContainer" parent="Background"]
layout_mode = 1
anchors_preset = 9
anchor_bottom = 1.0
offset_left = 8.0
offset_top = 50.0
offset_right = 118.0
offset_bottom = -26.0
grow_vertical = 2
mouse_filter = 2
theme_override_constants/separation = 8

[node name="StartArenaButon" type="TextureButton" parent="Background/NavRail"]
custom_minimum_size = Vector2(100, 42.25)
layout_mode = 2
texture_normal = ExtResource("4_84lro")
ignore_texture_size = true
stretch_mode = 5

[node name="Label" type="Label" parent="Background/NavRail/StartArenaButon"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -20.0
offset_top = -10.0
offset_right = 20.0
offset_bottom = 10.0
grow_horizontal = 2
grow_vertical = 2
theme_override_colors/font_color = Color(0, 0.25882354, 0.42745098, 1)
theme_override_fonts/font = ExtResource("5_y6vun")
theme_override_font_sizes/font_size = 16
text = "Arena"

[node name="DeckButton" type="Button" parent="Background/NavRail"]
custom_minimum_size = Vector2(100, 36)
layout_mode = 2
theme_override_font_sizes/font_size = 14
theme_override_styles/normal = SubResource("StyleBoxFlat_deck")
text = "Deck"

[node name="HeroesButton" type="Button" parent="Background/NavRail"]
custom_minimum_size = Vector2(100, 36)
layout_mode = 2
theme_override_font_sizes/font_size = 14
theme_override_styles/normal = SubResource("StyleBoxFlat_heroes")
text = "Heroes"

[node name="ShopButton" type="Button" parent="Background/NavRail"]
custom_minimum_size = Vector2(100, 36)
layout_mode = 2
theme_override_font_sizes/font_size = 14
theme_override_styles/normal = SubResource("StyleBoxFlat_shop")
text = "Shop"

[node name="RewardsButton" type="Button" parent="Background/NavRail"]
custom_minimum_size = Vector2(100, 36)
layout_mode = 2
theme_override_font_sizes/font_size = 14
theme_override_styles/normal = SubResource("StyleBoxFlat_rewards")
text = "Rewards"

[node name="NavRailSpacer" type="Control" parent="Background/NavRail"]
layout_mode = 2
size_flags_vertical = 3
mouse_filter = 2

[node name="ExitButton" type="TextureButton" parent="Background/NavRail"]
custom_minimum_size = Vector2(100, 42.25)
layout_mode = 2
texture_normal = ExtResource("4_84lro")
ignore_texture_size = true
stretch_mode = 5

[node name="ExitLabel" type="Label" parent="Background/NavRail/ExitButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -18.0
offset_top = -10.0
offset_right = 18.0
offset_bottom = 10.0
grow_horizontal = 2
grow_vertical = 2
theme_override_colors/font_color = Color(0, 0.25882354, 0.42745098, 1)
theme_override_fonts/font = ExtResource("5_y6vun")
theme_override_font_sizes/font_size = 16
text = "Exit"
```

Notes: `UI_note.png` is 142×60px; `100×42.25` preserves that aspect exactly, same technique
used throughout this redesign. Label offsets/font sizes on `Arena`/`Exit` are rough starting
points for the narrower rail slot, not precisely tuned — expect to hand-adjust once you see it
rendered, same as other font sizing in this project. `NavRailSpacer` (`size_flags_vertical = 3`,
expand+fill) is what pushes `Exit` to the bottom of the rail, separated from the content buttons
above it.

Update the connections block at the bottom of the file — remove the old `CreditsOverlay`
connection line's neighbor (nothing changes there) but add the new one from Part B:

```
[connection signal="closed_requested" from="SettingOverlay" to="." method="_on_setting_overlay_close_requested"]
[connection signal="credits_requested" from="SettingOverlay" to="." method="_on_credits_button_pressed"]
[connection signal="closed" from="CreditsOverlay" to="." method="_on_credits_overlay_closed"]
```

(The middle line is new — `credits_requested` doesn't exist on `SettingsOverlay` yet; it's added
in Part B below. Add this connection line in the same pass since Plan Mode will show the whole
diff together, but it only makes sense once Part B's script/scene changes are also applied.)

### A2. `scripts/ui/main_menu.gd`

Replace the onready var block:

```gdscript
@onready var nav_rail: VBoxContainer = $Background/NavRail
@onready var start_arena_buton: TextureButton = $Background/NavRail/StartArenaButon
@onready var settings_button: TextureButton = $Background/TopBar/SettingsButton
@onready var exit_button: TextureButton = $Background/NavRail/ExitButton
@onready var deck_button: Button = $Background/NavRail/DeckButton
@onready var heroes_button: Button = $Background/NavRail/HeroesButton
@onready var shop_button: Button = $Background/NavRail/ShopButton
@onready var rewards_button: Button = $Background/NavRail/RewardsButton
@onready var version_label: Label = $Background/FooterBar/VersionLabel
@onready var mail_button: Button = $Background/TopBar/MailButton
@onready var gift_button: Button = $Background/TopBar/GiftButton
@onready var coming_soon_toast: PanelContainer = $Background/ComingSoonToast
@onready var coming_soon_label: Label = $Background/ComingSoonToast/ComingSoonLabel

@onready var setting_overlay: SettingsOverlay = $SettingOverlay
@onready var credits_overlay: CreditsOverlay = $CreditsOverlay
```

(`main_buttons` and `credits_button` — the old ones pointing into the now-deleted
`MainButtons` cluster — are gone; `credits_button` no longer exists as a main-menu node at all,
see Part B.)

Replace `_ready()`:

```gdscript
func _ready() -> void:
	# Mobile: hide Exit (Android usually doestn need it)
	#if OS.has_feature("android") or OS.has_feature("ios"):
		#$ExitButton.visible = false
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0-dev")
	nav_rail.visible = true
	start_arena_buton.pressed.connect(_on_start_arena_buton_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	mail_button.pressed.connect(_show_coming_soon.bind("Mail"))
	gift_button.pressed.connect(_show_coming_soon.bind("Gift"))
	deck_button.pressed.connect(_show_coming_soon.bind("Deck"))
	heroes_button.pressed.connect(_show_coming_soon.bind("Heroes"))
	shop_button.pressed.connect(_show_coming_soon.bind("Shop"))
	rewards_button.pressed.connect(_show_coming_soon.bind("Rewards"))
	#setting_overlay.visible = false
```

Replace the open/close handlers (simplified to one `nav_rail` toggle instead of the old
`main_buttons`+`exit_button` pair; `_on_credits_button_pressed` no longer takes a button press
directly — it's now called by the `credits_requested` signal connection from Part A1):

```gdscript
func _on_start_arena_buton_pressed() -> void:
	get_tree().change_scene_to_file(PREMATCH_FLOW_SCENE)

func _on_settings_button_pressed() -> void:
	nav_rail.visible = false
	# Background je posledne dieta MainMenu (kreslene navrchu) — bez tohto
	# by overlay ostal skryty za nim aj pri visible = true.
	setting_overlay.move_to_front()
	setting_overlay.open(false)

func _on_credits_button_pressed() -> void:
	nav_rail.visible = false
	credits_overlay.move_to_front()
	credits_overlay.open()

func _on_setting_overlay_close_requested() -> void:
	setting_overlay.close()
	nav_rail.visible = true

func _on_credits_overlay_closed() -> void:
	nav_rail.visible = true

func _on_exit_button_pressed() -> void:
	get_tree().quit()
```

`_show_coming_soon()` stays exactly as it is from Step 2 — no changes needed there.

---

## Part B — Credits relocated into the Settings overlay

### B1. `scenes/menu/setting_overlay.tscn`

Add a `CreditsButton` at the end of the settings content list, after `LockCameraRow`:

```
[node name="CreditsButton" type="Button" parent="SettingsPanel/MarginContainer/ScrollContainer/SettingsContent"]
layout_mode = 2
theme_override_font_sizes/font_size = 18
text = "Credits"
```

Plain default-styled `Button`, matching the plainness of the rest of this settings list (Labels/
slider/checkbox, no `UI_note.png` parchment styling here) rather than importing the main menu's
button art into a different visual context.

### B2. `scripts/ui/setting_overlay.gd`

Add the new signal and onready var:

```gdscript
extends Control
class_name SettingsOverlay

signal closed_requested
signal exit_requested
signal credits_requested

@onready var close_settings: TextureButton = $SettingsPanel/CloseSettings
@onready var exit_button: TouchScreenButton = $ExitButton
@onready var lock_camera_toggle: CheckButton = $SettingsPanel/MarginContainer/ScrollContainer/SettingsContent/LockCameraRow/LockCameraToggle
@onready var credits_button: Button = $SettingsPanel/MarginContainer/ScrollContainer/SettingsContent/CreditsButton
```

Connect it in `_ready()`:

```gdscript
func _ready() -> void:
	exit_button.pressed.connect(_on_exit_button_pressed)
	lock_camera_toggle.toggled.connect(_on_lock_camera_toggled)
	credits_button.pressed.connect(_on_credits_button_pressed)
	visible = false
```

Add the handler (placement: anywhere after `_on_close_settings_pressed`):

```gdscript
func _on_credits_button_pressed() -> void:
	# Settings sa zatvori PRED vyziadanim Credits — oba su fullscreen overlay,
	# nechceme mat naraz otvorene oba naraz.
	close()
	credits_requested.emit()
```

Leave `open()`, `close()`, `_on_close_settings_pressed()`, `_on_exit_button_pressed()`,
`_on_lock_camera_toggled()` untouched.

---

## DO NOT TOUCH

- `TopBar` and its children (`CurrencyGroup`, `MailButton`, `GiftButton`, `SettingsButton`) —
  Step 2, untouched by this step.
- `FooterBar` and its children — Step 1, untouched.
- `ComingSoonToast`/`ComingSoonLabel` and `_show_coming_soon()` — reused as-is, no changes to
  their own definitions.
- `CreditsOverlay` scene/script — untouched; it's still opened the same way
  (`move_to_front()` + `open()`), just from a different trigger now (Settings' new button
  instead of a main-menu button).
- `SettingsPanel`, `CloseSettings`, `AudioLabel`/`AudioControl`, `LockCameraRow` in
  `setting_overlay.tscn`/`.gd` — untouched, only a new `CreditsButton` is added alongside them.
- `project.godot` — no changes this step.

## Out of scope

- Do NOT add icon art to the placeholder rail buttons — flat color + text only, same as
  Mail/Gift from Step 2.
- Do NOT add a `Trade` placeholder — flagged above as deliberately omitted; say so if you want
  it added.
- Do NOT wire any of `Deck`/`Heroes`/`Shop`/`Rewards` to real functionality — "Coming soon"
  toast only.
- This is the last step touching `MainButtons`/nav structure — Step 4 (center hero showcase +
  right mode card) is additive and shouldn't need to revisit anything built in this step.

## VERIFY

1. `grep -n "HBoxContainer\|NavRail" scenes/menu/MainMenu.tscn` — confirm the old
   `Background/HBoxContainer` subtree is completely gone and `NavRail` with its 7 children
   (`StartArenaButon`, `DeckButton`, `HeroesButton`, `ShopButton`, `RewardsButton`,
   `NavRailSpacer`, `ExitButton`) is present.
2. `grep -n "CreditsButton\|credits_requested" scenes/menu/MainMenu.tscn scenes/menu/setting_overlay.tscn scripts/ui/setting_overlay.gd scripts/ui/main_menu.gd`
   — confirm: no more `CreditsButton` in `MainMenu.tscn`; a new one exists in
   `setting_overlay.tscn`; `credits_requested` signal declared in `setting_overlay.gd` and
   connected both to `_on_credits_button_pressed` in `.gd` (emit side) and via the `.tscn`
   connection (receive side).
3. `grep -n "main_buttons\|credits_button" scripts/ui/main_menu.gd` — confirm no leftover
   references to the deleted `main_buttons` var or a main-menu-level `credits_button` var.
4. Run the main menu: confirm a vertical rail renders on the left edge, below the top bar and
   above the footer, with `Arena` at top (parchment style), four colored placeholder buttons
   below it, and `Exit` pinned to the bottom of the rail (parchment style) with visible空 space
   above it from the spacer.
5. Tap `Deck`/`Heroes`/`Shop`/`Rewards`: confirm each shows the "Coming soon" toast with the
   correct feature name (reusing Step 2's mechanism).
6. Tap `Arena`: confirm it still starts the prematch flow exactly as before.
7. Tap `Exit`: confirm it still quits the game exactly as before.
8. Tap `Settings` (top bar): confirm the overlay opens and the nav rail hides. Scroll down in
   the settings content and confirm a `Credits` button now appears after `Lock Camera`. Tap it:
   confirm Settings closes, Credits opens on top, and the nav rail stays hidden throughout (no
   flash of the rail between the two overlays).
9. Close Credits (its own close button): confirm the nav rail reappears and both overlays are
   fully closed — reopen Settings directly afterward to confirm it still opens cleanly (no stale
   state from the Credits-via-Settings path).
10. Confirm `TopBar`/`FooterBar` are visually unaffected throughout all of the above.
