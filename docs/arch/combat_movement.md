# Combat & movement model — DGB architecture

> Part of docs/architecture.md — see the index there.

## Combat & movement model

- `team` is a String (`"player"`/`"enemy"`); groups `team_player`/`team_enemy`.
- **Collision layers are computed at runtime** in `_ready()` from team
  (hurtbox layer constants in `unit.gd`); never baked per-team into scenes.
- Unit state machine: `MARCHING → CHASING (AggroRange) → ENGAGING (AttackRange)`.
  March target = `BattleManager.get_nearest_structure()`, refreshed on an interval,
  not per frame. Separation steering with cached interval updates. Units only
  collide with layer 4 (`collision_mask = 4`: structures/obstacles/border) —
  not with each other or with heroes; separation is the only thing spacing a
  squad apart.
- **Navigation (Sept 2026) — every mover follows a baked navmesh; the
  navmesh only picks the direction, never the velocity.**
  - *Map side.* Each map scene carries one `NavigationRegion2D`. Its
    `NavigationPolygon`'s walkable **outline** is hand-drawn to match the
    `MapBorder` shape; the **holes** are baked from source geometry:
    `Parsed Geometry Type = Static Colliders`, `Parsed Collision Mask = 4`,
    `Source Geometry Mode = Groups With Children`, group `nav_obstacle`
    (on `Patches`, `PlayerStructures`, `EnemyStructures`). `MapBorder` is
    intentionally outside the group (`conventions_pitfalls.md`). Agent radius is the default 10 px
    (hero body circle is 7 px; unit 16×16 box reaches ~11 px at the corners —
    accepted, they just slide past corners). Baked **at edit time, static**:
    nothing on the map changes topology mid-match (structure wrecks never
    `queue_free()`), so there's no runtime rebaking.
  - *Mover side.* `player.tscn`, `hero_dummy.tscn`, `melee_unit.tscn` and
    `ranged_unit.tscn` each carry a `NavAgent` (`NavigationAgent2D`) child —
    `path_desired_distance = 4`, `target_desired_distance = 8`, avoidance
    **off**. Each of the three scripts has its **own verbatim copy** of
    `_nav_direction_to(goal) -> Vector2` (same deliberate duplication as the
    status effects, `conventions_pitfalls.md`). It returns only a unit direction; each script's
    existing pipeline (windup lock, root, slow, `velocity`, `move_and_slide()`,
    animation) is unchanged. `NavigationAgent2D.velocity` / `velocity_computed`
    are not used anywhere.
  - *Where it plugs in.* `player.gd`: `get_move_input()` (tap-to-move) and
    the `primary_target` chase branch. `hero_dummy.gd`: inside
    `_steer_towards()`, so march, pod-seek and retreat all path. `unit.gd`:
    inside `_steer_towards()`, where the navmesh direction replaces only the
    **seek** term — separation is still added on top, unchanged.
  - *Repath rule.* The agent's `target_position` is only re-sent when the
    goal moved more than 16 px (`NAV_REPATH_DIST_SQ`) since the last one
    (`_nav_goal`), so chasing a moving target doesn't recompute the path
    every frame. `_nav_goal = Vector2.INF` forces a fresh path — reset on
    tap-to-move arrival and `on_new_move_command()` (player), and in
    `die()`/`revive()` (both heroes). Units never revive, so they don't reset.
  - *Goals inside a hole.* A structure sits inside a navmesh hole, so the path
    ends at the hole's edge; when `is_navigation_finished()` is true the helper
    falls back to direct steering for the last few pixels and the existing
    `AttackRange` overlap check takes over. No snapping of structure/pod goals.
  - *Queries.* `BattleManager.has_navigation()` is false when the current map
    has no `NavigationRegion2D` **and** on the first physics frame after load
    (`map_get_iteration_id() == 0`, server not synced yet) — every
    `_nav_direction_to()` then falls back to straight-line steering, i.e. the
    pre-navmesh behavior. `BattleManager.snap_to_navigation(pos)` returns the
    closest navmesh point (unchanged without a navmesh); used for the
    tap-to-move target (`arena.gd`) and the AI hero's retreat point (a spawn
    point inside the 10 px agent-radius margin would otherwise never satisfy
    the 8 px arrival check).
  - *Not built yet.* Deploy validation doesn't consult the navmesh —
    `is_deploy_position_valid()` still only checks bounds, own half and
    protection zones, so a unit card can be dropped inside a patch (next
    step: reject positions off the navmesh). No RVO avoidance — deliberately
    off; if squads clump at chokepoints the first lever is separation
    tuning, RVO is a separate decision (it changes how velocity is owned).
