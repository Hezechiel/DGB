# Card System — Greek Era (Design Spec)
 
> **Divine Gestures: Babylon — Arena Mode**
> Card collecting and faction structure, modeled on Star Wars: Force Arena (SWFA).
> SWFA reference: sides (Light/Dark) → factions (Rebels, Empire...) → shared side cards + faction-unique cards + faction synergy bonuses.
 
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
- **Era rule**: common cards never cross eras. Norse era (Aesir / Vanir / Jotunn) gets its own common pool. Keeps each era's identity strong — SWFA never mixed Rebels with Republic units.
---
 
## 2. Faction synergy rule
 
Units matching the deck leader's faction receive a bonus (SWFA-style leader synergy).
 
> ⚠️ **OPEN QUESTION 1 — faction bonus type** *(researching how SWFA handled this)*
> - Option A: **stat boost** (+10% HP / damage for faction units) — easier to balance
> - Option B: **cost discount** (−1 scroll energy for faction units) — strategically stronger, harder to balance
> - Rule either way: pick ONE, do not stack both.
 
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
 
## 4. Common pool — pan-Greek mythical creatures
 
Creatures belonging to no single god's domain → common by design.
 
| Card | Type | Role | Cost tier | Notes |
|------|------|------|-----------|-------|
| **Satyr** | Melee | Swarm | Very cheap | 2–3 per card, harassers |
| **Centaur** | Melee | Bruiser | Medium | Fast, sturdy midline threat |
| **Harpy** | Melee | Harasser | Medium | Flying visual; crosses impassable terrain (Nike rule) |
| **Cyclops** | Melee | Heavy tank | High | Slow; boulder throw special vs structures |
 
---
 
## 5. Faction-unique units (sketch — separate spec later)
 
Where flavor and the synergy bonus live.
 
| Faction | Unique unit ideas |
|---------|-------------------|
| **Olympus** | Pegasus, Bronze Automaton |
| **Sea** | Hippocampus rider, Nereid (healer variant), Ketos sea serpent |
| **Underworld** | Spartoi (skeleton warriors), Shades (cheap expendables), Erinyes (Furies) |
 
---
 
## 6. Deck composition
 
> ⚠️ **OPEN QUESTION 2 — deck size & sidekick acquisition** *(researching how SWFA spawned/obtained sidekicks)*
> - Working assumption: **hero + sidekick + N cards** (SWFA used hero + 7 cards)
> - To resolve: is the sidekick a permanent escort spawned with the hero, a card in the deck, or unlocked/leveled separately from the hero?
> - Related open questions already listed in `heroes_greek.md`: sidekick death handling, auto-cast vs player-triggered specials.
 
---
 
## 7. Era scaling template
 
Each new era repeats this exact structure:
 
```
Norse era:   common pool (huscarl, berserker, draugr, valkyrie...)
             factions: Aesir / Vanir / Jotunn
Chinese era: common pool + factions (TBD)
```
 
Design work per era = 1 common pool + 2–3 factions + hero/sidekick pairs. No cross-era deck mixing.
 
---
 
## 8. Next steps
 
- [ ] Resolve Open Question 1 (faction bonus type) — SWFA research
- [ ] Resolve Open Question 2 (sidekick spawn/acquisition) — SWFA research
- [ ] Stat pass on common pool (HP / DPS / speed / cost numbers)
- [ ] Faction-unique unit spec (`cards_greek_factions.md`)
- [ ] Card rarity & upgrade/collection progression (separate economy spec)
 
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