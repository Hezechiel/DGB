# Divine Gestures: Babylon — Game Design
 
> Living design document. Architecture and technical conventions live in `docs/architecture.md`;
> Claude Code session rules live in `CLAUDE.md`. Update this file when a design decision is made,
> not when code changes.
 
---
 
## 1. Concept
 
A landscape mobile MOBA for Android, built in Godot 4 / GDScript, inspired by
**Star Wars: Force Arena**. The player directly controls a **god avatar (hero)** on a
two-lane battlefield and summons units by **dragging scroll cards** from a hand onto
the map. Victory: destroy the enemy base (Command Post) before it destroys yours,
or hold the better position when the match clock runs out.
 
Designed as **PvP between remote players** from the ground up; current builds run
against a local AI opponent that moves, fights, seeks healing, and plays cards —
all through the same public entry points a remote player will use. It is a
stand-in for the networking phase, not a designed difficulty.
 
---
 
## 2. Core Loop (one match)
 
Pressing **Arena** from the main menu opens a placeholder matchmaking sequence —
a "searching for battle" screen, then a versus screen showing both players'
name/faction — before the match loads. Both screens are cosmetic ~1s
placeholders until real networking exists; rank, map, and opponent identity
are mock data (`MatchConfig`).
 
1. Both heroes spawn at their bases. Match timer starts at **3:00**.
2. Player moves the hero via tap-to-move, targets enemies by tapping them,
   auto-fires at the nearest target in range.
3. Player plays scroll cards from a **3-slot hand** (+ next-card preview) to summon
   units or cast spells; the played card cycles to the back of the deck queue
   (Clash Royale draw cycle — deterministic after the initial shuffle). The AI
   opponent plays from an identical but hidden hand on the same rules (§3.10).
4. Units march toward the nearest living enemy structure, aggro onto enemy units
   they detect, and fight along two horizontal lanes guarded by turrets
   (Top, Bot, plus a Base turret per team).
5. A destroyed lane's turrets expose the enemy base to damage.
6. Hero death is not match-ending: the body hides, a respawn countdown runs in the
   match info bar, and the hero returns at his base.
7. Match ends on base destruction (winner) or timer expiry (currently a Draw;
   progress-based scoring planned).
---
 
## 3. Systems — decided design
 
### 3.1 Cards & hand
- Hand of **3 active slots + 1 dimmed preview** of the next card, in a translucent
  panel at bottom-right (⅓ screen wide, ¼ tall).
- **Draw cycle:** deck is shuffled once at match start; a played card goes to the
  back of the queue; the queue front refills the freed slot. No randomness after
  the shuffle — players can learn and play around the cycle.
- **Playing a card:** drag it out of the hand onto the arena. A translucent circle
  marks the drop point — green where deploying is allowed, red where not; while a
  card is dragged over the map its hand slot shows the scroll's **back**, returning
  to its face if the drag is cancelled (over the hand, a red spot, or off-map). A
  cancelled play does not advance the draw cycle.
- **Squad cards:** a card may summon several units (`unit_count`), placed in a ring
  around the drop point. Squad size belongs to the *card*, not the unit.
- Every card is data (`CardData` resource): id, name, cost, scroll art, linked unit.
  Cards with no unit are **spells** (§3.11) — `CardData` carries either
  `unit_data` or `spell_data`, never both.
- Nine placeholder cards exist (costs 2–6, varying squad sizes); scroll arts and
  assignments are intentionally temporary. A shared scroll-back art shows while a
  card is being dragged.
### 3.2 Units
- Behavior archetypes are scenes (**melee** exists; ranged, siege, special planned);
  individual units are `UnitData` resources feeding an archetype: stats + animations.
- Targeting rules per unit: `ALL`, `UNITS_ONLY` (ignores structures),
  `STRUCTURES_ONLY` (siege/battering-ram style).
- Marching: units head for the **nearest living enemy structure** (no fixed
  waypoints), so they can be deployed anywhere; a wider **AggroRange** makes them
  chase enemies before melee contact. This is a marching-system property, not a
  placement rule — the deploy zone (§3.7) restricts *where* a card can be played;
  once placed, a unit marches the same regardless of where on the map it started.
### 3.3 Heroes
- Hero **identity is data** (`HeroData`: stats, projectile, animations);
  **who controls it** (local input / AI / remote player) is decided at spawn time,
  never sent as data. Both players may pick the same god.