- **Minions get a two-phase attack windup too (Sept 2026), but a
  deliberately simpler one than heroes'.** `UnitData.attack_type`
  (MELEE/RANGED) and a data-driven `attack_range` (replacing what used to
  be a scene-baked `AttackRange` radius) drive `_process_engaging()`:
  on entering range, the unit winds up for `damage_point_ratio` (same
  0.0-1.0 semantics and 0.7 default as `HeroData`) of the live-derived
  `"attack"` animation duration, then resolves — direct `take_damage()` for
  MELEE, or spawns the same `projectile.tscn` heroes already fire for
  RANGED — and `attack_cooldown` (unchanged field, now playing the role
  `HeroData.recovery_time` plays for heroes) starts counting from that
  point. Unlike heroes, this is implemented as a **plain countdown
  (`windup_left`) inside the existing synchronous `_physics_process` state
  machine, not an `await` coroutine** — `unit.gd` had no async patterns
  before this and shouldn't gain one just for a windup timer. The payoff:
  since nothing disables `_physics_process` during a minion's windup (unlike
  heroes' `set_physics_process(false)`), the pre-existing stun
  freeze-and-resume behavior (see `conventions_pitfalls.md`) already covers a stun landing
  mid-swing correctly, with no direct-cancel hook needed. Minions also get
  **no** cancel-on-new-command mechanic — they have no player-issued
  commands to cancel on, and no AI retreat state either; a target leaving
  `attack_range` mid-windup is left to the existing march-state fallthrough
  (`ENGAGING → CHASING` silently abandons the pending windup, no hit, no
  explicit cancel-animation) rather than a built interrupt system. Full
  detail in `unit_authoring_guide.md` §2.2.
- **Hero attacks are an interruptible two-phase cast-point (Sept 2026).**
  Targeting priority is unchanged: manual primary target (tap) with chase,
  auto-target fallback without chase. The swing itself now splits at
  `HeroData.damage_point_ratio` (0.0-1.0, default `0.7`) of the live-derived
  cast-point (`attack_left`'s `frame_count/speed`, same derivation as
  always). Before that fraction elapses the hero hasn't committed — a
  genuinely new command (a new tap-to-move, or an explicit tap on a
  *different* target) cancels the swing for free: no damage, `fire_left`
  reset to 0, animation snapped to idle, movement unlocked immediately.
  Re-issuing the same target mid-swing is a no-op, not a cancel. At/after
  the damage point the hit lands right then and movement unlocks
  immediately either way, with `recovery_time` now counting from the
  damage point rather than the old full-animation end. This replaced a
  single monolithic movement-lock for the whole `attack_left` duration
  with no way to interrupt it — the cause of a "hero feels rooted mid-fight"
  bug (tap-move, arrive, auto-fire on a newly-arrived enemy, then be stuck
  for the full swing before the next tap-move could even register). Full
  mechanic and per-hero tuning guidance live in `hero_authoring_guide.md`
  §2.2 — this doc covers the *why*, that one covers the *how to tune it
  per hero*.
- **AI retreat interrupts an in-progress swing.** `hero_dummy.gd`'s
  `HeroAI` NORMAL⇄LOW_HP hysteresis flip cancels a mid-swing attack via
  the same cancel path player commands use, hooked into `take_damage()`
  rather than `_physics_process` (see `conventions_pitfalls.md` for why). Meant to be the first
  of several future AI "interrupt and reconsider" triggers (e.g. spotting
  a higher-priority target) — only the HP-retreat one exists today.
