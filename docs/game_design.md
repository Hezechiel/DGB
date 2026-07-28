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
against a placeholder opponent (a standing dummy avatar, with no unit spawning)
until the AI and networking phases begin.
 
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
   (Clash Royale draw cycle — deterministic after the initial shuffle).
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
- Enemy avatar: currently a standing dummy near its base; AI controller is a
  planned milestone.
### 3.4 Death & respawn
- Per-team respawn penalty: first death **3 s**, +1 s per subsequent death,
  capped at **10 s**. Counters are fully independent per team and persist for the
  match.
- Dead hero: hidden and disabled (units disengage), countdown shown in the match
  info bar (player = left/blue side, enemy = right/red side), respawn at own base
  with full HP and a brief invulnerability window.
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
- Enemy energy regenerates too, but nothing spends it yet (the enemy side is idle
  until the AI lands) and the opponent's bar is hidden (SWFA/Clash Royale both hide
  opponent resource).
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
### 3.10 Enemy hero AI (movement/targeting, Wave 1)
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
  mistake injection, chasing beyond attack range, card-play decisions.
### 3.11 Spells
- Spell cards are `CardData` with `spell_data` instead of `unit_data` — same
  hand, same draw cycle, same energy gate, same drag-to-play flow as unit
  cards. The single branch is in `card_hand.play_card()`:
  `spawn_unit()` vs. `BattleManager.cast_spell()`.
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
- Three common spells, shared across all eras as one mechanic template with
  per-era art and card IDs (never a shared card ID — the era rule in
  `cards_greek.md` §1 holds):

  | Spell | Effect | CC type | Notes |
  |---|---|---|---|
  | **Storm** | Instant burst damage + damage ticks over the duration, plus a slow | Soft CC (slow) | Targets are snapshotted at cast; not a persistent zone |
  | **Stun** | No damage | Hard CC — no move, no attack | Shortest duration of the three |
  | **Trapping Net** | No damage | Root — cannot move, *can* still attack | Longer than Stun, since the effect is weaker |

- Three distinct CC axes by design (damage-zone / hard-lock / immobilise-but-
  fight), not three strengths of the same axis — Clash Royale's Zap ≠ Freeze
  ≠ Rage model.
- Re-applying an active status takes the **longer** remaining duration; it
  never stacks and never shortens an existing effect (same principle as the
  HoT overwrite rule in §3.9).
- Structures: turrets caught in a Storm radius **do** take damage (they're in
  the team registry) but are immune to stun/root/slow (no such methods).
  Bases are unaffected by spells entirely — they aren't in that registry.
  Pre-existing asymmetry, noted so it isn't mistaken for a bug.
- Numeric values (damage, radius, durations, tick interval, slow multiplier,
  costs) are placeholders pending a balance pass, same status as card costs
  in §3.1.
---
 
## 4. Roadmap (agreed order)
 
1. ~~**Enemy avatar AI**~~ — movement, targeting, and low-HP healing-pod
   seeking are implemented (`HeroAI` autoload + `hero_dummy.gd`). **Card
   plays via the same public entry points a remote player will use are
   still pending** — separate future step, not yet scoped.
2. **Timeout winner scoring** — replace the Draw with progress comparison.
3. **Deploy-zone expansion** — unlock the enemy half per lane when that lane's
   turret falls (§3.7).
4. Then: spell cards, ranged/siege archetypes, and the items below.
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
- Enemy AI card-play decisions (which card, when, where) — separate future
  design pass, not sketched yet.
- CC resistance / diminishing returns: should repeated stuns on the same hero
  within a short window get progressively shorter (tenacity), or is a short
  fixed stun enough? Deliberately not built yet — revisit once chain-CC is
  actually observable in playtesting.
- Spell VFX: `SpellData.vfx_scene` exists but is unwired — no particle or
  animation plays on cast yet.
- Spell zones are cast-time snapshots, not persistent areas. Should Storm
  become a real lingering zone (units entering later get hit), matching the
  §3.9 healing-pod-style area model?
- Should any spell be castable by the AI hero? Spell plays are part of the
  deferred card-play AI, not scoped.
- Do spells need their own deploy-ghost visual (radius preview rather than
  the unit-sized circle)? Currently they reuse the unit ghost.