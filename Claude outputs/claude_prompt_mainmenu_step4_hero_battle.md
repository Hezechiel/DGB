# DGB — Main Menu Redesign, Step 4: Hero Showcase + Battle Card

**Start in Plan Mode.** Read the two files below in full, present your exact diff
plan, and wait for my approval before editing anything.

Files involved:
- `scenes/menu/MainMenu.tscn`
- `scripts/ui/main_menu.gd`

Read-only reference (do not edit):
- `data/heroes/frames/frames_zeus.tres`
- `data/heroes/hero_zeus.tres`

## Context

This is the 4th and final step of the main-menu redesign (Step 1: footer,
Step 2: top bar, Step 3: left nav rail — all already applied and confirmed
working). Step 4 fills the empty center of the menu with a live Zeus idle
showcase and relocates the primary "start match" action into a single big
"Battle" card on the right, matching the Force Arena reference screenshot's
hub layout (nav rail on the left for account-y features, big hero art in the
middle, primary CTA on the right).

**Correction to my own earlier assumption**: I previously described Zeus's
idle art as a 400×400 frame. Having re-read `frames_zeus.tres` directly, that
400×400 size is actually the `attack_left` animation (from `zeus_attack.png`).
The `iddle_left` animation — the one we want here — comes from
`zeus_iddle.png` and is 8 frames at **325×350px**, `loop = 1` (looping),
`speed = 5.0`. It's a real looping animation, not a single static frame, so
this step uses an `AnimatedSprite2D` with `sprite_frames` pointing at the
existing `frames_zeus.tres` resource and plays `iddle_left` — no new art
needed, no static-frame extraction required.

**Why the centering needs a tiny script instead of just anchors**: containers
(`HBoxContainer`, `CenterContainer`, etc.) only auto-arrange `Control`
children. `AnimatedSprite2D` is a `Node2D`, so a container will not center it
automatically — its `position` has to be set manually. Because
`window/stretch/aspect = "expand"` means the actual pixel size of the content
area varies by device, we center it via the `resized` signal on its parent
`Control` rather than a hardcoded position, so it stays correctly centered
across aspect ratios (same reasoning as the anchored-button fixes earlier in
this menu rework).

**Primary CTA relocation**: `StartArenaButon` currently lives in `NavRail`
(placed there temporarily in Step 3, before this step gave it a proper home).
This step removes it from `NavRail` entirely and replaces it with a single
`BattleCard` button on the right of the new content area — there is only one
real game mode in DGB right now, so per the earlier decision this is one big
card, not a row of mode cards with locked/disabled placeholders next to it.

## Part A — `scenes/menu/MainMenu.tscn`

### A1. Add a new ext_resource for Zeus's sprite frames

After the existing `id="9_bvc5d"` ext_resource line (the `credits_overlay.tscn`
one), add:

```
[ext_resource type="SpriteFrames" uid="uid://75pi7xqp2vus" path="res://data/heroes/frames/frames_zeus.tres" id="10_zeusframes"]
```

### A2. Add a new StyleBoxFlat for the Battle card

After the existing `StyleBoxFlat_rewards` sub_resource block (right before the
`[node name="MainMenu" ...]` node block), add:

```
[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_battle"]
bg_color = Color(0.75, 0.15, 0.1, 1)
border_width_left = 3
border_width_top = 3
border_width_right = 3
border_width_bottom = 3
border_color = Color(1, 0.8, 0.3, 1)
corner_radius_top_left = 12
corner_radius_top_right = 12
corner_radius_bottom_right = 12
corner_radius_bottom_left = 12
```

(Gold border on a red field — just a placeholder accent to make the primary
CTA read as more important than the flat Deck/Heroes/Shop/Rewards buttons.
Change the colors freely if you don't like them; nothing downstream depends
on the exact values.)

### A3. Remove `StartArenaButon` and its `Label` from `NavRail`

Currently `NavRail`'s first two children are:

```
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
```