- Local hero: tap-to-move, manual target priority, auto-fire fallback without chase.
- Enemy avatar: AI-controlled (§3.10) — movement, targeting, healing-pod seeking
  and card plays. One fixed baseline, not a tuned difficulty tier.
### 3.4 Death & respawn
- Per-team respawn penalty: first death **3 s**, +1 s per subsequent death,
  capped at **10 s**. Counters are fully independent per team and persist for the
  match.
- Dead hero: hidden and disabled (units disengage), countdown shown in the match
  info bar (player = left/blue side, enemy = right/red side), respawn at own base
  with full HP and a brief invulnerability window.
- **A dead hero is not a target.** Units drop their chase, turrets drop their lock,
  and projectiles already in flight fizzle — nothing camps the corpse or follows
  the hero to its respawn point. The rule matters because a dead hero *stays on the
  map* (hidden, awaiting respawn) rather than disappearing, so "still exists" and
  "still targetable" are two different questions everywhere targets are held.
### 3.5 Match info bar
- Slim top-center bar: match timer in the middle, 3 tower icons per side
  (blue left / red right), circular hero-respawn counters at the outer edges
  (hidden while the hero lives). Tower-destroyed icon states are wired-up visuals
  pending mechanics.
### 3.6 Match end
- Base destruction → winner screen. Timer expiry → **Draw** screen (placeholder).
- Planned: timeout winner decided by progress (towers destroyed, kills, …) —
  explicitly not implemented yet.
### 3.7 Deploy zone
- Cards deploy only on **your own half** (midline `x = 0`) and within the map
  bounds. Anything else is refused; the red circle is the only feedback.
- Planned: the zone **expands into the enemy half once their lane turret falls**
  (Clash Royale model). Not implemented.
- Considered and not chosen: deploy bubbles around your own structures/hero (SWFA
  model), making the hero a mobile deploy anchor. Revisit if the static rule feels flat.
- Invalid/off-map drops currently just cancel; smart clamping to the nearest legal
  spot (around turrets/obstructions) is planned.
### 3.8 Energy
- Both heroes regenerate energy from a shared per-team pool: start **7**, cap
  **10**, **+1 every 4 s** (SWFA-style; slow continuous fill, not discrete pips).
  A modifier layer supports temporary regen boosts and temporary cost reductions
  (e.g. a "bloodlust"-style discount), triggerable by signal/method call for future
  hero abilities.
- Energy gates card plays: a play costs the card's energy, refused if
  unaffordable. Costs resolve through the modifier layer (a bloodlust discount
  lowers them), and the bar shows the real gold-fill art behind the stone frame.
- Unaffordable cards can't be dragged from the hand and are greyed out; they
  un-grey the instant regen makes them affordable. The spend is atomic in
  `play_card()` (`EnergySystem.try_spend()`), so the future double-tap and the
  network handler inherit the same gate without going through the drag UI.
- Enemy energy regenerates on identical rules and is now **spent by the AI**
  (§3.10), through the same atomic `try_spend()` gate as the player — no cheat
  energy, no discounted costs, no ignoring affordability. The opponent's bar stays
  hidden (SWFA/Clash Royale both hide opponent resource), so its economy is read
  off what it deploys, not off a meter.
### 3.9 Healing pods
- Static pods positioned near each base, one per lane per side (4 total on the
  map). Either hero can use either pod — cross-team usable, not locked to the
  pod's own side (SWFA-style neutral pickup).
- Walking onto a ready pod grants an instant heal plus a heal-over-time (HoT).
  The HoT keeps ticking to completion even while the hero is taking damage —
  it only stops if the hero dies.
- The health bar shows a dark green "pending heal" band ahead of the current
  HP fill, so the player can see how much more healing is still incoming.
- After use, a pod goes inactive and becomes available again after a cooldown;
  the map also has an initial delay before pods are first usable.
- Numeric defaults (heal amounts, HoT duration, cooldown, initial delay) are
  placeholders pending a balance pass, same as the card costs in §3.1.
- The AI-controlled enemy hero seeks a ready pod once HP drops below
  **20%**, preferring its own side's pod strictly (only considers the
  opposite side if none of its own are ready), and resumes normal
  behavior once HP climbs back above **50%** (hysteresis band, prevents
  flicker at the threshold). If no pod anywhere is ready, it falls back
  to retreating toward its own spawn point instead.
### 3.10 Enemy hero AI

