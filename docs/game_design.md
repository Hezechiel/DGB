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
against a placeholder opponent (dummy avatar + timed wave spawner) until networking
and AI phases begin.

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
- Every card is data (`CardData` resource): id, name, cost, scroll art, linked unit.
  Cards with no unit will become **spells** (later phase).
- Six placeholder scroll arts exist on one spritesheet; meanings/assignments are
  intentionally temporary.

### 3.2 Units
- Behavior archetypes are scenes (**melee** exists; ranged, siege, special planned);
  individual units are `UnitData` resources feeding an archetype: stats + animations.
- Targeting rules per unit: `ALL`, `UNITS_ONLY` (ignores structures),
  `STRUCTURES_ONLY` (siege/battering-ram style).
- Marching: units head for the **nearest living enemy structure** (no fixed
  waypoints), so they can be deployed anywhere; a wider **AggroRange** makes them
  chase enemies before melee contact.

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

---

## 4. Roadmap (agreed order)

1. **Drag-to-deploy** — drag a card from the hand onto the arena to call
   `play_card()` + `BattleManager.spawn_unit()` at the drop position; deploy-zone
   rules TBD (own half? behind front line?).
2. **Energy/mana cost system** — resource bar gating card plays; `CardData.cost`
   already exists and is unused by design.
3. **Enemy avatar AI** — replace the standing dummy with a controller (movement,
   targeting, card plays via the same public entry points a remote player will use).
4. **Timeout winner scoring** — replace the Draw with progress comparison.
5. Then: spell cards, ranged/siege archetypes, and the items below.

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

- Deploy-zone rules for drag-to-deploy (whole map vs. own territory).
- Energy system shape: regen rate, max pool, card costs, elixir-style vs. SWFA-style.
- Does hero death feed the timeout scoring (kill counting)?
- Faction synergy mechanism (see above).
- Hero abilities beyond the basic projectile (cooldown skills? per-god kits?).
- Sidekick lifecycle: permanent companion vs. summonable card.
- Real matchmaking flow, search-cancel behaviour, and the source of opponent
  name/faction (see pre-match placeholder in §2) are all undecided.
