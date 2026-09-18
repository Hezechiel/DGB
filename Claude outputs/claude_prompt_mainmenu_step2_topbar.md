# Claude Code Prompt — Main menu redesign, Step 2: top status bar

**Enter Plan Mode first.** Present the full diff for review before touching any files.

## Context

Second of 4 planned steps (Step 1 — footer — already landed and verified). This step adds a
Force-Arena-style top status bar to `MainMenu.tscn`: a currency counter placeholder, mail/gift
icon placeholders, and the **Settings** button relocated here from the main button cluster (it
becomes a small top-bar icon, matching the convention in the reference screenshot, since it's
the one feature here that's fully real today).

A few scoping calls worth being upfront about:

- **Only one currency counter, not a soft/premium split.** Force Arena shows multiple resource
  counters (gold, gems, energy). DGB has no economy at all yet (`game_design.md` lists
  monetization as explicitly undecided), and whether it ends up with one currency or a
  soft+premium split is a real design decision that hasn't been made. This step adds a single
  generic counter (icon + static `"0"`) as a placeholder — the pattern is trivially
  copy-pasteable for a second currency once that's actually decided.
- **No player identity/avatar/level in the bar.** Force Arena's top-left shows player level,
  name, and a faction icon. DGB has no player profile/account system at all — not even a stub —
  so I left this out rather than inventing placeholder UI for a system that doesn't exist even
  conceptually yet. Flag if you want a placeholder slot for this anyway.
- **This step introduces the "Coming soon" toast mechanism** (decided when we scoped the
  redesign) since Mail/Gift are the first tappable placeholder buttons. It's a small reusable
  bit of `main_menu.gd`: a hidden `PanelContainer` + `Label` that becomes visible with a
  feature name and auto-hides after 1.5s. Later steps' placeholder buttons (nav rail entries in
  Step 3) will reuse this same function.
- **Real vs. placeholder buttons are visually distinct on purpose.** The relocated `Settings`
  button keeps reusing the existing `UI_note.png` parchment-button art (same as `Arena`,
  `Credits`, `Exit` elsewhere in this scene) — that's the "this actually works" visual language
  in this project right now. `Mail`/`Gift` are plain flat-color `Button` nodes with no texture
  asset at all, using a `StyleBoxFlat` override rather than `TextureButton` (there's no icon art
  cut yet, and `Button`'s built-in styling is the correct tool for a color-only placeholder —
  unlike `TextureButton`, it doesn't need any texture to render something visible, which is what
  caused the invisible-button bug fixed earlier on the Settings/Credits close buttons). This
  split isn't just visual polish — it doubles as an honest todo-list of what still needs real
  art and wiring.

This step also nudges `Background/HBoxContainer` (the container holding the `MainButtons`
cluster) down by adding `offset_top = 44.0`, so it starts below the new top bar instead of
overlapping it. `MainButtons` itself is not restructured here — `SettingsButton`/`SettingsLabel`
are removed from it (relocated to the top bar), but `CreditsButton`/`ExitButton` stay exactly
where they are until Step 3 replaces that whole cluster with the nav rail. Expect
`VBoxContainer2` to look a little lopsided in the interim (2 buttons instead of 3) — same
category of temporary state as Step 1's title gap.

## Files to inspect first (Plan Mode — read before editing)

- `scenes/menu/MainMenu.tscn`
- `scripts/ui/main_menu.gd`

Confirm current content matches what's described below (in particular: `Title` should already
be gone and `FooterBar` should already exist, from Step 1) — if the live files differ, stop and
flag the mismatch instead of guessing.

## Changes

### 1. `scenes/menu/MainMenu.tscn`

**1a.** Add `offset_top = 44.0` to the existing `Background/HBoxContainer` node (currently has
`anchors_preset = 10`, `anchor_right = 1.0`, `offset_bottom = 252.0`, `grow_horizontal = 2`, no
`offset_top`):