**Wave 1 — movement & targeting**
- Two-state hysteresis (`NORMAL` / `LOW_HP`) at 20%→50% HP, computed by
  the `HeroAI` autoload; the actual movement/target decision is made by
  the hero script itself.
- `NORMAL`: marches toward the nearest living enemy structure, same
  "nearest structure, no fixed waypoints" rule units already follow.
- `LOW_HP`: seeks the nearest ready healing pod, own side preferred
  strictly; falls back to retreating toward its own spawn if none ready.
- Combat (auto-target + fire within range) runs independently of movement
  state — mirrors the local player hero's own auto-target-without-chase
  fallback, so the bot's baseline aggression matches what an unfocused
  local player already does, not a separately-tuned difficulty.
- Explicitly deferred: difficulty tiers, reaction delay, deliberate
  mistake injection, chasing beyond attack range.

**Wave 2 — card plays**
- The AI side holds **its own hand on the player's exact rules**: same 9-card
  deck, shuffled once at match start, same back-of-the-queue draw cycle, same
  3 active slots, same costs, same atomic energy spend. It is the player's
  mechanic run by a different decider — not a spawn script with its own economy.
- **No hand UI, and none planned** — the opponent's hand is hidden for the same
  reason its energy bar is (§3.8). It also carries no next-card preview slot:
  that is a player-facing affordance, and it affects neither cycle fairness nor
  energy math.
- **Decision tick every ~1.75 s, at most one card per tick.** Policy: play the
  first affordable card in hand that has a valid position. If nothing is
  affordable, the tick simply passes — the AI waits on regen exactly like a
  player would.
- **Placement is deliberately naive.** Unit cards deploy at the AI's own spawn
  point (always inside its legal half); spell cards are aimed at the nearest
  *living* player structure, so the target walks back through the turret line as
  turrets fall. This validates the pipeline; it is not tactics.
- **The AI is blind to the player.** It never reads the player's hand, energy,
  position, or actions, and never reacts to them. Everything it does is a
  function of its own hand and its own energy.
- **No privileged path.** It calls the same `try_spend()` / `spawn_unit()` /
  `cast_spell()` entry points the drag UI uses, so replacing it with a remote
  player swaps the input source and nothing else. This is the reason the card-play
  AI was built before the tactics that would make it interesting.
- Deck parity is maintained **by hand** — the AI's card list and the player's
  deck are two separate declarations with no shared source of truth. Changing the
  player's deck means changing both.
- Explicitly deferred: which card answers what, where to place it, when to hold
  energy for a bigger play, varying the tick rate, and any reaction to the player
  (§6).
### 3.11 Spells
- Spell cards are `CardData` with `spell_data` instead of `unit_data` — same
  hand, same draw cycle, same energy gate, same drag-to-play flow as unit
  cards. The branch is `spawn_unit()` vs. `BattleManager.cast_spell()`, in
  `card_hand.play_card()` for the player and mirrored in the AI's own play
  path (§3.10) — the AI casts spells from the same hand on the same rules.
- **Targeting: anywhere on the map**, both halves, regardless of deploy-zone
  state. The own-half restriction (§3.7) is a *unit* rule; lane-based zone
  expansion never applies to spells. `is_card_target_valid()` branches on
  card type and is the single source of truth for both the drag preview
  colour and the play-on-release check.
- **No friendly fire.** A spell only ever affects the opposing team, never
  the caster's own units or hero, regardless of where it lands. Deliberate:
  the same radius-query helper will back future AoE *units*, and
  position-based (team-agnostic) AoE would make those units miserable to
  balance.
- **One mechanic for all spells: cast delay, then a ticking area zone.**
  Playing a spell spawns a `SpellZone` node at the drop point with two phases:
  - **Cast phase** (`cast_time`): the circle is visible as a *warning* and
    nothing happens. The opposing player has this window to walk out — this
    is the counterplay, and it is why spells have a cast time at all.
  - **Zone phase** (`zone_duration`): every `tick_interval` the zone
    **re-queries** who is currently inside its radius and applies the effect
    to them. Deliberately **not** a snapshot — a unit that walks in later
    gets hit; a unit that walks out stops getting hit.
- `zone_duration = 0.0` means the zone fires exactly **one tick at the moment
  of impact and frees itself**. That is how Stun and Net behave "instantly"
  without a second code path — they are the same mechanic with the shortest
  possible lifetime, not a special case.
