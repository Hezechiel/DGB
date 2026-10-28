# Networking posture — DGB architecture

> Part of docs/architecture.md — see the index there.

## Networking posture (design-time only)

No transport exists. The prepared seams:

- Spawn messages will be `{card_id/hero_id, position, team}` — the receiving side
  calls the same `spawn_unit`/`spawn_hero` that local play uses.
- Card database version must match between clients (balance patches → DB version
  check at matchmaking).
- Server-owned state candidates already isolated in BattleManager: match timer,
  death counters, respawn timing, structure status, match result. `EnergySystem`
  is the second such module: a server would run its regen, modifier, and
  `try_spend(card_id)` logic verbatim (spend validation is the first thing a cheat
  client fakes), which is why it carries no scene or UI dependency.
  `HealingSystem` is the third: pod cooldown state and per-team HoT state are
  both pure data with no scene or UI dependency, so a server would run
  `trigger_heal()` / `consume_pod()` / `cancel_heal()` verbatim, same as
  EnergySystem's spend path.
- Authority model (dedicated server vs. relay/P2P) is an open decision with real
  cost implications — treat as its own project phase.
- `HeroAI` is the fourth such module: per-team hp-threshold hysteresis is
  pure data (a bool + two constants), so a server would run
  `get_hp_state()` verbatim. The *decision* of what to do about a LOW_HP
  state (which structure, which pod, which spawn point) stays in the hero
  script/controller layer, not in `HeroAI` — keeping the autoload itself
  trivially portable regardless of how targeting logic evolves.
- Spell casts fit the existing spawn-message shape: `{card_id, position, team}`
  → the receiving side calls the same `cast_spell()` local play uses. Unlike
  `EnergySystem`/`HealingSystem`/`HeroAI`, the spell layer is **not** a
  scene-free pure-state module — `SpellZone` is a scene node and applies
  effects to live nodes directly. `get_targets_in_radius()` is the clean
  seam: a server-authoritative version would run the zone's tick schedule
  and that query, and send resulting damage/status to clients rather than
  letting each client resolve its own. The cast delay is also a genuine
  gameplay window (not just a visual), so it must be server-timed, not
  client-timed, once authority exists.
- **God skills fit the same shape:** `{team, skill_id, target_id}` → the
  receiving side calls the same `SkillEffects.cast()` local play uses
  (`try_cast_skill()` only picks the target; `cast()` takes it as an
  argument, which is that seam). Tuning values are resolved from the shared
  database (`SkillData.values`), never sent. Both implemented skills resolve
  in one frame with no RNG, so they're deterministic given the same target
  and positions. Cooldown would be server-owned once authority exists. Hermes's energy steal touches
  `EnergySystem`, so it is server-authority material like `try_spend()`.
- **Audio is never networked and never authoritative.** Every client plays
  its own sounds from its own local events (hit landed, unit died, hero
  died signal), so nothing about audio enters a message. `AudioManager`
  randomness (variant pick, pitch/volume jitter, ambient timers) uses the
  global `randf()`/`randi()` — if gameplay ever moves to a seeded,
  lockstep RNG, audio must keep using a separate generator so a sound
  choice can't desync the simulation.
- **The end-of-match sequence is client-side presentation.** The winner is
  decided (and `match_ended` emitted) the instant the base falls; the
  camera focus, banner and 3.5 s delay before `MatchEndScreen` are local to
  each client and never networked.
- Map selection will need the same treatment: `MatchConfig.map_id` is
  currently a client-local TEMP random pick (`architecture.md` §2/`data_layer.md`) with no server
  involved — real matchmaking will need to agree on a map id before either
  client instantiates `MapDB.get_map(id).map_scene`, the same way card
  database version needs to match today.
- **Movement commands carry goals, never paths.** A tap-to-move message will
  be `{target_position}` (already navmesh-snapped by the sender or re-snapped
  by the receiver); each simulation computes its own path from the map's
  baked navmesh. That makes the navmesh bake part of the map "version" both
  sides must agree on, the same as the card database. Under a
  server-authoritative model the server runs the agents and clients only
  render positions.
- **The match manifest is the deck message.** Today `MatchConfig` is filled
  locally; with networking, both sides exchange `{hero_id, hero_level,
  card_levels}` once before the match and a server validates it against the
  player's inventory. Spawn messages do not change.
- **`PlayerProfile`'s mutation API is the server boundary** for the meta game:
  `grant_cards()`, `upgrade_card()`, `set_deck()` become requests; `PackRoller`
  and `DeckRules` run server-side unchanged because they take all inputs as
  arguments. The local JSON save is a stand-in and is cheatable by design.
  Card Detail's Upgrade button already goes through `upgrade_card()` only.
- **Synergy is derived, not transmitted.** Both sides compute it from the same
  manifest and the same card database, so it needs no message — but it makes
  `tags`, `domain`, `faction` and the gods' synergy fields part of the database
  version both clients must agree on.
