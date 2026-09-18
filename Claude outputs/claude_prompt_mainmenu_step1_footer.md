# Claude Code Prompt — Main menu redesign, Step 1: footer status line

**Enter Plan Mode first.** Present the full diff for review before touching any files.

## Context

First of 4 planned steps reworking `MainMenu.tscn` toward a Force-Arena-style hub layout
(top status bar, left nav rail, center hero showcase, right mode card — later steps). This
step only handles the footer: the large `Title` label currently at the top of the menu
("Duel of Gods: Babylon", 44pt `CinzelDecorative-Bold`, gold with drop shadow) is relocated to
a small, unformatted status line at the bottom of the screen, alongside a version number and a
static "server online" indicator.

Two things worth being upfront about:

- **The version number becomes a real (if trivial) project setting**, not a second hardcoded
  string. `project.godot` currently has no `config/version` at all. Rather than hardcode the
  version text directly into the label (which would mean hunting through a scene file to bump
  it later), this adds `config/version` to `project.godot`'s `[application]` section and reads
  it at runtime — one place to update it going forward. Not explicitly asked for, but the
  cheaper and more idiomatic way to do this in a Godot project; flag if you'd rather just
  hardcode the label text instead.
- **The "server online" text is 100% cosmetic.** There is no networking/matchmaking layer in
  this project yet (`game_design.md` lists real matchmaking as undecided, and
  `PreMatchFlow` is a mock timer, not a real connection). This label is static text, not backed
  by any check — it exists purely to complete the visual footer per your request, and will need
  real wiring whenever a networking layer exists.

This step does **not** touch `MainButtons` (the Arena/Settings/Credits/Exit button cluster) —
that gets replaced entirely in Step 3 (nav rail). Removing `Title` will leave a blank gap above
`MainButtons` in the interim, since `Background/HBoxContainer`'s fixed 252px top band isn't
being resized in this step — expected and temporary, not worth tuning now since that whole
container gets reworked in 1–2 steps anyway.

## Files to inspect first (Plan Mode — read before editing)

- `scenes/menu/MainMenu.tscn`
- `scripts/ui/main_menu.gd`
- `project.godot`

Confirm current content matches what's described below before applying — if the live files
differ, stop and flag the mismatch instead of guessing.

## Changes

### 1. `project.godot`

In the `[application]` section, add a version line right after `config/features`:

```
config/name="Duel of Gods: Babylon"
run/main_scene="uid://26kaj1qw10dd"
config/features=PackedStringArray("4.7", "Mobile")
config/version="0.1.0"
```

Pick whatever starting version string you actually want here — `0.1.0` is a placeholder for a
pre-release build, not a meaningful number I derived from anything. Leave every other section
of this file untouched.

### 2. `scenes/menu/MainMenu.tscn`

Remove the `Title` node block entirely:

```
[node name="Title" type="Label" parent="Background/HBoxContainer" unique_id=236994376]
theme_override_colors/font_color = Color(1, 0.827451, 0, 1)
theme_override_constants/shadow_offset_x = 1
theme_override_constants/shadow_offset_y = 1
theme_override_fonts/font = ExtResource("3_ekkse")
theme_override_font_sizes/font_size = 44
text = "Duel of Gods: Babylon"
horizontal_alignment = 1
```