- Two distinct duration concepts, deliberately separate fields:
  - `zone_duration` — how long the area lives on the map
  - `effect_duration` — how long stun/root/slow lasts **on a unit that was hit**

  Storm refreshes a *short* slow every tick, so standing in it keeps you
  slowed while leaving lets the slow decay ~1 s later. Collapsing these into
  one field would make leaving the zone meaningless.
- Three common spells, shared across all eras as one mechanic template with
  per-era art and card IDs (never a shared card ID — the era rule in
  `cards_greek.md` §1 holds):

  | Spell | Cast | Zone | Effect | CC type |
  |---|---|---|---|---|
  | **Storm** | Longest (~1.0 s) | Persistent (~3 s), damage ticks | Damage + refreshed short slow | Soft CC (slow) |
  | **Stun** | Shortest (~0.4 s) | Single tick | No damage | Hard CC — no move, no attack |
  | **Trapping Net** | Medium (~0.6 s) | Single tick | No damage | Root — cannot move, *can* still attack |

- Three distinct CC axes by design (damage-zone / hard-lock / immobilise-but-
  fight), not three strengths of the same axis — Clash Royale's Zap ≠ Freeze
  ≠ Rage model.
- **Storm is area-denial, not burst.** The persistent zone is what lets it
  deter an approach on a turret or hold a lane, and what makes Stun → Storm
  a real combo (the stun locks a target in place while the zone keeps
  refreshing the slow, so they are still slowed when the stun breaks).
- **Persistent-zone vs. stick-to-the-target are two different mechanics.**
  Storm is the zone model. Future spells like poison/toxin will be the other
  kind — applied once to whoever is hit, then ticking *on the unit* like a
  bleed, travelling with it. Not designed yet; noted so the zone model isn't
  mistaken for the only option.
- Re-applying an active status takes the **longer** remaining duration; it
  never stacks and never shortens an existing effect (same principle as the
  HoT overwrite rule in §3.9).
- Structures: turrets caught in a Storm zone **do** take damage every tick
  (they're in the team registry) and stun applies to them (turrets carry
  their own `apply_stun`), but root and slow don't (no such methods).
  Bases are unaffected by spells entirely — they aren't in that registry.
  Pre-existing asymmetry, noted so it isn't mistaken for a bug.
- **Drag and cast visuals are real art**; impact and duration are not.
  Each spell carries a `SpriteFrames` with a `"drag"` animation (follows the
  deploy ghost above the circle while dragging) and a `"cast"` animation
  (plays at the drop point, stretched to finish exactly at impact — so a
  0.4 s Stun visibly plays faster than a 1.0 s Storm from the same 8 frames).
  The drag circle also now shows the spell's **real** AoE radius, so what the
  player sees is what gets hit. The zone phase is still the placeholder purple
  circle; impact and duration animations don't exist yet.
- Numeric values (damage, radius, cast time, zone duration, effect duration,
  tick interval, slow multiplier, costs) are placeholders pending a balance
  pass, same status as card costs in §3.1.
---
 
## 4. Roadmap (agreed order)
 
1. ~~**Enemy avatar AI**~~ — movement, targeting, low-HP healing-pod seeking
   (`HeroAI` autoload + `hero_dummy.gd`) **and card plays** (`enemy_card_ai.gd`)
   are implemented, all through the same public entry points a remote player will
   use. **The play policy is deliberately minimal** — first affordable card, fixed
   safe position, one card per tick. Tactical card choice and placement
   (Utility AI) is a separate future step.
2. ~~**Spell cards**~~ — data layer, hand integration, status-effect layer,
   and the cast-delay/area-zone mechanic are implemented (`SpellData` +
   `SpellZone` + `cast_spell()`). **Art is still placeholder circles** and
   AI spell plays are not scoped.
