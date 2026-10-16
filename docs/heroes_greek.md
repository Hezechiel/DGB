# Heroes — Greek Era (Wave 1 Design Spec)
 
> **Duel of Gods: Babylon — Arena Mode**
> Hero + sidekick pairs for the Greek mythology era.
> Format per SWFA model: each playable god has one unique sidekick unit.
>
> **Legend**
> - **Type**: Melee / Ranged
> - **Role**: Tank / DPS / Burst DPS / Bruiser / Healer / Support
> - Flying is visual-only (no gameplay mechanic), with the single exception of Nike's terrain-crossing swipe.
 
---
 
> **Card Detail intros (Oct 2026):** each pair below carries its lore intro.
> Only Zeus and Poseidon have `HeroData` files today; their text is in
> `hero_zeus.tres` / `hero_poseidon.tres` (`description`). Sidekick intros
> wait for sidekick resources. Unit/spell intros: `cards_greek.md` §10.

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

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Zeus** — Master of the skies, Zeus commands the thunder and leads his armies with divine might. His presence inspires all allied units, and his lightning strikes devastate enemies on the battlefield.
- **Nike** — Winged herald of triumph, Nike never leaves Zeus's side. She cuts across the battlefield in a single blinding dash, and every ally she passes surges forward with the speed of certain victory.
 
---
 
### Poseidon + Triton
*Mythology: Triton is Poseidon's son and herald, calming/raising seas with his conch.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Poseidon** | Melee | Bruiser | **Tidal Slam** — trident AoE knockback wave in a cone |
| **Triton** | Ranged | Support | **Conch Rally** — horn blast heals + speeds nearby creeps briefly |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Poseidon** — Lord of the seas and shaker of the earth, Poseidon wades into battle with his trident raised. Each strike unleashes the fury of the tide, hurling enemies back like driftwood before a storm.
- **Triton** — Son and herald of Poseidon, Triton rides the waves at his father's command. One blast of his conch rallies the troops, mending their wounds and driving them onward like a rising current.
 
---
 
### Hades + Cerberus
*Mythology: The three-headed hound guards the gates of the Underworld at Hades's side.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hades** | Ranged | Burst DPS (glass cannon) | **Soul Harvest** — damage boost per enemy unit that died nearby recently |
| **Cerberus** | Melee | Tank | **Three-Headed Bite** — hits 3 targets at once, taunts them for 1s |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Hades** — Lord of the Underworld, Hades claims every soul that falls on the battlefield. The more enemies perish around him, the greater his dark power grows, until his wrath becomes unstoppable.
- **Cerberus** — The three-headed hound of the Underworld guards its gates against all who would pass. In battle he seizes three foes at once, and none can turn away from his snarling jaws.
 
> ⭐ **Recommended tutorial pair** — strongest internal contrast (glass cannon + tank), best for teaching sidekick logic.
 
---
 
### Athena + Owl of Athena
*Mythology: The little owl is Athena's sacred bird, depicted on Athenian coinage.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Athena** | Melee | Tank | **Aegis** — completely blocks the next enemy ability/projectile |
| **Owl** | Ranged | Support | **True Sight** — reveals and marks an enemy; allies deal +15% damage to it |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Athena** — Goddess of wisdom and strategic warfare, Athena stands unbroken at the front of every battle. Behind the Aegis, her legendary shield, no blow or spell can find its mark.
- **Owl** — Sacred bird of Athena, the Owl sees what others cannot. From the shadows she reveals the enemy's weakness and guides every allied blade and arrow to its target.
 
---
 
### Ares + Phobos & Deimos
*Mythology: His twin sons, Fear and Terror, drove his war chariot (Homer, Iliad).*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Ares** | Melee | DPS (sustain / lifesteal) | **Bloodlust** — attack speed ramps up while in continuous combat |
| **Phobos & Deimos** | Melee | Support (dual-unit, low HP) | **Terror Aura** — nearby enemies attack 20% slower |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Ares** — God of war and bloodshed, Ares lives for the clash of steel. The longer the battle rages, the faster his blade falls, and every wound he deals feeds his savage hunger.
- **Phobos & Deimos** — Fear and Terror, the twin sons of Ares, drive their father's war chariot into the fray. Wherever they stride, enemy hands tremble and their courage drains away.
 
---
 
### Apollo + Corvus
*Mythology: The raven was Apollo's sacred messenger bird (Coronis myth).*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Apollo** | Ranged | DPS (longest range in roster) | **Solar Flare** — piercing beam through all units in a line |
| **Corvus** | Ranged | Support | **Death Omen** — marked enemy takes bonus damage from Apollo specifically |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Apollo** — God of the sun and master of the bow, Apollo strikes from farther away than any other. His radiant arrows burn through enemy ranks in a single blazing line, sparing no one in their path.
- **Corvus** — Apollo's sacred raven and messenger, Corvus circles high above the battlefield. Whoever he marks is doomed, because the sun god's arrows never miss their chosen prey.
 