Delete both node blocks entirely. `NavRail`'s first child becomes
`DeckButton`.

### A4. Add the new `MainContent` subtree

Insert this right after `NavRail`'s `ExitLabel` node block ends (`text =
"Exit"`) and before the `[node name="TopBar" ...]` block:

```
[node name="MainContent" type="HBoxContainer" parent="Background"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 130.0
offset_top = 50.0
offset_right = -20.0
offset_bottom = -30.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme_override_constants/separation = 20

[node name="HeroShowcase" type="Control" parent="Background/MainContent"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 3
mouse_filter = 2

[node name="ZeusIdle" type="AnimatedSprite2D" parent="Background/MainContent/HeroShowcase"]
sprite_frames = ExtResource("10_zeusframes")
animation = &"iddle_left"
autoplay = "iddle_left"
flip_h = true
scale = Vector2(1.2, 1.2)

[node name="BattleCard" type="Button" parent="Background/MainContent"]
custom_minimum_size = Vector2(220, 280)
layout_mode = 2
size_flags_vertical = 4
theme_override_font_sizes/font_size = 28
theme_override_styles/normal = SubResource("StyleBoxFlat_battle")
text = "Battle"
```

Notes on the numbers: `offset_left = 130.0` clears `NavRail` (which ends at
`offset_right = 118.0`) with a small gap; `offset_top = 50.0` matches
`NavRail`'s own top; `offset_bottom = -30.0` sits just above `FooterBar`.
`flip_h = true` makes Zeus face right, toward the Battle card — flip it back
to `false` if you'd rather he face the camera/left; it's purely cosmetic.

## Part B — `scripts/ui/main_menu.gd`

### B1. Onready vars

Replace this line:

```gdscript
@onready var start_arena_buton: TextureButton = $Background/NavRail/StartArenaButon
```

with:

```gdscript
@onready var main_content: HBoxContainer = $Background/MainContent
@onready var hero_showcase: Control = $Background/MainContent/HeroShowcase
@onready var zeus_idle: AnimatedSprite2D = $Background/MainContent/HeroShowcase/ZeusIdle
@onready var battle_button: Button = $Background/MainContent/BattleCard
```

### B2. `_ready()`

Replace:

```gdscript
	start_arena_buton.pressed.connect(_on_start_arena_buton_pressed)
```

with:

```gdscript
	battle_button.pressed.connect(_on_battle_button_pressed)
	# Node2D deti Control containera sa necentruju automaticky (HBoxContainer
	# rata len s Control potomkami) — preto centrujeme ZeusIdle rucne cez
	# HeroShowcase.resized, aby to sedelo spravne aj pri roznom aspect ratio
	# (window/stretch/aspect = "expand").
	hero_showcase.resized.connect(_on_hero_showcase_resized)
	_on_hero_showcase_resized()
```

Leave every other line in `_ready()` (`version_label...`, `nav_rail.visible =
true`, `settings_button...`, `exit_button...`, `mail_button...`,
`gift_button...`, `deck_button...`, `heroes_button...`, `shop_button...`,
`rewards_button...`) exactly as-is.

### B3. New handler + rename

Replace:

```gdscript
func _on_start_arena_buton_pressed() -> void:
	get_tree().change_scene_to_file(PREMATCH_FLOW_SCENE)
```

with:

```gdscript
func _on_hero_showcase_resized() -> void:
	zeus_idle.position = hero_showcase.size / 2

func _on_battle_button_pressed() -> void:
	get_tree().change_scene_to_file(PREMATCH_FLOW_SCENE)
```

### B4. Hide/show `MainContent` alongside `NavRail`

`nav_rail.visible` is toggled in four places so the nav rail doesn't stay
interactable behind the fullscreen Settings/Credits overlays. Mirror the same
toggle for `main_content` in all four spots:

```gdscript
func _on_settings_button_pressed() -> void:
	nav_rail.visible = false
	main_content.visible = false
	setting_overlay.move_to_front()
	setting_overlay.open(false)

func _on_credits_button_pressed() -> void:
	nav_rail.visible = false
	main_content.visible = false
	credits_overlay.move_to_front()
	credits_overlay.open()

func _on_setting_overlay_close_requested() -> void:
	setting_overlay.close()
	nav_rail.visible = true
	main_content.visible = true

func _on_credits_overlay_closed() -> void:
	nav_rail.visible = true
	main_content.visible = true
```

(Only add the `main_content.visible` lines — don't rewrite the surrounding
comments/logic beyond that.)

## DO NOT TOUCH

- `TopBar` and its children (`CurrencyGroup`, `MailButton`, `GiftButton`,
  `SettingsButton`) — untouched by this step.
- `FooterBar` and its children.
- `ComingSoonToast` / `_show_coming_soon()` and the Mail/Gift/Deck/Heroes/
  Shop/Rewards `pressed` connections — untouched.
- `NavRail`'s `DeckButton`, `HeroesButton`, `ShopButton`, `RewardsButton`,
  `NavRailSpacer`, `ExitButton`/`ExitLabel` — untouched except that
  `StartArenaButon`/`Label` are removed (A3).
- `scenes/menu/setting_overlay.tscn`, `scenes/menu/credits_overlay.tscn`, and
  their scripts — not part of this step.
- `data/heroes/frames/frames_zeus.tres`, `data/heroes/hero_zeus.tres` —
  read-only reference, do not modify.
- `scenes/ui/PreMatchFlow.tscn` and anything under `scripts/arena/` —
  unrelated to this step.
- `project.godot` — no changes needed here.

## Out of scope

- No hover/pressed-state art for `BattleCard` — it uses the same
  "override `styles/normal` only, let the default theme handle hover/pressed"
  pattern as `MailButton`/`GiftButton`/`DeckButton`/etc.
- No additional mode cards (2v2, Training, ranked, event modes, etc.) next to
  Battle — DGB has one real mode right now, so one card.
- No player level/avatar/profile element next to the hero art.
- No support for showing any hero other than Zeus (Poseidon, future heroes) —
  matches the existing hardcoded `TEMP` hero selection in `arena.gd`.
- No sound on the idle animation or on Battle-card press.
- No extra responsive polish beyond the `resized`-driven centering specified
  above (no dynamic scale-to-fit, no orientation handling, etc.).

## VERIFY

1. `grep -n "StartArenaButon" scenes/menu/MainMenu.tscn` → no matches.
2. `grep -n "_on_start_arena_buton_pressed" scripts/ui/main_menu.gd` → no
   matches (renamed to `_on_battle_button_pressed`).
3. `grep -n "BattleCard\|StyleBoxFlat_battle\|10_zeusframes\|iddle_left"
   scenes/menu/MainMenu.tscn` → all four present.
4. `grep -n "hero_showcase\|zeus_idle\|battle_button\|main_content"
   scripts/ui/main_menu.gd` → all four onready vars present, each used at
   least once below their declaration.
5. Open `scenes/menu/MainMenu.tscn` in the Godot editor — confirm no parse
   errors/orphan-node warnings in the output panel.
6. Run the project to the main menu: confirm Zeus's idle animation is
   visibly playing (looping, facing right) roughly centered in the space
   between the nav rail and the Battle card.
7. Confirm the Battle card renders with the red/gold placeholder styling and
   "Battle" text, positioned to the right of the hero art.
8. Tap the Battle card → scene changes to `PreMatchFlow.tscn` (same behavior
   the old Arena nav-rail button had).
9. Tap Settings → confirm the hero showcase and Battle card are hidden and
   not clickable while the Settings overlay is open, same as the nav rail;
   close Settings → both reappear. Repeat for Credits (via Settings →
   Credits).
10. Confirm `NavRail` now reads top-to-bottom as: Deck, Heroes, Shop,
    Rewards, (spacer), Exit — no Arena entry left in the rail.
