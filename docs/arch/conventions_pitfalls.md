# Conventions & known pitfalls — DGB architecture

> Part of docs/architecture.md — see the index there.

## Conventions & known pitfalls (hard-won)

- Signal connections in `_ready()`, not the Inspector.
- `configure()` must be callable **before** `add_child()` — use `$Node` paths
  inside it, not `@onready` vars.
- Child `_ready()` runs before parent `_ready()` → per-match resets belong in the
  arena's `_enter_tree()`.
- `is_instance_valid()` guards wherever a stored target can die.
- `CollisionShape2D` shape resources: mark **Local to Scene**; never mutate shared
  shapes at runtime.
- Leash/exit logic: don't rely on `body_exited` at the same boundary as
  `body_entered`; use `_physics_process` distance checks.
- `get_path()` is reserved on Node — lane paths use `get_lane_path()`.
- Android: `.tres.remap` suffix stripping in any `DirAccess` scan;
  `emulate_mouse_from_touch = true`; `TextureButton` for menus,
  `TouchScreenButton` in-game.
- UI art scaling: `TextureRect` with `EXPAND_IGNORE_SIZE` +
  `KEEP_ASPECT_CENTERED` — never manual scale factors.
- Autoload state outlives scenes: every new per-match variable in BattleManager
  **must** be added to `reset_match_state()` (or documented as persistent).
- Card drag input is tracked in `card_hand.gd::_input()` by touch index, not in
  `_gui_input`. `_input` runs before the GUI system and before `_unhandled_input`,
  so consuming there deterministically starves `arena_camera.gd` (pan) and
  `arena.gd` (tap-to-move). `Card._gui_input` only detects the press and hands off
  to `CardHand.begin_drag()`. The drag path deliberately does NOT use
  `InputR.suppress_next_release()` — it consumes its own release; that one-shot flag
  would otherwise linger and swallow the next tap-to-move.
- **Resolved:** the above starvation is why drag-to-deploy needed its own
  camera hook instead of reusing `arena_camera.gd`'s pan handler. `ArenaCamera`
  now exposes `begin_deploy_pan()` / `update_deploy_pan(screen_pos)` /
  `end_deploy_pan()`, driven from `arena.gd`'s existing
  `deploy_preview_started` / `deploy_preview_updated` / `deploy_preview_ended`
  handlers rather than from raw input — `deploy_preview_updated` now also
  carries the drag's screen position (not just world position) specifically
  so the camera can do screen-edge proximity panning without ever needing the
  starved input events. Runs independently of `Settings.lock_camera` (checked
  in `_physics_process` *before* the lock gate); only the post-release
  behaviour branches on lock state, and does so by reusing the existing
  `_return_timer`/`_return_ramp`/`return_delay`/`return_ramp_time` fields
  rather than adding a parallel return mechanism.