(Exact property list above may not match line-for-line with what Plan Mode shows you — match
by node name/path, not by copying this block verbatim over what's actually there.)

After removing `Title`, the `3_ekkse` (`CinzelDecorative-Bold.ttf`) `ext_resource` declaration
at the top of the file becomes unused — grep the file first to confirm nothing else references
it (it shouldn't; only `Title` used it), then remove that `ext_resource` line too.

Add a new `FooterBar` node and its children as the last children under `Background` (after the
existing `HBoxContainer` subtree — i.e. after the `ExitButton`/`ExitLabel` block, before the
`[connection ...]` lines at the bottom of the file):

```
[node name="FooterBar" type="HBoxContainer" parent="Background"]
layout_mode = 1
anchors_preset = 12
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 12.0
offset_top = -22.0
offset_right = -12.0
offset_bottom = -4.0
grow_vertical = 0
mouse_filter = 2
alignment = 1
theme_override_constants/separation = 16

[node name="FooterTitleLabel" type="Label" parent="Background/FooterBar"]
layout_mode = 2
theme_override_colors/font_color = Color(0.7, 0.7, 0.7, 0.8)
theme_override_font_sizes/font_size = 12
text = "Duel of Gods: Babylon"

[node name="FooterSep1" type="Label" parent="Background/FooterBar"]
layout_mode = 2
theme_override_colors/font_color = Color(0.5, 0.5, 0.5, 0.6)
theme_override_font_sizes/font_size = 12
text = "•"

[node name="VersionLabel" type="Label" parent="Background/FooterBar"]
layout_mode = 2
theme_override_colors/font_color = Color(0.7, 0.7, 0.7, 0.8)
theme_override_font_sizes/font_size = 12
text = "v0.0.0"

[node name="FooterSep2" type="Label" parent="Background/FooterBar"]
layout_mode = 2
theme_override_colors/font_color = Color(0.5, 0.5, 0.5, 0.6)
theme_override_font_sizes/font_size = 12
text = "•"

[node name="ServerStatusLabel" type="Label" parent="Background/FooterBar"]
layout_mode = 2
theme_override_colors/font_color = Color(0.7, 0.7, 0.7, 0.8)
theme_override_font_sizes/font_size = 12
text = "Server: Online"
```

Notes: no `theme_override_fonts` set on any of these — they deliberately fall back to the
default project font rather than the decorative `CinzelDecorative`/`Marcellus` fonts used
elsewhere, per "small font text without formatting." No `unique_id` on the new nodes (several
existing nodes in this project, e.g. the arena `Minimap` instance, already omit it — it's an
editor convenience, not required for the nodes to work). `VersionLabel`'s `text = "v0.0.0"` is
just an editor-preview default; the real value is set at runtime in step 3 below.

### 3. `scripts/ui/main_menu.gd`

Add an onready var and set its text in `_ready()`:

```gdscript
@onready var version_label: Label = $Background/FooterBar/VersionLabel
```

In `_ready()`, add this line (placement doesn't matter relative to the existing lines, but
grouping it near the top is fine):

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
	#setting_overlay.visible = false
```

Leave every other function in this file untouched.

## DO NOT TOUCH

- `MainButtons`, `VBoxContainer`/`VBoxContainer2`, `StartArenaButon`, `SettingsButton`,
  `CreditsButton`, `ExitButton` and their child Labels — unchanged, gets reworked in Step 3.
- `SettingOverlay`, `CreditsOverlay` node instances and their scenes/scripts — untouched.
- `_on_start_arena_buton_pressed`, `_on_settings_button_pressed`, `_on_credits_button_pressed`,
  `_on_setting_overlay_close_requested`, `_on_credits_overlay_closed`, `_on_exit_button_pressed`
  in `main_menu.gd` — untouched.
- `Background`'s own properties (`StyleBoxTexture_mgsx5`, anchors) — untouched, only gains one
  new child (`FooterBar`).
- Any other section of `project.godot` (autoloads, display, layer_names, physics, rendering).

## Out of scope

- Do NOT resize or reposition `Background/HBoxContainer` (the top band) to close the gap left
  by removing `Title` — that whole subtree is replaced in Step 3.
- Do NOT wire up any real server/connectivity check for `ServerStatusLabel` — it's static text
  until a networking layer exists.
- Do NOT add any separator graphics/lines beyond the plain "•" glyph labels.

## VERIFY

1. `grep -n "config/version" project.godot` — confirm the new line is present under
   `[application]`.
2. `grep -n "Title\|FooterBar\|VersionLabel\|ServerStatusLabel" scenes/menu/MainMenu.tscn` —
   confirm the old `Title` node block is gone, `FooterBar` and its 5 children are present.
3. `grep -n "3_ekkse\|CinzelDecorative-Bold" scenes/menu/MainMenu.tscn` — confirm no remaining
   references (both the `ext_resource` line and any node using it should be gone).
4. `grep -n "version_label" scripts/ui/main_menu.gd` — confirm the onready var and the
   `_ready()` assignment are both present.
5. Run the main menu: confirm no large gold title renders at the top anymore, and a small,
   plain (non-bold, no drop shadow) footer line reads
   `Duel of Gods: Babylon • v0.1.0 • Server: Online` centered near the bottom of the screen.
6. Confirm all 4 existing main-menu buttons (Arena/Settings/Credits/Exit) still work exactly as
   before — this step shouldn't have touched their behavior at all, only the `Title` node above
   them.
7. Confirm the Settings and Credits overlays (from the earlier z-order fix) still open on top of
   everything correctly, including now rendering over `FooterBar` when open (full-screen
   overlays should cover the footer too, not show it poking through).