- **God skills (Oct 2026) — cooldown on the hero, effect in one shared place.**
  - *Split.* Cooldown state and the cast entry point are **duplicated** in
    `player.gd` and `hero_dummy.gd` (thin: `skill`, `skill_cd_left`,
    `get_skill_cooldown_left()`, `can_cast_skill()`, `try_cast_skill()`,
    `_reset_skill_cooldown()`), same deliberate duplication as the status
    effects. The **effects** are written once, in `SkillEffects`
    (`scripts/arena/skills/skill_effects.gd`, static functions only, no
    stored state except a warn-once set): `is_implemented(skill)`,
    `cast(skill, caster, caster_team, target, attack_power) -> bool`, plus the
    shared target helpers `is_alive()`, `find_nearest_target()`,
    `pick_cast_target()`, `skill_damage()`, `enemy_team_of()`. `cast()`
    dispatches on `skill.id` with `if/elif`; an unknown id warns once and
    returns `false`. Tuning is read only through `skill.get_value()`.
  - *Cooldown.* Starts full at spawn (`configure()`) and again on every
    `revive()`. Ticks in `_process`, **not** `_physics_process` (a locked
    attack windup and the spawn animation disable physics, and the cooldown
    must not pause for them); doesn't tick while dead; keeps ticking while
    stunned; pauses with the game.
  - *Cast rules.* `can_cast_skill()` is false when the skill is missing or not
    implemented, on cooldown, the god is dead or stunned, the match is over,
    or there is no target. Target = the player's `primary_target` if it's a
    registered, alive enemy within `cast_range`, otherwise the nearest alive
    enemy within `cast_range` (center-to-center, candidates from
    `get_targets_in_radius()`, so bases are never targets). The AI uses the
    nearest rule only. A cast is **instant** (no skill windup or animation
    yet): it cancels a pending auto-attack windup, faces the target, calls
    `SkillEffects.cast()`, and starts the cooldown only if that returned
    `true` — a refused cast costs nothing.
  - *AI.* `hero_dummy.gd` casts whenever `can_cast_skill()` is true, in both
    NORMAL and LOW_HP states (first pass, no cluster scoring).
  - *Attack Power* = the caster node's level-scaled `projectile_damage`;
    damage = `maxi(1, roundi(AP × pct / 100))`.
  - *Implemented:* **Zeus — Chain Lightning**: hit the target, then up to
    `jumps` more (1 + 5 = 6 targets) to the nearest not-yet-hit alive enemy
    within `jump_range` of the last hit; damage falls off multiplicatively per
    jump (220 → 176 → 141 %…); every hit is stunned 0.4 s and a turret also
    gets `interrupt_shot()` (`fire_left = fire_cooldown`, called only by this
    skill — the Stun spell is unchanged). **Poseidon — Tidal Wave**: a cone of
    `cone_angle` / `wave_range` aimed at the target; every enemy inside takes
    flat damage, then a slow (`1 - slow_pct/100` for `slow_duration`) and a
    knockback of `knockback` px radially away from Poseidon over
    `knockback_time` (code default 0.2 s). Turrets take damage only. Both
    resolve in one frame, deterministically. The other ten gods' skills are
    not implemented (no button, the AI never casts).
  - *Adding a skill* = one `if/elif` branch + one `_<skill>()` function in
    `SkillEffects` and its id in `is_implemented()`; new mechanics it needs
    (shield, charm, summon…) go where their kind already lives (a status
    effect → the three mover scripts).
- **Knockback (Oct 2026)** is the fourth status effect, next to stun/root/slow
  in `unit.gd`, `player.gd`, `hero_dummy.gd`: `knockback_left`,
  `knockback_velocity`, `apply_knockback(direction, distance, duration)`. A new
  knockback replaces a running one. In `_physics_process` its branch sits
  **above** the stun early-return: it moves the mover with `move_and_slide()`
  (so obstacles, structures and the border stop it, `collision_mask = 4`),
  ignores root and slow, and also moves a stunned target. `apply_knockback()`
  resets `_nav_goal` (stale path) and cancels the swing in progress — heroes
  through `_cancel_attack_windup()` (a locked windup disables
  `_physics_process`, so the push would never run otherwise), units by
  clearing `windup_left` / `_swing_target` (their melee hit doesn't re-check
  range on landing, so a pushed unit would still hit from 60 px away).
  `revive()` clears any leftover knockback. Turrets and bases have no
  `apply_knockback()` and are never moved.
- Hero death: hide + disable (collision & hurtbox zeroed deferred → attackers get
  `area_exited` and disengage), unregister, respawn via BattleManager countdown.
