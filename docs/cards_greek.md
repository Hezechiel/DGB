# Card System — Greek Era (Design Spec)
 
> **Duel of Gods: Babylon — Arena Mode**
> Card collecting and faction structure, modeled on Star Wars: Force Arena (SWFA).
> SWFA reference: sides (Light/Dark) → factions (Rebels, Empire...) → shared side cards + faction-unique cards + faction synergy bonuses.
> **Vocabulary changed (Oct 2026):** what this file calls an *era* is now a
> **faction / pantheon**; what it calls a *faction* (Olympus, Sea, Underworld)
> is now a **domain**, shared across pantheons. See `game_design.md` §3.14.
 
---
 
## 1. Structure overview
 
```
ERA (Greek)
 ├── COMMON POOL — cards usable by every Greek faction
 ├── FACTION: Olympus (Sky)      — leader: Zeus
 ├── FACTION: Sea                — leader: Poseidon
 └── FACTION: Underworld         — leader: Hades
```
 
- Mythological basis: the three brothers divided the cosmos **by lot** — sky, sea, underworld. Factions are canon, not invented.
- Later heroes slot into factions: Athena / Apollo / Ares / Artemis / Hermes → **Olympus**; Triton-adjacent → **Sea**; Demeter + Persephone → straddle **Underworld** (seasonal flavor).
- **Pantheon rule (changed Oct 2026):** a deck *may* mix pantheons — a Greek
  god can field Norse scrolls. The cost is synergy: foreign scrolls neither
  count toward the god's threshold nor receive its bonus. Card ids are still
  never reused between pantheons.
---
 
## 2. Faction synergy rule
 
**Resolved (Oct 2026).** Each god has one synergy rule: *if the deck holds at
least N scrolls carrying the god's synergy tag, from the god's own pantheon,
every scroll of that pantheon gets the god's bonus.* Units and spells both
count. One threshold, no tiers. The bonus is always a boost (unit stats, spell
damage or energy regeneration, depending on the god) — never a cost discount.

Zeus: four Olympus scrolls → Greek units +10 % HP and +10 % damage (numbers are
placeholders). Poseidon: four Sea scrolls, same placeholder bonus.

Most spells will carry only their pantheon as a tag; a domain tag (sea,
olympus, underworld, nature) on a spell is the exception.
 
---
 
## 3. Common pool — human soldiery (historically grounded)
 
Real ancient Greek troop types — supports the "historically accurate" pillar.
 
| Card | Type | Role | Cost tier | Notes |
|------|------|------|-----------|-------|
| **Hoplite** | Melee | Tank creep | Cheap | Staple frontline, shield |
| **Toxotes** (archer) | Ranged | DPS | Cheap | Staple backline |
| **Peltast** | Ranged | Skirmisher | Cheap | Fast javelin thrower, fragile — swarm card |
| **Sphendonetes** (slinger) | Ranged | Long-range chip | Very cheap | Rhodian slingers; outranges archers, tiny damage |
| **Hippeus** (cavalry) | Melee | Charger | Medium | Fast; bonus damage on first hit — anti-ranged tool |
| **Phalanx** | Melee | Squad (3 hoplites) | Medium | Formation bonus: +armor while all three alive |
| **Priestess** | Ranged | Healer | Medium | Single-target heal |
| **Gastraphetes crew** | Ranged | Siege | High | Anti-structure only; the "belly-bow," earliest Greek artillery |
 
## 4. Rare pool — pan-Greek mythical creatures
 
Creatures whose myths belong to hero-tales rather than a single god's household
→ available to every faction by design.
 
| Card | Type | Role | Cost tier | Notes |
|------|------|------|-----------|-------|
| **Satyr** | Melee | Swarm | Very cheap | 2–3 per card, harassers |
| **Centaur** | Melee | Bruiser | Medium | Fast, sturdy midline threat |
| **Harpy** | Melee | Harasser | Medium | Flying visual; crosses impassable terrain (Nike rule) |
| **Cyclops** | Melee | Heavy tank | High | Slow; boulder throw special vs structures |
| **Pegasus** | Melee | Flying raider | Medium | Fast; crosses impassable terrain (Nike rule) to reach the backline archers a ground unit would have to walk around. Fragile for the cost — melts to massed ranged, so it raids and leaves |
| **Hippocampus rider** | Melee | Charger | Medium | Damage scales with uninterrupted charge distance — rewards a clean run-up, unlike the Hippeus's flat first-hit bonus. Ground-bound and sturdier than Pegasus |

- Both mounts have divine ties (Poseidon sired both; Pegasus later carried Zeus's
  thunderbolts), so the "no single god's domain" line above is a stretch for them.
  They sit here anyway because their *stories* are Bellerophon's and the sea-road's,
  and because every faction wants access to a fast flanker.
