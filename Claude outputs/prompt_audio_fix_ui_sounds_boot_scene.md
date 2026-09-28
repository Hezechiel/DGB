# Claude Code prompt — Fix: UI tap sounds missing in the boot scene (MainMenu)

**Start in Plan Mode.** Read the file listed below, then present a plan with the exact diff. Do not edit anything until I approve the plan.

## Context / root cause (already confirmed)

When the game boots, no MainMenu button plays `ui_select` or `ui_close`.

`AudioManager` wires tap sounds by connecting to `get_tree().node_added` in its `_ready()`. At boot, however, the autoloads **and** the main scene (`MainMenu.tscn`) are both under `root` before the SceneTree initializes. Godot then runs `_enter_tree` for the whole tree, which fires every `node_added`, and only after that runs `_ready`. So by the time `AudioManager._ready()` connects the signal, every MainMenu button has already entered the tree, and none of them get wired.

I reproduced this in a minimal Godot 4.7 headless project: the autoload's `_ready()` sees 2 buttons already in the tree, and the `node_added` handler is called 0 times for them. Scenes loaded later (PreMatchFlow, arena HUD, MainMenu after returning from a match) are wired correctly, because the connection exists by then.

## Change — `scripts/AudioManager.gd` only

In `_ready()`, directly after `get_tree().node_added.connect(_on_node_added)`, wire the nodes that are already in the tree:

```gdscript
	# Boot scena (MainMenu) vstupi do stromu SPOLU s autoloadmi — vsetky jej
	# node_added prebehnu este pred tymto _ready(), takze connect vyssie ich
	# nezachyti. Preto jednorazovo prejdeme uzly, ktore uz v strome su.
	# Dvojite zapojenie nehrozi — _on_node_added() ma guard cez meta _ui_sfx_wired.
	for n in get_tree().root.find_children("*", "", true, false):
		_on_node_added(n)
```

`_on_node_added()` itself stays unchanged: its type filter and meta guard already make it safe to call on any node.

## DO NOT TOUCH

- Everything else in `AudioManager.gd`: music, SFX pool, voice, announcer, stinger, volume
- Every scene file and the button groups (`CloseSettings` and `CloseCredits` already have `ui_sfx_close`)
- `main_menu.gd` and `setting_overlay.gd`: no manual per-button connects

## Explicitly OUT of scope

- New UI sounds (card pickup/cancel, no-energy)
- Any change to how groups are read

## VERIFY

- `git diff --stat` → only `scripts/AudioManager.gd`, +~6 lines.
- **Cold start the game (F5):** every MainMenu button (nav rail, top bar, Battle, Settings) plays `ui_select` on the first tap after boot.
- **Settings and Credits close X** → `ui_close`. Checkbox and credits buttons → `ui_select`.
- Each tap plays **exactly once**, with no doubled or louder click. This checks that the meta guard stops double wiring.
- Go to a match and back to the menu → buttons still play once per tap (not twice).
- In-match pause button + settings overlay → still work as before.
- No new errors or warnings on boot.

Stop after this step and report the diff.