> ⚠️ **First explicit synergy pair.** Playtest whether pair-synergy specials feel good before designing more of them.
 
---
 
### Artemis + Hunting Hound
*Mythology: Artemis received her hunting dogs from Pan.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Artemis** | Ranged | Burst DPS (mobile kiter) | **Hunter's Step** — short hop backward + next arrow crits |
| **Hound** | Melee | DPS (chaser) | **Run Down** — bonus damage and speed against targets moving away |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Artemis** — Goddess of the hunt and the wild, Artemis never lets her prey out of sight. Swift and elusive, she slips away from danger and answers with an arrow that always finds the heart.
- **Hound** — A gift to Artemis from Pan himself, the Hunting Hound is relentless in pursuit. Any foe who dares to flee only feeds its speed and fury.
 
---
 
### Hermes + Ram
*Mythology: Hermes Kriophoros ("ram-bearer"); god of thieves.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hermes** | Melee | Assassin DPS (fastest hero) | **Pickpocket** — hits steal a small amount of enemy scroll energy |
| **Ram** | Melee | Tank (bodyguard) | **Headbutt** — single-target knockback that interrupts attacks |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Hermes** — Swift messenger of the gods and patron of thieves, Hermes strikes before the enemy sees him coming. With every blow he steals a little of their divine power for his own cause.
- **Ram** — Faithful companion of Hermes, the Ram is a stubborn wall of horn and wool. It shields its master from harm and sends attackers reeling with a crushing headbutt.
 
---
 
### Aphrodite + Eros
*Mythology: Eros constantly attends Aphrodite in art and myth.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Aphrodite** | Ranged | Support/Healer hybrid | **Enthrall** — charms an enemy creep to fight for you for 3s |
| **Eros** | Ranged | Support | **Love Arrow** — links two allies; they share 20% of healing received |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Aphrodite** — Goddess of love and beauty, Aphrodite was also worshipped armed among the warriors of Sparta. Her gaze bends the will of her enemies and turns foes into allies who fight at her command.
- **Eros** — Son and constant companion of Aphrodite, Eros never misses with his golden bow. His arrows bind allies together, so the strength of one sustains the other.
 
---
 
### Hephaestus + Automaton
*Mythology: Hephaestus built golden mechanical servants and the bronze giant Talos.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hephaestus** | Melee | Tank (slow, heavy) | **Forge Turret** — drops a stationary mini-turret (expires after a few seconds or limited hits) |
| **Automaton** | Melee | Bruiser | **Self-Repair** — regenerates when out of combat for 2s |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Hephaestus** — Smith of the gods and master of the divine forge, Hephaestus shaped the weapons of Olympus. Slow but unbreakable, he raises fire-forged machines that guard the battlefield in his place.
- **Automaton** — Forged from bronze in the workshop of Hephaestus, the Automaton knows neither fear nor fatigue. Whenever the fighting pauses, its tireless mechanism repairs itself for the next clash.
 
---
 
### Demeter + Persephone
*Mythology: The defining mother-daughter myth; note thematic overlap with Hades's domain (potential faction tension flavor).*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Demeter** | Ranged | Healer | **Harvest Bloom** — ground zone that heals allies standing in it |
| **Persephone** | Ranged | Support (state-switcher) | **Season Shift** — toggle: Spring = ally heal aura / Winter = enemy slow aura |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Demeter** — Goddess of the harvest and the fertile earth, Demeter brings life wherever she walks. Fields bloom beneath her allies' feet and heal every wound they carry into battle.
- **Persephone** — Queen of the Underworld and maiden of spring, Persephone commands the turning of the seasons. In spring she restores her allies, and in winter she chills her enemies to a crawl.
 
---
 
### Dionysus + Silenus
*Mythology: Silenus was Dionysus's tutor and constant companion (mentor archetype).*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Dionysus** | Melee | Bruiser (drain-tank) | **Revel** — AoE that makes enemies "drunk": randomized wobble pathing briefly |
| **Silenus** | Melee | Support | **Old Master's Blessing** — random strong buff to one ally (damage, speed, or shield) |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Dionysus** — God of wine and revelry, Dionysus once marched his wild army to the very edge of the world. His frenzy spreads through enemy ranks and leaves them stumbling, lost in the chaos.
- **Silenus** — Wise old tutor of Dionysus, Silenus has followed his student through every wild campaign. His blessings are unpredictable, but whoever receives one fights with the strength of a god.
 
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
 