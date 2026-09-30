# Claude Code prompt — VICTORY / DEFEAT banner during the base-destroyed end sequence

**Start in Plan Mode.** Read every file listed below, then present a plan with the exact diffs. Do not edit anything until I approve the plan.

## Context

The base-destroyed end sequence has landed. `arena.gd::_play_end_sequence(winner)` does four things: it hides the HUD, fades the music out, calls `arena_camera.play_focus()` on the fallen base, then after `END_SEQUENCE_SECONDS` (3.5 s) changes scene to `MatchEndScreen`. The collapse sound comes from `base.gd`.

This step adds the result **banner** on top of those 3.5 s, the classic MOBA "VICTORY" / "DEFEAT" slam. It also adds a short fade to black right before the scene change, so the jump to `MatchEndScreen` doesn't cut.

Constraints:
- **The banner can't live in the HUD**, because the HUD is hidden during the sequence. It gets its own `CanvasLayer` scene, instanced in `arena.tscn` next to `HUD`.
- **Code/scene only, no art assets.** Use `ColorRect`s and `Label`s with the fonts the project already has (`assets/fonts/CinzelDecorative-Black.ttf`, `Marcellus-Regular.ttf`). I'll swap in textures later, so keep node names stable.
- **Presentation only.** The banner reads the `winner` string it's given. It doesn't touch `BattleManager` or connect to any signal. `arena.gd` stays the single place that drives the sequence.

## Files to read first

- `scripts/arena/arena.gd` (`END_SEQUENCE_SECONDS`, `_on_match_ended()`, `_play_end_sequence()`, `@onready` vars)
- `scenes/arena/arena.tscn` (child order, `DesaturateRect`, `HUD`)
- `scenes/arena/ui/DeathTelegraph.tscn` + `scripts/arena/ui/death_telegraph.gd`: read only; they're the reference for an overlay `CanvasLayer` scene, its font setup, and `mouse_filter` on its labels
- `scripts/arena/desaturate_overlay.gd`: read only
- `scenes/hud/HUD.tscn`: read only (HUD is `layer = 10`)
- `project.godot` `[display]`: read only (1170×540, `canvas_items`, `expand`)

## Changes

### 1. NEW `scenes/arena/ui/MatchResultBanner.tscn`

```
MatchResultBanner (CanvasLayer)  layer = 20, visible = false, script = match_result_banner.gd
├── Band (ColorRect)             full-width horizontal strip, vertically centered:
│                                anchor_left 0 / anchor_right 1 / anchor_top 0.5 / anchor_bottom 0.5,
│                                offset_top -75 / offset_bottom 75, color = Color(0, 0, 0, 0.6),
│                                mouse_filter = IGNORE
│   ├── Title (Label)            full-rect in Band, h+v centered, text "VICTORY",
│   │                            font CinzelDecorative-Black.ttf, size 72,
│   │                            outline_size 8, font_outline_color black, mouse_filter = IGNORE
│   └── Subtitle (Label)         anchored to Band's bottom, h centered, text "",
│                                font Marcellus-Regular.ttf, size 18, font_color white (alpha 0.9),
│                                mouse_filter = IGNORE
└── Fade (ColorRect)             full rect, color = Color(0, 0, 0, 0) (fully transparent),
                                 mouse_filter = IGNORE
```

Every new node needs a unique `unique_id` in the file. `Fade` is declared **after** `Band`, so it draws on top of it.

### 2. NEW `scripts/arena/ui/match_result_banner.gd`

`extends CanvasLayer`, `class_name MatchResultBanner`. Reference implementation below. Keep its structure; flag small idiomatic fixes in the plan.