- Range checks use `distance_squared_to()`.
- **Deploy zone:** `BattleManager.is_deploy_position_valid(pos, team)` is the single
  source of truth — the live drag preview (circle colour) and the spawn on release
  both call it, so they cannot disagree. Today: inside `DEPLOY_BOUNDS` and on the
  team's own half (midline `x = 0`). It is **positional only** (takes no `card_id`);
  energy affordability is a *separate* check and is deliberately NOT folded in here,
  so the red circle never conflates "bad spot" with "can't afford". Future zone
  rules (expansion on turret kill, obstacles / off-navmesh rejection) go inside
  this function.
  - **Spell targeting:** `BattleManager.is_card_target_valid(card, pos, team)`
  is the single source of truth for *both* card types and wraps (never
  modifies) `is_deploy_position_valid()`. Spells: inside `DEPLOY_BOUNDS`
  only, either half. Units: the existing own-half rule, untouched.
- **AoE queries:** `BattleManager.get_targets_in_radius(pos, radius, affected_team)`
  is the shared radius query — **team-scoped by parameter, never
  position-only**. `SpellZone` passes the caster's *opposing* team, so
  spells can't friendly-fire. Public (no leading underscore) because it is
  called from outside the autoload; future AoE unit attacks should call this
  same helper rather than rolling their own overlap scan.
- **Spell effects are a re-query per tick, never a snapshot.** `SpellZone`
  calls `get_targets_in_radius()` fresh on every tick, so a unit that walks
  into an active Storm gets hit and one that walks out stops being hit.
  Holding a target array across time was the *old* model and was deliberately
  removed — if a future spell needs stick-to-the-target behaviour
  (poison/bleed), that belongs as per-unit state on the victim, like the
  status timers, not as an array held by the caster.
- **`cast_spell()` applies nothing.** It validates the card and spawns a
  `SpellZone`; all timing and all effect application live on that node. This
  keeps every spell's lifetime bound to the arena scene tree.
- **Status effects** live as plain per-instance state (`stun_left`,
  `root_left`, `slow_left`, `slow_multiplier` + `apply_stun()` /
  `apply_root()` / `apply_slow()`) duplicated **independently** in
  `unit.gd`, `player.gd`, and `hero_dummy.gd` — no shared base class, same
  principle as the HealingSystem signal hooks. Stun short-circuits at the
  top of `_physics_process` (movement *and* attack cooldown both freeze);
  root zeroes movement only, inside the steering function; slow multiplies
  the velocity magnitude. None of the three interacts with navigation: the
  agent's path simply waits while the mover is stunned/rooted and resumes
  afterwards. **Sept 2026: `player.gd`/`hero_dummy.gd`'s
  `apply_stun()` additionally cancels a mid-swing attack outright (see the
  bullet above and `conventions_pitfalls.md`) — this is no longer byte-identical to `unit.gd`'s
  version. `unit.gd` gained its own windup (`windup_left`, see above) but
  deliberately did NOT gain an equivalent cancel call: its windup is a
  plain `_physics_process` timer rather than an `await` coroutine, so the
  existing freeze-and-resume stun behavior already pauses it correctly —
  adding a direct cancel there would be solving a problem `unit.gd` doesn't
  have.**

---

## Moved from CLAUDE.md (Oct 2026)

Facts from the old CLAUDE.md catalogue that the sections above did not
already cover.

### Player hero (from CLAUDE.md)