3. ~~**Spell art pass**~~ — drag/cast animations and per-spell ghost radius
   are wired for all three spells. **Impact and duration animations are still
   missing** (assets don't exist); the zone phase remains a placeholder circle.
4. **Per-unit deploy delay** — `UnitData.spawn_time`, deploy indicator at the
   drop point, unit untargetable until it lands.
5. **Timeout winner scoring** — replace the Draw with progress comparison.
6. **Deploy-zone expansion** — unlock the enemy half per lane when that lane's
   turret falls (§3.7).
7. Then: ranged/siege archetypes, and the items below.
---
 
## 5. Future vision (brief, not yet designed)
 
- **Era structure:** world mythologies as content eras — Greek first, then Norse,
  Chinese, … Each era brings a god roster and themed unit pools.
- **Factions (Greek era):** Olympus/Sky, Sea, Underworld — faction-unique units
  beyond a common card pool; faction synergy bonus mechanism undecided
  (stat boost vs. cost discount — research SWFA's approach).
- **Sidekicks:** each playable god paired with a unique companion; spawn/obtain
  mechanics undecided.
- **PvP networking:** authoritative model TBD (server vs. relay); all spawning is
  already ID-based to support it. Death counters, timer, and match state map to
  future server-owned state.
- **Meta:** deck building, collection, per-match deck selection — enabled by the
  card database design, no UI yet.
---
 
## 6. Open questions
 
- Deploy-zone expansion on turret kill: whole enemy half, or only that lane's band?
- Invalid/off-map drops: keep the plain cancel, or clamp to the nearest legal spot?
- Energy: is opponent energy ever shown, and does late-match regen accelerate
  (Clash-Royale-style double time)?
- Bloodlust-style refund ability (pay base cost, RNG-proc partial refund): trigger
  chance and amount undecided.
- Does hero death feed the timeout scoring (kill counting)?
- Faction synergy mechanism (see above).
- Hero abilities beyond the basic projectile (cooldown skills? per-god kits?).
- Sidekick lifecycle: permanent companion vs. summonable card.
- Real matchmaking flow, search-cancel behaviour, and the source of opponent
  name/faction (see pre-match placeholder in §2) are all undecided.
- Monetization model: which combination of paid distribution, IAP, subscription
  (battle pass), and ads — decided in principle as IAP/battle-pass-first,
  no forced/interstitial ads (see `cards_greek.md` §9 for detail). Exact mix
  and pricing tiers undecided.
- Ad-based catch-up mechanic: should non-paying players have an ad-gated path
  to card packs / battle pass progress so they aren't locked out of keeping up
  with subscribers? If yes, which shape (see `cards_greek.md` §9) — undecided.
- Google Play service fee tier and billing route (Play Billing vs. alternative
  billing) — deferred until revenue model is closer to shipping; noted here
  so it isn't forgotten.
- Portable/summonable single-use healing pods (Hephaestus's Forge Turret kit
  in `heroes_greek.md` — "drops a stationary mini-turret" — is the precedent
  for this kind of single-use mechanic) have a stub spawn entry point
  (`BattleManager.spawn_healing_pod`) but no hero ability wired to it yet —
  which hero(s) get this, and when, is undecided.
  - Enemy AI difficulty tuning (reaction delay, mistake injection, chase
  behavior beyond attack range) is deferred — current bot behavior is a
  single fixed baseline, not yet a "practice mode difficulty" concept.
- Enemy AI card-play **tactics** (which card answers what, where to place it,
  whether to bank energy for a bigger play, whether the decision interval should
  vary or react to pressure) — the plumbing now exists and plays the first
  affordable card at a fixed safe spot (§3.10). The decision layer on top of it
  is a separate design pass, not sketched yet.
- Should the AI deploy units anywhere other than its own spawn point — pushing a
  lane, defending a threatened turret, flanking? Currently one fixed spot, which
  makes its units predictable to intercept.
- CC resistance / diminishing returns: should repeated stuns on the same hero
  within a short window get progressively shorter (tenacity), or is a short
  fixed stun enough? Deliberately not built yet — revisit once chain-CC is
  actually observable in playtesting.
- Spell art: impact and duration animations don't exist yet, so the zone
  phase is still a placeholder circle. Each spell currently has its own
  full sheet (`scroll_storm` / `scroll_stun` / `scroll_ensnaring_net`);
  undecided whether later spells keep that or share a generic set.
- Naming drift on the net spell: `display_name = "Trapping Net"`, asset
  `scroll_ensnaring_net`, id `spell_net`. Pick one before more references
  accumulate.
- ~~Should any spell be castable by the AI hero?~~ Yes — the AI plays spell
  cards from the same hand, currently aimed at the player's nearest living
  structure. Still open: whether AI spells should ever target *units or the
  hero* instead of structures, which is part of the deferred targeting pass.
- Stick-to-the-target damage-over-time (poison / toxin / bleed) as a second
  spell mechanic alongside the zone model — shape undecided, not designed.
- Should Storm's zone block or discourage *deployment* inside it, or only
  damage what's already there? Currently purely damage/slow.
- Per-unit deploy delay (`spawn_time`: siege giant slow, slinger squad fast)
  is agreed in principle but not implemented — the unit does not exist and
  cannot be targeted until the delay elapses.