```
[node name="HBoxContainer" type="VBoxContainer" parent="Background" unique_id=564597481]
layout_mode = 1
anchors_preset = 10
anchor_right = 1.0
offset_top = 44.0
offset_bottom = 252.0
grow_horizontal = 2
```

**1b.** Remove the `SettingsButton` and `SettingsLabel` node blocks from
`Background/HBoxContainer/MarginContainer/MainButtons/VBoxContainer2` (they're being relocated,
not deleted — recreated below in the new `TopBar`):

```
[node name="SettingsButton" type="TextureButton" parent="Background/HBoxContainer/MarginContainer/MainButtons/VBoxContainer2" unique_id=272909697]
layout_mode = 2
texture_normal = ExtResource("4_84lro")

[node name="SettingsLabel" type="Label" parent="Background/HBoxContainer/MarginContainer/MainButtons/VBoxContainer2/SettingsButton" unique_id=878977067]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -50.0
offset_top = -12.5
offset_right = 50.0
offset_bottom = 12.5
grow_horizontal = 2
grow_vertical = 2
theme_override_colors/font_color = Color(0, 0.25882354, 0.42745098, 1)
theme_override_fonts/font = ExtResource("5_y6vun")
theme_override_font_sizes/font_size = 18
text = "Settings"
```

Leave `CreditsButton`/`CreditsLabel` and `ExitButton`/`ExitLabel` in
`VBoxContainer2` untouched.

**1c.** Add a `StyleBoxFlat` sub_resource for the toast background, alongside the existing
`StyleBoxTexture_mgsx5` sub_resource near the top of the file:

```
[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_toast"]
bg_color = Color(0, 0, 0, 0.75)
corner_radius_top_left = 6
corner_radius_top_right = 6
corner_radius_bottom_right = 6
corner_radius_bottom_left = 6
```

**1d.** Add the new `TopBar` subtree as a child of `Background` (placement: anywhere after
`Background`'s own declaration — putting it right after `Background/HBoxContainer`'s subtree
and before `FooterBar` keeps related content grouped):

```
[node name="TopBar" type="HBoxContainer" parent="Background"]
layout_mode = 1
anchors_preset = 10
anchor_right = 1.0
offset_left = 10.0
offset_top = 6.0
offset_right = -10.0
offset_bottom = 42.0
grow_horizontal = 2
mouse_filter = 2
theme_override_constants/separation = 10

[node name="CurrencyGroup" type="HBoxContainer" parent="Background/TopBar"]
layout_mode = 2
mouse_filter = 2
theme_override_constants/separation = 6

[node name="CurrencyIcon" type="ColorRect" parent="Background/TopBar/CurrencyGroup"]
custom_minimum_size = Vector2(18, 18)
layout_mode = 2
size_flags_vertical = 4
color = Color(0.85, 0.65, 0.15, 1)

[node name="CurrencyAmountLabel" type="Label" parent="Background/TopBar/CurrencyGroup"]
layout_mode = 2
size_flags_vertical = 4
theme_override_colors/font_color = Color(0.95, 0.95, 0.9, 1)
theme_override_font_sizes/font_size = 14
text = "0"

[node name="TopBarSpacer" type="Control" parent="Background/TopBar"]
layout_mode = 2
size_flags_horizontal = 3
mouse_filter = 2

[node name="MailButton" type="Button" parent="Background/TopBar"]
custom_minimum_size = Vector2(64, 32)
layout_mode = 2
theme_override_font_sizes/font_size = 14
theme_override_styles/normal = SubResource("StyleBoxFlat_mail")
text = "Mail"

[node name="GiftButton" type="Button" parent="Background/TopBar"]
custom_minimum_size = Vector2(64, 32)
layout_mode = 2
theme_override_font_sizes/font_size = 14
theme_override_styles/normal = SubResource("StyleBoxFlat_gift")
text = "Gift"

[node name="SettingsButton" type="TextureButton" parent="Background/TopBar"]
custom_minimum_size = Vector2(70, 29.6)
layout_mode = 2
texture_normal = ExtResource("4_84lro")
ignore_texture_size = true
stretch_mode = 5

[node name="SettingsLabel" type="Label" parent="Background/TopBar/SettingsButton"]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -20.0
offset_top = -8.0
offset_right = 20.0
offset_bottom = 8.0
grow_horizontal = 2
grow_vertical = 2
theme_override_colors/font_color = Color(0, 0.25882354, 0.42745098, 1)
theme_override_fonts/font = ExtResource("5_y6vun")
theme_override_font_sizes/font_size = 12
text = "Settings"
```