```gdscript
extends CanvasLayer
class_name MatchResultBanner

# Vysledkovy banner zaverecnej sekvencie (padla zakladna) — VICTORY / DEFEAT
# nad zamrazenym zaberom kamery. Ciste prezentacne: nevie nic o BattleManageri,
# dostane len winner string z arena.gd. Vlastny CanvasLayer, lebo HUD je
# pocas sekvencie skryty. Nazvy nodov nechat — neskor sa vymenia za textury.

const COLOR_VICTORY := Color(1.0, 0.82, 0.3)    # zlata
const COLOR_DEFEAT := Color(0.85, 0.15, 0.15)   # karmínova
const REVEAL_DELAY := 0.6    # kamera uz je v pohybe (play_focus trva 0.8 s)
const FADE_OUT_TIME := 0.35  # stmavnutie tesne pred zmenou sceny

@onready var band: ColorRect = $Band
@onready var title: Label = $Band/Title
@onready var subtitle: Label = $Band/Subtitle
@onready var fade: ColorRect = $Fade

func _ready() -> void:
	visible = false

# winner: "player" / "enemy" (z pohladu lokalneho hraca). total_duration =
# dlzka celej sekvencie z arena.gd — fade to black skonci presne na jej konci.
func show_result(winner: String, total_duration: float) -> void:
	var won := winner == "player"
	title.text = "VICTORY" if won else "DEFEAT"
	title.add_theme_color_override("font_color", COLOR_VICTORY if won else COLOR_DEFEAT)
	subtitle.text = "The enemy Command Post has fallen" if won else "Your Command Post has fallen"

	# vychodzi stav pred odhalenim
	band.scale = Vector2(1.0, 0.0)
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	fade.color.a = 0.0
	visible = true
	# pivot na stred — velkosti su znama az po layoute, preto az teraz
	band.pivot_offset = band.size / 2.0
	title.pivot_offset = title.size / 2.0
	title.scale = Vector2(1.6, 1.6)

	var t := create_tween()
	t.tween_interval(REVEAL_DELAY)
	# 1) pas sa "roztvori" zo stredu
	t.tween_property(band, "scale:y", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 2) titulok "dopadne" (zmensi sa z 1.6 na 1.0) a zviditelni sa
	t.tween_property(title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(title, "modulate:a", 1.0, 0.2)
	# 3) podtitulok
	t.tween_property(subtitle, "modulate:a", 1.0, 0.3)
	# 4) drz, potom stmavni celu obrazovku tesne pred zmenou sceny
	var used := REVEAL_DELAY + 0.25 + 0.35 + 0.3
	t.tween_interval(maxf(total_duration - used - FADE_OUT_TIME, 0.0))
	t.tween_property(fade, "color:a", 1.0, FADE_OUT_TIME)
```

Plan check: confirm that `band.size` / `title.size` are already laid out when `show_result()` is called mid-match. The node has been in the tree since the arena loaded; it's only hidden. If they aren't, set the pivots after `await get_tree().process_frame` and say so. **Don't hardcode pixel pivots.**

### 3. `scenes/arena/arena.tscn`

Instance `MatchResultBanner.tscn` as a direct child of `Arena`, **after** `HUD`, named `MatchResultBanner`, with a new `unique_id`. No other scene changes.

### 4. `scripts/arena/arena.gd`

- Add `@onready var result_banner: MatchResultBanner = $MatchResultBanner` next to the other `@onready` vars.
- In `_play_end_sequence(winner)`, directly after `hud.visible = false`:

  ```gdscript
  	$DesaturateRect.visible = false     # ak hrdina prave mrtvy, vitazny/prehrany zaber nema byt sedy
  	result_banner.show_result(winner, END_SEQUENCE_SECONDS)
  ```

- Nothing else changes: the draw path, the timer, the camera call and the audio calls stay as they are.

## DO NOT TOUCH

- `BattleManager.gd`, `base.gd`, `arena_camera.gd`, `AudioManager.gd`
- `match_end_screen.gd` / `MatchEndScreen.tscn`: it still shows the result and plays the stinger afterwards
- `desaturate_overlay.gd` and `DeathTelegraph`: only the `DesaturateRect` node's visibility is toggled from `arena.gd`
- `HUD.tscn` / `HUD.gd`
- `END_SEQUENCE_SECONDS` stays 3.5

## Explicitly OUT of scope

- Banner textures/art, particles, light rays, screen shake
- A banner sound or moving the stinger earlier (see my note to the user); no audio changes in this step
- Slow motion
- A banner for a draw (a draw still skips the sequence)
- Localization

## VERIFY

Static checks:
- `grep -rn "MatchResultBanner" scenes/ scripts/` → the new scene/script, one instance in `arena.tscn`, one `@onready` in `arena.gd`.
- `grep -n "BattleManager\|connect(" scripts/arena/ui/match_result_banner.gd` → no results.
- `git diff --stat` shows only `arena.gd` and `arena.tscn`, plus the two new files.

Runtime tests:
1. **Victory:** destroy the enemy base.
   - About 0.6 s in (while the camera is still moving), the dark band opens from the center.
   - "VICTORY" slams in gold (shrinks to size), and the subtitle "The enemy Command Post has fallen" fades in.
   - The banner holds; in the last ~0.35 s the screen fades to black.
   - `MatchEndScreen` appears with no visible cut. Total ≈ 3.5 s, as before.
2. **Defeat:** the same, but "DEFEAT" in red with "Your Command Post has fallen".
3. **Layout:** the banner is centered and full-width at the editor's 1170×540, and after resizing the game window to a wider and a taller aspect. Text isn't clipped at size 72.
4. **Hero dead at the moment of victory:** die with **H**, then quickly finish the base (or let the AI win while you're dead). The end shot is in color, not grey, and no "GOD DEAD" label shows (the HUD is hidden).
5. Tapping during the banner does nothing (it doesn't block anything or cause errors).
6. **Draw** → `MatchEndScreen` immediately, no banner.
7. **Next match** starts clean: no banner and no black fade visible.

Stop after this step and report: the diff summary, anything in the plan you changed (especially the pivot/layout check), and any test you couldn't run.