- **`Camera2D`'s native `limit_left`/`limit_right`/`limit_top`/`limit_bottom`
  are a second, engine-level clamp — separate from `arena_camera.gd`'s own
  `bounds_min`/`bounds_max` + `_clamp_to_bounds()`.** Both can be active at
  once, and the engine's native limit wins if it's more restrictive, which
  makes changing `bounds_min`/`bounds_max` in the Inspector look like it does
  nothing. `arena_camera.gd` now forces the native limits wide open in
  `_ready()` so `bounds_min`/`bounds_max` is unconditionally the only clamp
  that applies, regardless of whatever `limit_*` values happen to be saved on
  the `Camera2D` node (easy to inherit by duplicating a scene, since it's a
  separate Inspector section from the script's own exported vars).
- **Resolved:** the two independently-hardcoded bounds systems referenced
  above (native `Camera2D` limits vs. the script's own `bounds_min`/
  `bounds_max`) are now both driven from one place — `MapData.bounds`,
  applied via `arena_camera.configure_map(map_data)` — and
  `BattleManager.deploy_bounds` (formerly a `const DEPLOY_BOUNDS`, now
  mutable) is set from the same resource via
  `BattleManager.configure_map(map_data)`, both called once from
  `arena.gd._ready()`. One `MapData.tres` per map now fully describes bounds,
  camera pan tuning, and hero spawn points (`data_layer.md`).
- **`ArenaCamera`'s initial `position`/`zoom` are NOT per-map.** They're
  hardcoded on the `Camera2D` node inside `arena.tscn` (the shared shell) —
  `configure_map()` only ever touches `bounds_min`/`bounds_max`/
  `edge_margin`/`edge_pan_speed_max`. Works today because both existing
  maps (`GreekPlateauMap`, `NordPlainsMap`) share the same bounds size; a
  map with meaningfully different dimensions will likely need this
  addressed (a `camera_start_position`/`camera_start_zoom` on `MapData`,
  most likely) — noted in `map_authoring_guide.md` §2.9, not built yet.
- `CardHand` is inside a CanvasLayer → screen→world goes through
  `get_viewport().get_canvas_transform()`, not plain `get_canvas_transform()`
  (which returns the layer transform). Node2Ds like `arena.gd` use the plain form.
- **A second autoload (`EnergySystem`) now holds per-match state outside
  `BattleManager.reset_match_state()`.** Its OWN `reset_match_state()` must be called
  from `arena._enter_tree()` alongside BattleManager's. Same pitfall as the
  BattleManager reset rule above, second owner: every new per-match field in
  EnergySystem must be reset there, or it leaks across matches (leaked modifiers,
  stale energy).
- HUD child `process_mode`: the `HUD` CanvasLayer is `WHEN_PAUSED` (so the settings
  overlay runs while paused); children that must run DURING play set their own
  `process_mode`. `EnergyBar` is `PAUSABLE` — it polls in `_process()`, so inheriting
  `WHEN_PAUSED` would freeze the bar during play and only move it while paused.
- Typing a bar reference as `Range` (the shared base of `ProgressBar` and
  `TextureProgressBar`) let the energy bar's placeholder→textured swap happen
  with zero script change — `energy_bar.gd` still only touches
  `min_value`/`max_value`/`value`. Reach for the base class when a UI node is a
  known future art-swap target.
- **A third autoload (`HealingSystem`) also holds per-match state outside
  `BattleManager.reset_match_state()`.** Its OWN `reset_match_state()` must be
  called from `arena._enter_tree()` alongside BattleManager's and
  EnergySystem's. Same pitfall as the EnergySystem reset rule above, third
  owner: every new per-match field in HealingSystem must be reset there, or it
  leaks across matches (stale pod cooldowns, stuck HoT).
- Hero `Hurtbox` groups (`player_hurtbox`/`enemy_hurtbox`) — added for
  collision-layer/team wiring — turned out reusable as a plain team-detection
  signal for non-combat systems too, not just combat targeting:
  `HealingPod._on_area_entered()` reads the group off the entering Area2D to
  resolve team, no layer-bit math needed. Worth reaching for before inventing
  a parallel team-tag mechanism.
- **Autoload enums can't be used as type annotations or `match` patterns.**
  `HeroAI.State` can't do `var s: HeroAI.State` or `match s: HeroAI.State.X:`
  — an autoload is a singleton *instance*, not a `class_name`, so its enum
  isn't a real type in that sense. Runtime access like
  `HeroAI.State.LOW_HP` in expressions/comparisons is fine; cache the
  value as untyped/`int` and branch with `if`/`elif` instead of `match`.
- **An autoload's `get_tree().node_added` listener never sees the boot
  scene.** At startup the autoloads *and* the main scene (`MainMenu.tscn`)
  are all under `root` before the SceneTree initializes; Godot runs
  `_enter_tree` (which emits every `node_added`) for the whole tree first
  and only then `_ready`. So a listener connected in an autoload's
  `_ready()` misses every node of the first scene — that's why MainMenu
  buttons had no tap sound while later scenes did (confirmed in a minimal
  Godot 4.7 headless repro). Fix/pattern: after connecting, also walk the
  nodes already present once (`get_tree().root.find_children("*", "",
  true, false)`) through the same handler, with an idempotency guard
  (`AudioManager` uses meta `_ui_sfx_wired`). Applies to any future
  "auto-wire every X" autoload.
- **Looping sounds never go through a stealable voice pool.** A loop would
  hold a pool voice forever, and priority stealing would silence it
  permanently. Ambient beds own their own `AudioStreamPlayer`
  (`AmbientEmitter` LOOP mode); only finite one-shots use `play_sfx()`.
  Corollary: a one-shot `.ogg` imported with `loop=true` (Godot's OGG
  default can be on) plays forever and pins a voice — check the Import dock
  when adding any one-shot OGG (`amb_greek_cymbals.ogg` hit this).
- **Attack sounds fire at the damage point, not at swing start.** Hero and
  unit `attack_sfx` play where the hit lands (melee) or the projectile is
  released (ranged) — a hero's windup is cancelable (`combat_movement.md`), and a swing-start
  sound would play for swings that never happened.
- **The match result is logic; the ending is presentation.** When a base
  falls, `BattleManager.on_base_destroyed()` still decides the winner and
  emits `match_ended` in the same frame — nothing in `BattleManager` waits.
  The 3.5 s end sequence (camera, banner, fade, delayed scene change) lives
  entirely in `arena.gd` / `ArenaCamera` / `MatchResultBanner`. Anything
  that must stop acting once the result exists (card plays, future network
  handlers) gates on `BattleManager.is_match_over()`, never on whether the
  scene has changed yet. Same split as audio: a future server decides the
  result; each client plays its own ending.
- **`Control.pivot_offset` must be set after layout.** Scaling a `Control`
  from its center (the banner's band/title "slam") needs `pivot_offset =
  size / 2`, and `size` is only valid once the container layout has run.
  `MatchResultBanner` sets its pivots inside `show_result()` (the node has
  been in the tree, hidden, since the arena loaded) — never hardcode pixel
  pivots, they break on other aspect ratios (`stretch/aspect = "expand"`).
- **Deleting a resource that a scene still references can make Godot
  embed it into that scene.** When the old `assets/music/music_menu.mp3` was
  deleted while `scenes/music.tscn` still pointed at it, the editor re-saved
  `music.tscn` with the whole MP3 inlined as a `PackedByteArray` sub-resource
  (309 B → 6.3 MB), and with `export_filter = "all_resources"` that ships in
  the APK. Delete the *referencing* scene first (or in the same FileSystem
  selection), then the asset — and check file sizes afterwards.
- **A fourth autoload (`HeroAI`) holds per-match state outside
  `BattleManager.reset_match_state()`.** Same pitfall as `EnergySystem`/
  `HealingSystem`: its own `reset_match_state()` must be called from
  `arena._enter_tree()` alongside the other three, or the low-HP hysteresis
  flag leaks across matches.
- `hero_dummy.tscn`'s `TargetMarker` node existed unused in the scene since
  its creation — `melee_unit.tscn` hides its own copy in the scene file,
  but the hero scene didn't, so it was invisibly always-on until wired up
  in `hero_dummy.gd` (`set_targeted()` + hidden in `_ready()`/`die()`).
  Worth double-checking for other copy-pasted scene subtrees with the same
  silently-active-node issue.
- `BattleManager`'s healing-pod registry needs the same `tree_exited`
  cleanup as the unit registries (`register()`), not the "permanent wreck,
  never freed" pattern turrets/bases use — `single_use` pods (future
  portable pods) actually `queue_free()` themselves, unlike turrets/bases.
- **Status effects are duplicated by design, not by omission.** `apply_stun`/
  `apply_root`/`apply_slow` are near-identical in three files (Sept 2026:
  `player.gd`/`hero_dummy.gd`'s `apply_stun()` now additionally cancels a
  mid-swing attack, see below — so the three are no longer byte-identical,
  but the divergence is a direct, intentional consequence of only heroes
  having a lockable windup at all). Resist the refactor into a shared parent
  or component: the three scripts have genuinely different movement
  pipelines (`unit.gd` steers with separation, `player.gd` blends
  tap-to-move with chase, `hero_dummy.gd` is single-target steering) and
  the *insertion points* differ even though the timers don't. A shared
  class would force those pipelines to converge. `MapDB` follows the same
  discipline: it duplicates `CardDB`'s scan/load pattern verbatim rather
  than extracting a shared base class (see `architecture.md` §2/`data_layer.md`) — two unrelated small
  scanners, not a reason to generalize yet. **`_nav_direction_to()` (`combat_movement.md`
  Navigation) follows the same rule** — three verbatim copies, one per
  movement script, plugged in at each script's own insertion point. Keep the
  three copies in sync by hand if one changes. (Menu chrome is the
  opposite case: the framed screens share one base scene, `menu_ui.md` — they are the
  same thing with different content, not different pipelines. Card data is
  also the opposite case: `UnitData`/`SpellData` *are* one thing — a card —
  so they share the `CardData` base, `data_layer.md`.)
- **A stunned unit's `attack_left` also stops ticking.** The stun early-return
  sits *above* the cooldown decrement in `_physics_process`, so a unit
  stunned mid-cooldown resumes with the same cooldown remaining rather than
  attacking instantly on recovery. Intentional; don't "fix" it by moving the
  decrement above the stun check. **Heroes diverge from this for an
  in-progress swing specifically (Sept 2026):** a locked windup disables
  `_physics_process` entirely (`set_physics_process(false)`), so the
  freeze-and-resume behavior above literally cannot apply to a mid-swing
  stun — the stun timer wouldn't even be evaluated until the swing finished
  on its own. `player.gd`/`hero_dummy.gd`'s `apply_stun()` now calls
  `_cancel_attack_windup()` directly when landing mid-swing, canceling the
  attack outright instead of pausing it. `unit.gd` minions are unaffected
  (no cast-point system to interrupt) and this bullet's original
  freeze-and-resume behavior still fully applies to their plain
  `attack_cooldown` timer, and to a hero's own *cooldown* between swings —
  and (Sept 2026) to `unit.gd`'s new `windup_left` timer too, by the same
  logic: it's just another countdown that lives inside `_physics_process`,
  which already early-returns on `stun_left > 0.0` before reaching it. This
  is the reason `unit.gd`'s windup was deliberately built as a plain timer
  rather than a copy of the hero `await` pattern — it gets correct stun
  behavior for free instead of needing the direct-cancel workaround heroes
  required.
- **`attack_range` as a stat name collides with `attack_range` as an
  Area2D node reference.** `unit.gd` used to have only
  `@onready var attack_range: Area2D = $AttackRange`; adding a data-driven
  `attack_range: float` stat (Sept 2026, mirroring `HeroData`) required
  renaming the node reference to `attack_range_area`, matching the split
  `player.gd`/`hero_dummy.gd` already used (`attack_range: float` stat vs.
  `attack_range_area: Area2D` node). Any future archetype adding a
  `HeroData`/`UnitData`-style data-driven range stat should use this same
  `<stat>` / `<stat>_area` naming split from the start rather than
  colliding with whatever `@onready` name came first.
- **A locked windup disables `_physics_process` outright, so anything meant
  to interrupt it can't wait for the next physics frame.** `_perform_attack()`'s
  `set_physics_process(false)` (unless `can_move_while_attacking`) means the
  entire per-frame update — including any status-timer countdown or state
  check — simply doesn't run until the windup ends or cancels on its own.
  Every interrupt trigger added so far (`on_new_move_command()`,
  `set_primary_target()` targeting a new node, `apply_stun()`, and
  `hero_dummy.gd`'s HP-hysteresis flip via `take_damage()`) is therefore
  hooked directly at the call site that changes the relevant state, calling
  `_cancel_attack_windup()` synchronously — never inferred later inside
  `_physics_process`. Keep this pattern for any future interrupt condition
  (e.g. an AI "higher-priority target spotted" trigger). God skill casts and
  knockback already follow it: both call `_cancel_attack_windup()` at the call
  site (`combat_movement.md`).
- **Anything that must keep counting during a locked windup lives in
  `_process`, not `_physics_process`.** The god skill cooldown ticks there for
  that reason (`combat_movement.md`). Conversely, a forced move (knockback) must run in
  `_physics_process`, so it cancels the windup first to turn physics back on.
- **A unit's melee hit does not re-check range when it lands.**
  `unit.gd::_resolve_attack_hit()` trusts the target locked at windup start.
  Anything that moves a unit mid-swing (knockback today) must cancel the
  pending windup (`windup_left = 0.0`, `_swing_target = null`), or the hit
  lands from wherever the unit was pushed to.
- **New effects that are "the same thing for every caster" go into
  `SkillEffects`, not into the hero scripts.** The hero scripts only own
  per-hero state (cooldown) and the cast entry point. Don't copy an effect
  into `player.gd` and `hero_dummy.gd` — that's the one place the
  status-effect duplication rule does *not* apply.
- **Timed multi-second effects belong on a scene node, not in an autoload.**
  Storm's damage-over-time was originally an `await`-based loop inside
  `BattleManager` holding a target snapshot across several seconds — which
  survived units dying (`is_instance_valid()` per tick) but was *not* safe
  against a match ending or scene change mid-loop. Moving the timing into
  `SpellZone`'s `_process` fixed that for free: the node is a child of the
  arena, so match end, scene change, and `reset_match_state()` all clean it
  up with no guard code. Reach for this pattern before adding another
  `await` chain to an autoload. Note the deliberate consequence —
  **`SpellZone` state is intentionally absent from every
  `reset_match_state()`**, unlike the four autoloads; scene ownership is the
  reset mechanism.
- **Never mutate a shared `SpriteFrames` at runtime.** Stretching a spell's
  cast animation to fit `cast_time` is done with
  `AnimatedSprite2D.speed_scale` on the *node*
  (`speed_scale = frame_count / animation_speed / cast_time`), never with
  `set_animation_speed()` / `set_animation_loop()` on the resource — those
  would leak across every instance using that resource. Same rule as "never
  write runtime state back into a resource" in `architecture.md` §1, one step further: playback
  parameters are node state too. The same goes for scene sub-resources such as
  a `StyleBoxTexture`: `main_menu.gd` `.duplicate()`s the Background stylebox
  before swapping its texture rather than editing the cached one.
- **Animation names are a contract for spells as well as units.** Spell
  `SpriteFrames` must expose `"drag"` and `"cast"`; both playback sites guard
  with `has_animation()`, so a spell with a missing or absent frames resource
  degrades to the plain circle instead of erroring. `"cast"` is authored with
  `loop = 1` and is never visibly seen looping because the node hides it at
  the phase flip — don't "fix" the resource.
- **Control siblings draw in child order — later siblings draw on top —
  regardless of each one's own `visible` state.** A hidden fullscreen overlay
  declared *before* an opaque sibling in the scene tree stays visually buried
  under it even once `visible = true`; the fix is `Control.move_to_front()`
  at open time, not a permanent scene reorder. First hit on `MainMenu.tscn`'s
  `SettingOverlay`/`CreditsOverlay` vs. `Background` (`menu_ui.md`) — worth checking
  first whenever a Control-based overlay "doesn't show" despite `visible`
  being true and no texture/logic bug found.
- **A later sibling that overlaps a button also takes its taps.** A Control
  drawn later gets GUI input first, and a container's own
  `mouse_filter = IGNORE` does not pass that on to its children — a full-rect
  `Panel` inside it still stops the tap. `MainMenu`'s `MainContent` used to
  start at x 130 while `NavRail` reaches x 158: harmless with only the
  showcase, but full-size tab pages would have eaten the right edge of every
  rail button. Keep a page area clear of the rail's rect
  (`offset_left = 166`) rather than juggling `mouse_filter` on every page.
- **Setting `button_pressed` from code emits `toggled`, not `pressed`.** The
  main-menu tabs connect `pressed`, so `_switch_tab()` and the Deck leave
  guard can re-select a button in a `ButtonGroup` without re-entering
  `_request_tab()`. Connecting `toggled` instead would recurse.
- **A `Node2D` child of a `Control` container is not auto-arranged by it.**
  Containers (`HBoxContainer`, `CenterContainer`, …) only lay out `Control`
  children; a `Node2D` (e.g. an `AnimatedSprite2D`) parented under one keeps
  whatever `position` it's given, unaffected by the container's sizing pass.
  Center or position it manually — via the parent Control's `resized` signal,
  not a hardcoded offset, so it stays correct across the different canvas
  shapes `window/stretch/aspect = "expand"` produces per device. First hit on
  `MainMenu.tscn`'s hero showcase (`menu_ui.md`), reused for the framed screens' god
  window.
- **A filled (`Solids` build-mode) `CollisionPolygon2D` is for something you
  can't enter, not for something you can't leave.** `MapBorder`'s first
  version used `Solids`, which treats the whole polygon interior as solid
  mass — the hero spawned inside the border's own footprint and got pushed
  *out* of the playable area instead of contained by it. `build_mode =
  Segments` is the correct mode for any boundary/containment shape (a
  two-sided wall along the outline only, no fill); `Solids` stays correct
  for actual obstacles (rocks, `ObstaclePatch` blobs) where the whole
  footprint should genuinely be impassable from every direction. Don't
  copy `build_mode` between the two use cases — they solve opposite
  problems.
- **`MapBorder.tscn` currently carries two `CollisionPolygon2D` children**
  — `CollisionPolygon2D` (written by `map_border.gd`'s `@tool` parametric
  generator) and `CollisionPolygon2D2` (hand-traced), with only the
  hand-drawn one enabled (`disabled = true` on the generated one) for
  side-by-side testing. This is a deliberate temporary state for
  comparison, not a finished design — **pick one approach and remove the
  other's node before release**; a `StaticBody2D` with two enabled shape
  children unions both, which was never the intent here. The navmesh's
  walkable outline is hand-drawn to match the **hand-traced** border; if the
  border shape changes, redraw the outline and rebake.
- **Navmesh bake source: groups, never "everything on layer 4".** The
  `NavigationPolygon`'s default `Source Geometry Mode = Root Node Children`
  only parses nodes *under* the `NavigationRegion2D` — obstacles living
  elsewhere in the map scene produce a mesh with no holes at all. Using
  plain collision-mask parsing would pull in `MapBorder` too, and a border
  parsed as an obstruction can carve out the entire arena. Use
  `Groups With Children` + the `nav_obstacle` group on the obstacle/structure
  containers only; `MapBorder` stays out of the group, and the walkable
  outline is drawn by hand instead.
- **A TileSet with a Navigation Layer silently adds a second navmesh.** Any
  `TileMapLayer` whose tiles carry navigation polygons registers its own
  navigation regions on the same map, overlapping the baked one and ignoring
  its holes. The Greek tileset has no navigation layer by design; keep it
  that way for every new tileset (or turn off the layer's
  `Navigation → Enabled`).
- **Copying a `NavigationRegion2D` between maps copies the baked polygons
  too.** The `NavigationPolygon` sub-resource stores the bake result
  (`vertices`/`polygons`), not just the settings — duplicating it into another
  map scene gives that map the *other* map's holes until you set the
  `nav_obstacle` groups on the new map and press **Bake NavigationPolygon**
  there. Always rebake per map.
- **Every mover archetype scene must carry `NavAgent`.** `player.gd`,
  `hero_dummy.gd` and `unit.gd` resolve it with `@onready var nav_agent =
  $NavAgent`; a scene sharing one of those scripts without the node crashes
  on spawn. Two unit scenes share `unit.gd` — both need it, and so will any
  future sibling archetype scene.
- **Never set `NavigationAgent2D.target_position` every frame.** Each
  assignment triggers a new path query. `_nav_direction_to()` only re-sends
  it when the goal moved more than 16 px (`NAV_REPATH_DIST_SQ`); a chase of a
  moving target would otherwise repath every physics frame per agent.
- **`has_navigation()` is false on the first physics frame after a map
  loads** (`NavigationServer2D.map_get_iteration_id() == 0` until the server
  syncs). Anything querying the navmesh during spawn must tolerate the
  fallback (direct steering / unsnapped point) rather than assume a path
  exists.
- **The HUD is ready before the match manifest exists.** HUD children run
  `_ready()` before `arena.gd::_ready()` sets the manifests, so HUD UI that
  shows match-derived state gets an explicit `configure()` call from the arena
  afterwards (`minimap.configure_map()`, `synergy_icon.configure()`), instead
  of reading `BattleManager` in its own `_ready()`.
- **`CardDB` routes by type, so folders are free — but its skip list is
  not.** The recursive scan must keep skipping `frames/` (`SpriteFrames` have
  no `id` and would each raise "failed to load resource") and `skills/`
  (`SkillData` has an `id` but is not a card). A new kind of helper resource
  stored under `data/cards|heroes|packs/` needs its folder added to
  `SKIP_DIRS`, or it is rejected as an unknown type.
- **Autoload order matters for `PlayerProfile`.** It validates its save against
  `CardDB` in `_ready()`, so it must come after `CardDB` in `project.godot`.
- **Save files are versioned and migrated, never silently reset.** A known
  older `save_version` is converted in memory and rewritten; only an unreadable
  or unknown-version file falls back to the starter profile. Add a migration
  branch whenever the profile's shape changes.
- **Menu tiles listen to mouse-button events only.** With
  `emulate_touch_from_mouse` on and Godot's mouse-from-touch emulation, handling
  `InputEventScreenTouch` as well makes every tap fire twice (`DeckTile`).
- **A tap inside a scrolling list needs a distance check.** `DeckTile` only
  counts a release within 10 px of the press; otherwise a finger that scrolled
  the pool selects whatever tile it lifts off.
- **`self_modulate` to tint a control without tinting its children.**
  `SynergyIcon` greys the circle and count but leaves its tooltip readable;
  Card Detail's close button darkens itself on press the same way.
- **Hand-written `.tres` / `.tscn` reference new files by `path=` only.** Never
  invent a `uid`; Godot assigns one. When moving resources outside the editor,
  keep every existing `uid` and fix the `path=` strings. A scene that points at
  a file that does not exist yet (e.g. an art asset still being drawn) fails
  to load as a missing dependency — reference only files that are on disk.
- **A path-only reference does not survive an editor move (Oct 2026).** When
  files are dragged in the FileSystem dock, Godot rewrites references that
  carry a `uid`, but a hand-written `[ext_resource]` with only `path=` can be
  left pointing at the old location — four cards broke this way when units
  moved under `cards/greek/units/`. After hand-writing resources, open and
  save them once (or run Project → Tools → Upgrade Project Files) so they
  gain uids **before** any move; after a move, grep for the old folder path.
- **A computed property can give a base class typed views of its subclasses.**
  `CardData.unit_data` / `.spell_data` are `get:`-only properties returning
  `self as UnitData` / `self as SpellData` — a base script naming its own
  subclasses is a cyclic class reference, which Godot 4 resolves. Not
  exported, so never serialized; an old `.tres` that still sets
  `unit_data = …` is a pre-merge file and is rejected by `CardDB`.
- **Texture filtering follows how much the art is scaled on the device.**
  With `stretch_mode = canvas_items` textures render at device resolution
  (S25 FE = 2× the 1170×540 viewport), so a texture's real on-screen scale is
  `node scale × camera zoom × 2` (arena camera zoom = 3). Three cases, three
  settings:

  | Art | Real scale | Setting | Where it's set |
  |---|---|---|---|
  | **Painted UI** (frames, backgrounds, buttons) | ~1–1.3× | **Linear** (`texture_filter = 2`) | once on the **scene root**, children inherit — `MainMenu`'s `Background`, `framed_overlay.tscn`, `card_detail.tscn` |
  | **Minified battlefield sprites** (hero + unit sheets, 250–420 px frames at node scale 0.1–0.15) | ~0.6–0.9× on device, ~0.3× in a desktop window | import **mipmaps** (`mipmaps/generate=true`) + **Linear Mipmap** (`texture_filter = 4`) | on the **`AnimatedSprite2D` only** in `player.tscn`, `hero_dummy.tscn`, `melee_unit.tscn`, `ranged_unit.tscn` — not the root, so health bars and target markers keep their own look |
  | **Enlarged pixel-style art** (map tiles, turrets, bases, projectile) | 3–6× | **Nearest** — the project default (`default_texture_filter = 0`), set nowhere | nothing to do; never change the project default |

  Why: Nearest at an uneven scale (e.g. 1.15×) duplicates rows unevenly and
  stair-steps painted diagonals; Nearest while shrinking makes moving sprites
  shimmer, and Linear alone stops helping past ~2× shrink — mipmaps (pre-shrunk
  copies) cover that; Linear on enlarged pixel art just blurs it.
  Rules for new content: a new UI scene sets Linear on its root; a new
  hero/unit sprite sheet gets mipmaps in its `.import` (the archetype scenes'
  sprite node already has Linear Mipmap); a new archetype scene copies
  `texture_filter = 4` onto its `AnimatedSprite2D`. Author painted UI at
  roughly **2× its logical on-screen size** — never shrink it to the viewport
  size. Costs and caveats: mipmaps add ~33 % texture memory per sheet and
  soften slightly; at small mip levels they blend across frame borders of a
  sprite sheet, so frames need transparent padding (a faint line of a
  neighbouring frame at a sprite's edge = missing padding in the art, not code).
- **Large card art is one file per card, not a sheet.** God covers
  (`HeroData.card_art`) live as individual PNGs in
  `assets/sprites/gods/<pantheon>/<god>/` (`<god>_decal1.png`, alternates
  `<god>_decal2.png` …). The same texture is the god's picture in Card Detail
  and on the small `DeckTile`s (Deck screen, Encyclopedia); the tile draws it
  with Linear Mipmap, so the PNG needs **Mipmaps** on in its Import dock: a sheet would load every god's art to show one,
  quickly exceeds the 4096 px mobile texture limit, and makes every repaint
  shift region coordinates. Sheets/atlases stay for small art drawn many times
  at once (unit sprites, tiles, icons). The unit scroll faces
  (`decals_greek.png` + `AtlasTexture` regions) predate this rule.
- **Inherited scenes: a derived script that overrides `_ready()` must call
  `super()` first.** Godot 4 does not chain `_ready()` automatically;
  `FramedOverlay` (`menu_ui.md`) wires its close button, title and god layout in its own
  `_ready()`, and a derived overlay that forgets `super()` silently loses all
  three.
- **A scene instanced in two places can run under two different
  `process_mode`s.** `SettingOverlay` inherits `WHEN_PAUSED` inside the HUD
  (the tree is paused while it is open) but is overridden to `INHERIT` in
  `MainMenu.tscn` (the tree is not paused). Anything inside it that must
  animate in both places — the god idle sprite — is set to `ALWAYS`
  explicitly; relying on the inherited mode makes it freeze in one of the two.
- **The framed screens' dim is a rectangle with a hole, and that only works
  because the art's god window is a closed hole.** `DimWithHole` draws four
  non-overlapping rects *behind* the frame art around the window's bounding
  box (padded a few px); the rectangle's edges fall under opaque frame pixels,
  so no seam shows. If a frame is repainted with the window opening to the
  outer edge (a gap in the vines), a rectangle is no longer enough — that
  needs a mask texture.
- **9-slice texture margins are in the texture's own pixels.** A
  `StyleBoxTexture` keeps its corners at native texture size, so art drawn
  much smaller than its source (tabs: 61 px art in ~30 px buttons) can let the
  corners eat most of the height. Tune `texture_margin_*` in the Theme editor,
  not in art; crop transparent padding with `region_rect` (the inactive gold
  button) instead of re-exporting.
- **When 9-slice corners must shrink, use `ScaledNinePatch`, not a
  `StyleBoxTexture`.** `scripts/ui/scaled_nine_patch.gd` (`@tool`) scales the
  whole texture first (`patch_scale`, or auto-fit) and only then stretches the
  middle bands, so ornate corners keep their shape on small panels; it can
  also draw a fill under the frame (`fill_color`, `fill_inset`). The Deck
  panels use it (52×46 px corners at 0.7). Trade-off: it lives as a node in
  the scene, not in `dgb_theme.tres` — move to the theme only if Godot's
  stylebox gains corner scaling or a third screen needs the same frame.
- **Column-major order in a `GridContainer` needs index remapping and a
  filler.** `GridContainer` always fills row by row. For a fixed number of
  rows scrolling horizontally (the Deck collection), set `columns =
  ceil(n / rows)`, add children in cell order `(i % rows) * cols + i / rows`,
  and fill an empty last cell with a mouse-ignoring `Control`, or the top row
  shifts.
- **Tab panes that hold long text sit in a `ScrollContainer`.** Card Detail's
  Skills and Details panes each live in their own `ScrollContainer`
  (`horizontal_scroll_mode = 0` so labels wrap, the inner pane
  `size_flags_horizontal = 3`); the tab toggles the **scroll container's**
  visibility, not the pane's — a visible empty scroll container stacked in the
  same `PanelContainer` would swallow the other tab's drag.

### Screen-reading shaders (from CLAUDE.md Key Conventions)

- **`canvas_item` screen-reading shaders (Godot 4.7):** `SCREEN_TEXTURE` is **not** a bare built-in in this Godot version — it was removed. Declare it yourself: `uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;` (see `scenes/arena/ui/shaders/desaturate.gdshader`). Omitting the uniform declaration is a hard compile error, not a silent fallback
- **Screen-reading `canvas_item` shaders: keep them in the same canvas as their content.** `desaturate_overlay.gd`'s `ColorRect` lives directly under `Arena` (layer 0, with `z_index` forcing it to draw last) rather than inside a separate `CanvasLayer` alongside the HUD-style telegraph label, on the theory that `SCREEN_TEXTURE` reads don't reliably cross a `CanvasLayer` boundary. This was fixed at the same time as the missing `hint_screen_texture` uniform declaration above, so the two fixes were never isolated from each other — treat "same canvas as the content" as the safe default for any future screen-reading shader, not as a confirmed, isolated Godot behavior
