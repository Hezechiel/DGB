# Heroes — Greek Era (Wave 1 Design Spec)

> **Divine Gestures: Babylon — Arena Mode**
> Hero + sidekick pairs for the Greek mythology era.
> Format per SWFA model: each playable god has one unique sidekick unit.
>
> **Legend**
> - **Type**: Melee / Ranged
> - **Role**: Tank / DPS / Burst DPS / Bruiser / Healer / Support
> - Flying is visual-only (no gameplay mechanic), with the single exception of Nike's terrain-crossing swipe.

---

## Design rules

1. Every pair contains at least one melee OR one ranged unit — no pair is fully kite-proof or fully helpless in melee.
2. Sidekicks define hero identity mechanically, not just visually.
3. Mythological accuracy first: every sidekick has a canonical source.
4. One special ability per unit. Keep specials simple — this is a fast-paced mobile MOBA.

---

## Roster

### Zeus + Nike
*Mythology: Nike attends Zeus; he holds her in his palm in the Statue of Zeus at Olympia.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Zeus** | Ranged | Burst DPS | **Chain Lightning** — bolt jumps to 2 nearby enemies at reduced damage |
| **Nike** | Melee | Support | **Victory Swipe** — dash attack in a line; ignores impassable terrain; brief speed buff to allies she passes through |

---

### Poseidon + Triton
*Mythology: Triton is Poseidon's son and herald, calming/raising seas with his conch.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Poseidon** | Melee | Bruiser | **Tidal Slam** — trident AoE knockback wave in a cone |
| **Triton** | Ranged | Support | **Conch Rally** — horn blast heals + speeds nearby creeps briefly |

---

### Hades + Cerberus
*Mythology: The three-headed hound guards the gates of the Underworld at Hades's side.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hades** | Ranged | Burst DPS (glass cannon) | **Soul Harvest** — damage boost per enemy unit that died nearby recently |
| **Cerberus** | Melee | Tank | **Three-Headed Bite** — hits 3 targets at once, taunts them for 1s |

> ⭐ **Recommended tutorial pair** — strongest internal contrast (glass cannon + tank), best for teaching sidekick logic.

---

### Athena + Owl of Athena
*Mythology: The little owl is Athena's sacred bird, depicted on Athenian coinage.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Athena** | Melee | Tank | **Aegis** — completely blocks the next enemy ability/projectile |
| **Owl** | Ranged | Support | **True Sight** — reveals and marks an enemy; allies deal +15% damage to it |

---

### Ares + Phobos & Deimos
*Mythology: His twin sons, Fear and Terror, drove his war chariot (Homer, Iliad).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Ares** | Melee | DPS (sustain / lifesteal) | **Bloodlust** — attack speed ramps up while in continuous combat |
| **Phobos & Deimos** | Melee | Support (dual-unit, low HP) | **Terror Aura** — nearby enemies attack 20% slower |

---

### Apollo + Corvus
*Mythology: The raven was Apollo's sacred messenger bird (Coronis myth).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Apollo** | Ranged | DPS (longest range in roster) | **Solar Flare** — piercing beam through all units in a line |
| **Corvus** | Ranged | Support | **Death Omen** — marked enemy takes bonus damage from Apollo specifically |

> ⚠️ **First explicit synergy pair.** Playtest whether pair-synergy specials feel good before designing more of them.

---

### Artemis + Hunting Hound
*Mythology: Artemis received her hunting dogs from Pan.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Artemis** | Ranged | Burst DPS (mobile kiter) | **Hunter's Step** — short hop backward + next arrow crits |
| **Hound** | Melee | DPS (chaser) | **Run Down** — bonus damage and speed against targets moving away |

---

### Hermes + Ram
*Mythology: Hermes Kriophoros ("ram-bearer"); god of thieves.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hermes** | Melee | Assassin DPS (fastest hero) | **Pickpocket** — hits steal a small amount of enemy scroll energy |
| **Ram** | Melee | Tank (bodyguard) | **Headbutt** — single-target knockback that interrupts attacks |

---

### Aphrodite + Eros
*Mythology: Eros constantly attends Aphrodite in art and myth.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Aphrodite** | Ranged | Support/Healer hybrid | **Enthrall** — charms an enemy creep to fight for you for 3s |
| **Eros** | Ranged | Support | **Love Arrow** — links two allies; they share 20% of healing received |

---

### Hephaestus + Automaton
*Mythology: Hephaestus built golden mechanical servants and the bronze giant Talos.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hephaestus** | Melee | Tank (slow, heavy) | **Forge Turret** — drops a stationary mini-turret (expires after a few seconds or limited hits) |
| **Automaton** | Melee | Bruiser | **Self-Repair** — regenerates when out of combat for 2s |

---

### Demeter + Persephone
*Mythology: The defining mother-daughter myth; note thematic overlap with Hades's domain (potential faction tension flavor).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Demeter** | Ranged | Healer | **Harvest Bloom** — ground zone that heals allies standing in it |
| **Persephone** | Ranged | Support (state-switcher) | **Season Shift** — toggle: Spring = ally heal aura / Winter = enemy slow aura |

---

### Dionysus + Silenus
*Mythology: Silenus was Dionysus's tutor and constant companion (mentor archetype).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Dionysus** | Melee | Bruiser (drain-tank) | **Revel** — AoE that makes enemies "drunk": randomized wobble pathing briefly |
| **Silenus** | Melee | Support | **Old Master's Blessing** — random strong buff to one ally (damage, speed, or shield) |

---

## Roster balance overview

| Mechanic niche | Pair |
|----------------|------|
| Burst + terrain mobility | Zeus + Nike |
| Knockback / crowd control | Poseidon + Triton |
| Glass cannon + taunt tank | Hades + Cerberus |
| Vision / ability-block | Athena + Owl |
| Debuff / attrition | Ares + Phobos & Deimos |
| Long-range synergy duo | Apollo + Corvus |
| Kiting / chase | Artemis + Hound |
| Resource theft / assassin | Hermes + Ram |
| Charm / heal-link | Aphrodite + Eros |
| Constructs / engineer | Hephaestus + Automaton |
| Zone heal / state toggle | Demeter + Persephone |
| Disruption / RNG buffs | Dionysus + Silenus |

---

## Prototyping priority (suggested)

1. **Hades + Cerberus** — tutorial pair, clearest role contrast, tests taunt + kill-tracking systems
2. **Zeus + Nike** — tests chain targeting + terrain-ignoring dash (new movement case for `unit.gd`)
3. **Poseidon + Triton** — tests AoE knockback + creep buff auras
4. **Athena + Owl** — tests projectile blocking + enemy marking/reveal

These four cover most of the special-ability systems the rest of the roster reuses (taunt, marks, auras, knockback, dashes, chained targeting).

---

## Open design questions

- [ ] Does the sidekick spawn with the hero, on a cooldown card, or as a persistent escort?
- [ ] Sidekick death: respawn timer, or gone until hero respawns?
- [ ] Do sidekick specials auto-cast (AI) or player-triggered? (Player-triggered adds depth but doubles input load on mobile.)
- [ ] Pair-synergy specials (Apollo + Corvus model): expand or keep as a one-off?