`scenes/arena/player.tscn` / `scripts/arena/player.gd`
- `CharacterBody2D`, tap-to-move via `InputR` — no camera child; the camera is a standalone node (`ArenaCamera`, see `battle_scene.md`)
- Attacks use a cast-point system (`_perform_attack()`): plays `attack_left`, locks movement for the animation's own duration (`frame_count / speed`, read live) unless `can_move_while_attacking`, then applies the hit — `fire_bolt()` for `AttackType.RANGED`, direct `take_damage()` for `AttackType.MELEE` (re-checks range/liveness on landing)
- `take_damage(amount)` with invulnerability window (`invuln_time`), sprite flash feedback
- Stats come from `HeroData` via `configure(data, team, stat_mods := {})` — `stat_mods` are `BattleManager._hero_stat_mods()` multipliers (`max_hp`/`damage`/`attack_speed` from the god's level; synergy never buffs the god): `max_hp`, `speed`, `attack_range`, `recovery_time` (post-cast-point cooldown remainder — cast-point itself is derived live from the `attack_left` animation, so retuning its fps/frame count never requires touching cooldown data), `projectile_damage`, `attack_type`, `can_move_while_attacking`, `attack_sound`
- Spawn/death animations (`spawn_left`, `death_left`) freeze movement for their duration
- Mirrored by `scripts/arena/hero_dummy.gd` (`scenes/arena/hero_dummy.tscn`) for AI-controlled enemy heroes — same cast-point/attack logic, own march/retreat/heal-seek movement; the "am I in trouble" decision is delegated to `HeroAI` (`architecture.md` §2)

### Auto-attack priority (from CLAUDE.md)

Player's `_physics_process` attack logic, in priority order:
1. If `primary_target` is set and valid (explicit tap-on-enemy) → attack it if in range; if out of range, chase it (overrides tap-to-move)
2. Else, `find_nearest_enemy()` picks the nearest valid enemy hurtbox currently in attack range (unit, hero, or structure — no separate priority tier between them) and fires **only** if the player has no active tap-to-move command that frame — auto-attack never interrupts movement, and never chases on its own

`primary_target` is set by `set_primary_target()` (tapping an enemy directly) and cleared when the target dies or `_clear_primary_target()`/`_on_primary_target_removed()` fires.

### Combat unit (from CLAUDE.md)

`scenes/arena/units/melee_unit.tscn`, `scenes/arena/units/ranged_unit.tscn` / `scripts/arena/unit.gd`
- `team` export drives which hurtbox/attack-range/aggro-range physics layers and groups it joins at `_ready()`, since the scenes carry no team-specific static layer values
- Configured entirely from `UnitData` via `configure(data, team, stat_mods := {})` — `stat_mods` (`max_hp`/`damage`/`speed`/`attack_speed` multipliers, level × synergy) come from `BattleManager._unit_stat_mods()`; fields: `max_hp`, `damage`, `attack_cooldown`, `speed`, `attack_type` (MELEE/RANGED), `attack_range`, `projectile_scene`, `damage_point_ratio`, `target_filter` (`ALL` / `UNITS_ONLY` / `STRUCTURES_ONLY` — e.g. a battering-ram unit ignores units and only closes on turrets/bases)
- `MarchState`: `MARCHING` (seeks `structure_target`), `CHASING` (spotted an enemy unit in the wider `AggroRange`, pursues indefinitely — no leash yet), `ENGAGING` (enemy hurtbox in `AttackRange`)
- Seek + separation steering (`compute_separation()`) shared between marching and chasing
- Status effects: re-applying takes the longer of current/new duration (never shortens an active effect)
- Spawn invulnerability window on every deploy (`invuln_time`, not just first spawn — units get no "safe first spawn" the way heroes do since every deployment can land mid-fight)
- `take_damage(amount)` → cosmetic death (`die()`): disables collision/hurtbox immediately, plays "death" animation if present, then `queue_free()`
- Tap-to-target only for enemy-side units (`_on_hurtbox_input_event` sets the player's `primary_target`)

### Turrets (from CLAUDE.md)

`scenes/arena/turrets/PlayerTurret.tscn`, `scenes/arena/turrets/EnemyTurret.tscn` / `scripts/arena/turret.gd`
- `StaticBody2D`, shared script, `owner_team` and `target_group` exports
- Full MOBA variables: `armor`, `stun_timer`, `restore_hp_per_sec`, `regen_buffer`
- 4-stage damage visuals via `AnimatedSprite2D` frame control (no `queue_free()` — turrets become wrecks)
- `_on_destroyed()` disables CollisionShape2D and DetectionRange deferred
- Owns an exported `protection_zone: Rect2` (see `data_layer.md` and "Spawn protection zones" in `battle_scene.md`)

### Projectile (from CLAUDE.md)

`scenes/arena/projectiles/LightningBolt.tscn` / `scripts/arena/projectiles/lightning_bolt.gd`
- `Area2D`, 8-directional animated sprite
- `setup(start_pos, dir)` called deferred after `add_child`
- `_try_damage(target)`: checks `is_in_group(hit_group)` and `has_method("take_damage")`
- `hit_group` set by shooter (`"team_enemy"` or `"team_player"`)