- **Consequence:** rare-pool cards take no faction synergy bonus (§2). A mount in a
  synergy deck will always be slightly behind an equivalent faction-unique card —
  intended, and the reason the uniques in §4a can afford to read as stronger.

## 4a. Faction-unique units

Where flavor and the synergy bonus (§2) actually bite. A unique card played in its
own leader's deck is the intended power peak of a match, so these should read as
strong *and* answerable — never as a card the opponent simply cannot respond to.

| Card | Faction | Type | Role | Cost tier | Notes |
|------|---------|------|------|-----------|-------|
| **Bronze Automaton** | Olympus | Melee | Armored wall | High | Talos, Hephaestus's work. High armor, modest damage — eats *many small hits* and folds to a few big ones, so it counters swarms rather than bruisers. Slow. Unmoved by slow/root (bronze, not flesh). Deliberately an **armor**-type tank against the Cyclops's **HP**-type |
| **Nereid** | Sea | Ranged | Area healer | Medium | Sea-nymph. Heal-over-time on friendly units in a radius — the area counterpart to the Priestess's single-target heal. Follows the existing HoT rule: re-applying takes the longer remaining duration, never stacks (`game_design.md` §3.9). No offense at all |
| **Ketos** | Sea | Melee | Heavy finisher | High | The Sea's top end. Huge HP and damage, very slow — a turret-breaker you have to escort, and a wasted card if it dies mid-map. Unlike the Gastraphetes crew it hits everything, but it has to walk into range to do it |
| **Spartoi** | Underworld | Melee | Squad (3–4) | Medium | Sown dragon's teeth. A *disciplined* squad against the Satyr rabble, but no formation bonus — that stays the Phalanx's identity. Arrives and dies as a group, which makes it Storm's natural prey |
| **Shades** | Underworld | Melee | Expendable chaff | Very cheap | Bodies to soak turret fire. Near-zero HP, near-zero damage, several per card. **Fades after a fixed lifetime** — the cheapest card in the era must not be able to hold a lane indefinitely |
| **Erinyes** | Underworld | Melee | Hero hunter | High | The Furies pursue the guilty: prefers the enemy **hero** over units, ignores structures entirely. Flying (Nike rule). The answer to a hero who never retreats — and close to a dead card against one who plays safe, which is the intended trade |

- **One shape per faction**, so a deck reads at a glance: Olympus = order and armor,
  Sea = sustain and big bodies, Underworld = numbers and attrition.
- **Olympus is currently short.** With Pegasus moved to the rare pool it has a
  single unique unit against Sea's two and Underworld's three. That is a gap to
  fill before the faction spec, not a deliberate asymmetry (§8).
- **Most of these need mechanics that do not exist yet.** `UnitData` today carries
  only `max_hp`, `damage`, `attack_cooldown`, `speed`, and `target_filter` — so unit
  armor, damage reduction, a unit that heals, unit lifetime/despawn, hero-preference
  targeting, flying/terrain-crossing, and charge-distance damage are each a new field
  *plus* archetype work. None of this table is a data-entry job.
- Rarity, per-faction card counts, and whether uniques cost more than the
  equivalent common card are all undecided (§6, §8).

## 4.1 Common pool — spells (cross-era template)

Spells are the one common-pool category that repeats across every era. The
**mechanic** is shared; the **card IDs and art are per-era** (Greek storm =
lightning, Norse = blizzard, Egyptian = sandstorm...), so §1's "common cards
never cross eras" rule holds — no card ID is ever reused between eras.

| Card | Type | Effect | Cost tier | Notes |
|------|------|--------|-----------|-------|
| **Storm** | Spell | Persistent AoE zone: damage ticks + slow while inside | Medium | Only damaging spell; area denial, not burst |
| **Stun** | Spell | AoE hard CC — no move, no attack | Cheap | Shortest cast time; fastest reactive tool |
| **Trapping Net** | Spell | AoE root — cannot move, can still attack | Cheap | Longer effect than Stun; anti-chase / anti-kite |

- Castable **anywhere on the map**, unlike unit cards (own half only).
- **No friendly fire** — opposing team only.
- **Every spell has a cast delay** during which the target circle is visible
  to both players. That warning window is the counterplay: the target can
  walk out. Stun's is the shortest, Storm's the longest.
- **Storm alone leaves a lasting zone**; Stun and Net resolve in a single
  tick at impact. Mechanically they're the same system with different
  lifetimes, not three separate implementations.
- Card face art: Storm uses `scroll_storm.png` (5×2 grid of 260×340 cells —
  cell 0 is the card face, the rest are drag/cast animation frames). Stun and
  Net still use the shared `substitute.png` sheet (16×6 grid of 109×109
  cells) as placeholders.
- In-arena visuals are still a placeholder circle (orange while casting,
  purple while the zone is live); impact and duration animations don't exist
  yet for any spell.