Add the two more `StyleBoxFlat` sub_resources `MailButton`/`GiftButton` reference (put them next
to `StyleBoxFlat_toast` from 1c):

```
[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_mail"]
bg_color = Color(0.3, 0.45, 0.6, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_gift"]
bg_color = Color(0.55, 0.25, 0.5, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4
```

Notes: `UI_note.png` is 142×60px; `70×29.6` preserves that aspect exactly, same
`ignore_texture_size`/`stretch_mode = 5` technique used for the arena HUD buttons and the
Settings/Credits close buttons. `SettingsLabel`'s font size is shrunk to 12 to fit the smaller
box — likely needs your own hand-tuning once you see it rendered, same as other font sizing in
this project. `Mail`/`Gift` only override the `normal` style state (hover/pressed fall back to
engine defaults) — acceptable for a placeholder that's getting real art later, not worth fully
theming every button state now.

**1e.** Add the `ComingSoonToast` node as a child of `Background`, after `TopBar`:

```
[node name="ComingSoonToast" type="PanelContainer" parent="Background"]
visible = false
layout_mode = 1
anchors_preset = 5
anchor_left = 0.5
anchor_right = 0.5
offset_left = -110.0
offset_top = 50.0
offset_right = 110.0
offset_bottom = 80.0
mouse_filter = 2
theme_override_styles/panel = SubResource("StyleBoxFlat_toast")

[node name="ComingSoonLabel" type="Label" parent="Background/ComingSoonToast"]
layout_mode = 2
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_font_sizes/font_size = 14
text = "Coming soon"
horizontal_alignment = 1
vertical_alignment = 1
```

### 2. `scripts/ui/main_menu.gd`

Update the `settings_button` onready path (it moved from `MainButtons/VBoxContainer2` to
`TopBar`), and add the new onready vars:

```gdscript
@onready var main_buttons: HBoxContainer = $Background/HBoxContainer/MarginContainer/MainButtons
@onready var start_arena_buton: TextureButton = $Background/HBoxContainer/MarginContainer/MainButtons/VBoxContainer/StartArenaButon
@onready var settings_button: TextureButton = $Background/TopBar/SettingsButton
@onready var credits_button: TextureButton = $Background/HBoxContainer/MarginContainer/MainButtons/VBoxContainer2/CreditsButton
@onready var exit_button: TextureButton = $Background/HBoxContainer/MarginContainer/MainButtons/VBoxContainer2/ExitButton
@onready var version_label: Label = $Background/FooterBar/VersionLabel
@onready var mail_button: Button = $Background/TopBar/MailButton
@onready var gift_button: Button = $Background/TopBar/GiftButton
@onready var coming_soon_toast: PanelContainer = $Background/ComingSoonToast
@onready var coming_soon_label: Label = $Background/ComingSoonToast/ComingSoonLabel

@onready var setting_overlay: SettingsOverlay = $SettingOverlay
@onready var credits_overlay: CreditsOverlay = $CreditsOverlay

const PREMATCH_FLOW_SCENE := "res://scenes/ui/PreMatchFlow.tscn"
const COMING_SOON_DURATION := 1.5

var _toast_token := 0
```

In `_ready()`, connect the two new buttons:

```gdscript
func _ready() -> void:
	# Mobile: hide Exit (Android usually doestn need it)
	#if OS.has_feature("android") or OS.has_feature("ios"):
		#$ExitButton.visible = false
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0-dev")
	main_buttons.visible = true
	exit_button.visible = true
	start_arena_buton.pressed.connect(_on_start_arena_buton_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	credits_button.pressed.connect(_on_credits_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	mail_button.pressed.connect(_show_coming_soon.bind("Mail"))
	gift_button.pressed.connect(_show_coming_soon.bind("Gift"))
	#setting_overlay.visible = false
```

Add the toast function (placement: anywhere after `_ready()`, e.g. right before
`_on_start_arena_buton_pressed`):

```gdscript
# Docasny "Coming soon" toast pre placeholder tlacidla (Mail/Gift teraz, dalsie
# pribudnu v kroku 3 — nav rail). _toast_token zaruci ze rychle po sebe idúce
# tapnutia (napr. Mail hned po Gift) predlzia zobrazenie namiesto toho aby ho
# predcasne schovali — kazdy show() zrusi platnost predchadzajuceho timeoutu.
func _show_coming_soon(feature_name: String) -> void:
	coming_soon_label.text = "%s — coming soon" % feature_name
	coming_soon_toast.visible = true
	_toast_token += 1
	var token := _toast_token
	get_tree().create_timer(COMING_SOON_DURATION).timeout.connect(func():
		if token == _toast_token:
			coming_soon_toast.visible = false
	)
```

Leave every other function in this file untouched.

## DO NOT TOUCH

- `StartArenaButon`, `CreditsButton`, `ExitButton` and their child Labels — unchanged, gets
  reworked in Step 3.
- `FooterBar` and its children (Step 1) — untouched.
- `SettingOverlay`, `CreditsOverlay` node instances and their scenes/scripts — untouched.
- `_on_start_arena_buton_pressed`, `_on_settings_button_pressed`, `_on_credits_button_pressed`,
  `_on_setting_overlay_close_requested`, `_on_credits_overlay_closed`, `_on_exit_button_pressed`
  — untouched (only the `settings_button` path they reference changed, not their bodies).
- `project.godot` — no changes this step.

## Out of scope

- Do NOT add a "+" buy-currency button next to `CurrencyAmountLabel` — no shop/purchase flow
  exists yet; this is a pure display placeholder for now.
- Do NOT add a player level/name/avatar element to the top bar — flagged above as intentionally
  omitted pending an actual player-profile system.
- Do NOT theme `Mail`/`Gift`'s hover/pressed button states — `normal` style only.
- Do NOT wire `CurrencyAmountLabel` to any real value — it's a static `"0"` until an economy
  system exists.

## VERIFY

1. `grep -n "TopBar\|MailButton\|GiftButton\|ComingSoonToast" scenes/menu/MainMenu.tscn` —
   confirm the new subtree is present.
2. `grep -n "SettingsButton" scenes/menu/MainMenu.tscn` — confirm it now appears once, under
   `TopBar`, not under `MainButtons/VBoxContainer2`.
3. `grep -n "settings_button\|mail_button\|gift_button\|_show_coming_soon" scripts/ui/main_menu.gd`
   — confirm the updated path and new onready vars/function are present.
4. Run the main menu: confirm a slim status bar renders at the very top with a gold-ish square +
   `"0"` on the left, and `Mail`/`Gift`/`Settings` buttons on the right — and that
   `MainButtons` (Arena / Credits+Exit) no longer overlaps it, sitting cleanly below.
5. Tap `Settings` in its new top-bar location: confirm it still opens the settings overlay
   correctly (unchanged behavior, only its position/size changed).
6. Tap `Mail`, then `Gift`: confirm the "Coming soon" toast appears each time with the correct
   feature name, and auto-hides after ~1.5s. Tap one right after the other and confirm the toast
   doesn't flicker/hide prematurely between the two taps.
7. Confirm `Arena`, `Credits`, `Exit` buttons all still work exactly as before.
8. Confirm the footer from Step 1 is unaffected and still renders correctly at the bottom.