- Numbers are placeholders pending the same stat pass as the rest of the
  common pool.
---
 
## 5. Faction-unique units — status
 
The name-only sketch that used to live here is now the full table in **§4a**
(roles, cost tiers, and the mechanics each unit would need). What is still open is
the *spec*, not the roster:
 
- Numbers (HP / DPS / speed / cost), pending the same stat pass as the rest of the
  pools (§8).
- Per-faction card counts — **Olympus currently has one unique unit** against Sea's
  two and Underworld's three, after Pegasus moved to the rare pool.
- **Pegasus** and **Hippocampus rider** are no longer faction-locked: they live in
  the rare pool (§4) and therefore carry no synergy bonus.
- Whether faction-unique cards are also a *rarity* tier, or just a deck-eligibility
  restriction, is undecided.
 
---
 
## 6. Deck composition
 
**Deck size resolved (Oct 2026): 1 god + 7 scrolls**, units and spells mixed,
no duplicates, one deck per god.

> ⚠️ **OPEN QUESTION 2 — sidekick acquisition** *(still open)*
> - Is the sidekick a permanent escort spawned with the hero, a card in the
>   deck, or unlocked/leveled separately from the hero?
> - Related open questions already listed in `heroes_greek.md`: sidekick death
>   handling, auto-cast vs player-triggered specials.
 
---
 
## 7. Era scaling template
 
Each new era repeats this exact structure:
 
```
Norse era:   common pool (huscarl, berserker, draugr, valkyrie...)
             factions: Aesir / Vanir / Jotunn
Chinese era: common pool + factions (TBD)
```
 
Design work per pantheon = 1 common pool + 2–3 domains + god/sidekick pairs,
plus the tags its gods refuse and each god's synergy rule. Decks may mix
pantheons at the cost of synergy.
 
---
 
## 8. Next steps
 
- [x] Open Question 1 (synergy type) — resolved, §2
- [ ] Open Question 2 — deck size resolved (god + 7); sidekick still open
- [x] First stat pass on all 20 Greek units (values in
      `scrolls_decisions.md`); cards exist for the eight human units.
      Balance pass still to do.
- [x] Card rarity, leveling and collection — built (`game_design.md` §3.14);
      per-card rarities are still placeholders
- [x] Spells take normal deck slots
- [ ] Domain cards: Pegasus, Bronze Automaton (Olympus); Hippocampus Rider,
      Nereid, Ketos (Sea); Shades, Spartoi, Erinyes (Underworld) — unit data
      exists with placeholder sprites, no cards yet
- [ ] Tag vocabulary (holy, undead, beast…) and which gods refuse what
- [ ] Synergy rule for every god beyond Zeus and Poseidon
- [ ] Mechanics the unit data cannot express yet: healing (Priestess, Nereid),
      charge bonus (Hippeus), formation armor (Phalanx), flying (Harpy,
      Pegasus), Cyclops boulder throw
- [ ] Give Olympus at least one more unique unit — one against Sea's two and
      Underworld's three (§4a, §5)
- [ ] Decide which §4a mechanics are worth building: unit armor / damage
      reduction, a unit that heals, unit lifetime & despawn, hero-preference
      targeting, flying / terrain-crossing, charge-distance damage. Each is a new
      `UnitData` field plus archetype work — cost them before committing the cards
- [ ] Faction-unique unit spec (`cards_greek_factions.md`)
- [ ] Per-era spell art (Norse/Egyptian/Chinese reskins of Storm/Stun/Net)
- [ ] Are there faction-unique spells, or do spells stay strictly common?
 
 ### 9.1 Kozmetické odmeny — vhodné plochy (64×64 chibi sprite obmedzenie)

Sprite rozlíšenie (64×64) robí priamu vizuálnu kozmetiku na jednotkách (skin
varianty, farebné palety) ťažko čitateľnú a teda ťažko predajnú — hráč ju ani
poriadne nevidí v behu zápasu. Vhodnejšie plochy pre kozmetické battle-pass
odmeny, ktoré využívajú existujúci art pipeline (SVG master → PNG):

- **Scroll-back art** — už existuje spoločný "scroll-back" počas ťahania karty
  (`architecture.md` §4); väčšia a viditeľnejšia plocha než sprite skin.
- **Víťazné pózy** — statický, veľký zobrazovaný prvok na konci zápasu.
- **Profilové rámiky / odznaky** — zobrazené staticky v UI (profil, pred
  zápasom), nie v behu hry, takže rozlíšenie nie je limitujúce.
- **Efekty ultimate útoku** (farba, trail) — viditeľné v zápase, ale
  nezávisia od základnej sprite veľkosti jednotky.

Toto nahrádza pôvodnú predstavu "skin variant na sprite" ako primárnu
kozmetickú odmenu v battle passe.