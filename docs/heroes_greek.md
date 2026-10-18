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
 
## God skills — shared rules (Oct 2026 draft)

Every god has **one active skill**, SWFA-style: a button with a cooldown, on
top of the auto-attack. The sidekick keeps its own special (still an open
question whether it auto-casts, see the end of this file). The format below
mirrors SWFA: name, Cooldown Time, effect in % of Attack Power.

- **Damage is always % of Attack Power** (`HeroData.projectile_damage`), so
  skills scale with god level automatically through the existing
  `LevelCurve` multiplier, with no per-skill scaling tables. SWFA's
  "(17s)" upgraded-cooldown values can come later as a level perk.
- **Cooldown band 16–28s.** Mobility/utility skills sit low (Artemis 16s),
  executes and charms sit high (Hades 28s, Aphrodite 26s).
- **Gods are protected from the strongest effects.** Executes, charm and
  long CC apply to units only. A god gets flat damage or a reduced
  duration instead (≤ 1s hard CC). No skill can delete or take control of
  the enemy god.
- **Structures:** turrets take damage (often reduced) and can be stunned.
  Bases are immune to skills, the same as spells. Skills never move
  structures.
- **Every skill is readable.** Each one has a visible shape (cone, line,
  circle, chain), so the counterplay is the same as for spells: see it,
  step out of it.
- **Cast through the existing attack pipeline.** Casting a skill cancels a
  pending auto-attack windup (same `_cancel_attack_windup()` path), and a
  stun on the caster cancels a skill that is still winding up.
- **Data (Oct 2026):** each skill is a `SkillData` resource in
  `data/heroes/<pantheon>/skills/` (`scripts/arena/skill_data.gd`), next to
  the god files and their `frames/`; `CardDB` skips `skills/` like `frames/`. Linked from
  `HeroData.skill`. It holds `cooldown`, `cast_range`, a `values` dictionary
  (all tuning numbers, e.g. `damage_pct = 220`) and a `description_template`
  with `{key}` placeholders. Card Detail's Skills tab renders the template
  with the current values, so retuning a number never needs a text rewrite.
  All 12 gods have a `HeroData` + `SkillData` file. The 10 new gods
  (everyone except Zeus and Poseidon) are placeholders: no sprite art
  (`sprite_frames` empty, so in a match they borrow the scene's default look),
  `obtain_source = 0` (never in packs; F10 still grants them for testing), no
  synergy rule yet, and first-pass stats (melee range 20, Apollo 110, Hades
  400 HP, Athena/Hephaestus 650 HP, Hermes speed 90, Hephaestus 55).
- **Runtime (Oct 2026):** built for **Zeus and Poseidon** — cooldown,
  HUD skill button, AI use, and the effects in `SkillEffects`
  (`architecture.md` §5 "God skills"). Casts are instant for now (no skill
  windup or animation). The other ten skills are data only until their
  effect is written; each lists under *Needs* the new mechanics it requires,
  so the cost is visible before one is picked.

---

## Roster
 
### Zeus + Nike
*Mythology: Nike attends Zeus; he holds her in his palm in the Statue of Zeus at Olympia.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Zeus** | Ranged | Burst DPS | **Chain Lightning** (skill) — bolt hits the target and jumps to up to 5 more enemies, micro-stun interrupts attacks |
| **Nike** | Melee | Support | **Victory Swipe** — dash attack in a line; ignores impassable terrain; brief speed buff to allies she passes through |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Zeus** — Master of the skies, Zeus commands the thunder and leads his armies with divine might. His presence inspires all allied units, and his lightning strikes devastate enemies on the battlefield.
- **Nike** — Winged herald of triumph, Nike never leaves Zeus's side. She cuts across the battlefield in a single blinding dash, and every ally she passes surges forward with the speed of certain victory.

**Skill — Zeus: Chain Lightning**
- Cooldown Time: 24s
- Hurls a thunderbolt at the target, dealing 220% of Attack Power. The bolt then arcs to the nearest enemy not yet hit (units, the enemy god and turrets), up to 5 jumps, losing 20% damage per jump. Every target hit is stunned for 0.4s, which interrupts its attack: a god's swing is cancelled and a turret's shot timer restarts.
- *Balance:* Strongest against clustered squads; against a lone god it is just one 220% hit plus a short interrupt. The 0.4s stun is an interrupt, not a lockdown. Bases are immune (they're not in the target registry, same as for spells). Jump range ~60 px, and the bolt never hits the same target twice.
- *Built (Oct 2026):* chain targeting (nearest not-yet-hit within `jump_range` of the last hit), `turret.interrupt_shot()`. "5 jumps" = the target **plus** 5 jumps, 6 targets max; the 20 % falloff is multiplicative per jump (220 → 176 → 141 % …). Units hit only pause their swing for the 0.4 s (existing stun behaviour); gods have it cancelled.
 
---
 
### Poseidon + Triton
*Mythology: Triton is Poseidon's son and herald, calming/raising seas with his conch.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Poseidon** | Melee | Bruiser | **Tidal Wave** (skill) — cone wave, knockback + slow |
| **Triton** | Ranged | Support | **Conch Rally** — horn blast heals + speeds nearby creeps briefly |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Poseidon** — Lord of the seas and shaker of the earth, Poseidon wades into battle with his trident raised. Each strike unleashes the fury of the tide, hurling enemies back like driftwood before a storm.
- **Triton** — Son and herald of Poseidon, Triton rides the waves at his father's command. One blast of his conch rallies the troops, mending their wounds and driving them onward like a rising current.

**Skill — Poseidon: Tidal Wave**
- Cooldown Time: 22s
- Strikes the ground with his trident and sends a wave forward in a cone, dealing 180% of Attack Power to all enemies it hits, knocking them back and slowing them by 30% for 2s.
- *Balance:* A peel and zoning tool: it shoves a push off a turret or breaks a squad's formation. Moderate damage, because the knockback is the value. Knockback distance ~60 px, stopped by obstacles. It doesn't move turrets (they take damage only). Cone ~90°, range ~100 px.
- *Built (Oct 2026):* knockback status on units and gods (0.2 s forced slide, stopped by obstacles, cancels the swing in progress). Damage is flat for every target in the cone; the push is radial, straight away from Poseidon.
 
---
 
### Hades + Cerberus
*Mythology: The three-headed hound guards the gates of the Underworld at Hades's side.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hades** | Ranged | Burst DPS (glass cannon) | **Reaping** (skill) — short-radius execute on units, soul stacks |
| **Cerberus** | Melee | Tank | **Three-Headed Bite** — hits 3 targets at once, taunts them for 1s |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Hades** — Lord of the Underworld, Hades claims every soul that falls on the battlefield. The more enemies perish around him, the greater his dark power grows, until his wrath becomes unstoppable.
- **Cerberus** — The three-headed hound of the Underworld guards its gates against all who would pass. In battle he seizes three foes at once, and none can turn away from his snarling jaws.

**Skill — Hades: Reaping**
- Cooldown Time: 28s
- Sweeps his bident around him. Enemy units below 35% HP in a short radius die instantly; every other enemy (including the enemy god) takes 160% of Attack Power. Each soul reaped grants Hades +8% Attack Power for 8s, stacking up to 5 times.
- *Balance:* **The execute never applies to gods** — they only take the flat 160%. The radius is short (~50 px) on purpose: a ranged glass cannon has to step into melee range to use it, which is the risk that pays for the execute. Turrets and bases are not affected. Strongest after an exchange that has softened a squad, and weak as an opener.
- *Needs:* Execute-below-threshold check on units only; a timed stacking Attack Power buff on the god (a status timer, same pattern as slow).
 
> ⭐ **Recommended tutorial pair** — strongest internal contrast (glass cannon + tank), best for teaching sidekick logic.
 
---
 
### Athena + Owl of Athena
*Mythology: The little owl is Athena's sacred bird, depicted on Athenian coinage.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Athena** | Melee | Tank | **Aegis of Medusa** (skill) — shield, then Gorgon-head stun burst |
| **Owl** | Ranged | Support | **True Sight** — reveals and marks an enemy; allies deal +15% damage to it |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Athena** — Goddess of wisdom and strategic warfare, Athena stands unbroken at the front of every battle. Behind the Aegis, her legendary shield, no blow or spell can find its mark.
- **Owl** — Sacred bird of Athena, the Owl sees what others cannot. From the shadows she reveals the enemy's weakness and guides every allied blade and arrow to its target.

**Skill — Athena: Aegis of Medusa**
- Cooldown Time: 20s
- Raises the Aegis, gaining a shield equal to 30% of her max HP for 4s. When the shield breaks or expires, the Gorgon's head on it flashes: enemy units within a short radius are stunned for 1s, and the enemy god for 0.5s.
- *Balance:* The tank's answer to burst: she absorbs the damage, then punishes the attackers who stayed close. The stun on the god is halved, which keeps lockdown on gods short (see the shared rules). The stun has no damage attached.
- *Needs:* Shield absorb (a new HP layer on the god) and its expiry/break trigger. The stun already exists.
 
---
 
### Ares + Phobos & Deimos
*Mythology: His twin sons, Fear and Terror, drove his war chariot (Homer, Iliad).*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Ares** | Melee | DPS (sustain / lifesteal) | **War Frenzy** (skill) — attack speed, lifesteal, CC immunity |
| **Phobos & Deimos** | Melee | Support (dual-unit, low HP) | **Terror Aura** — nearby enemies attack 20% slower |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Ares** — God of war and bloodshed, Ares lives for the clash of steel. The longer the battle rages, the faster his blade falls, and every wound he deals feeds his savage hunger.
- **Phobos & Deimos** — Fear and Terror, the twin sons of Ares, drive their father's war chariot into the fray. Wherever they stride, enemy hands tremble and their courage drains away.

**Skill — Ares: War Frenzy**
- Cooldown Time: 25s
- Ares gives in to the frenzy of battle for 6s: +30% Attack Speed, his attacks heal him for 25% of the damage dealt, and he is immune to slow and root (but not stun).
- *Balance:* Anakin-style self-buff: no burst, just sustained output. Stun still works on purpose, so Athena, Zeus and Stun-spell counters stay meaningful. The lifesteal makes him a turret-diver only if the enemy ignores him.
- *Needs:* Timed attack-speed buff (the synergy `attack_speed` multiplier path exists, but per-match only, so this needs a timed version); lifesteal on hit; slow/root immunity flags.
 
---
 
### Apollo + Corvus
*Mythology: The raven was Apollo's sacred messenger bird (Coronis myth).*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Apollo** | Ranged | DPS (longest range in roster) | **Solar Flare** (skill) — piercing sun beam in a line |
| **Corvus** | Ranged | Support | **Death Omen** — marked enemy takes bonus damage from Apollo specifically |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Apollo** — God of the sun and master of the bow, Apollo strikes from farther away than any other. His radiant arrows burn through enemy ranks in a single blazing line, sparing no one in their path.
- **Corvus** — Apollo's sacred raven and messenger, Corvus circles high above the battlefield. Whoever he marks is doomed, because the sun god's arrows never miss their chosen prey.

**Skill — Apollo: Solar Flare**
- Cooldown Time: 22s
- Fires a beam of sunlight in a straight line, dealing 200% of Attack Power to every enemy it passes through. Turrets in the line take 50%. A target marked by Corvus takes 50% more.
- *Balance:* Long range (~250 px) matches his longest-range identity, but it is a skillshot with a visible line, so enemies can sidestep it. Damage spread across a whole squad is fair, and only the Corvus synergy makes it a real god-killer.
- *Needs:* Line (capsule) target query, a new shape next to the radius query. The Corvus mark interaction can come later.
 
> ⚠️ **First explicit synergy pair.** Playtest whether pair-synergy specials feel good before designing more of them.
 
---
 
### Artemis + Hunting Hound
*Mythology: Artemis received her hunting dogs from Pan.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Artemis** | Ranged | Burst DPS (mobile kiter) | **Hunter's Step** (skill) — backward hop + empowered arrow |
| **Hound** | Melee | DPS (chaser) | **Run Down** — bonus damage and speed against targets moving away |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Artemis** — Goddess of the hunt and the wild, Artemis never lets her prey out of sight. Swift and elusive, she slips away from danger and answers with an arrow that always finds the heart.
- **Hound** — A gift to Artemis from Pan himself, the Hunting Hound is relentless in pursuit. Any foe who dares to flee only feeds its speed and fury.

**Skill — Artemis: Hunter's Step**
- Cooldown Time: 16s
- Leaps backward a short distance. Her next arrow deals 250% of Attack Power and slows the target by 40% for 2s.
- *Balance:* Short cooldown, because this is mobility first and damage second, which fits the kiter role. The hop is ~60 px and never passes through obstacles. The slow sets up Hound's Run Down.
- *Needs:* A short dash (same movement case as Nike's swipe), plus a "next attack empowered" flag on the god.
 
---
 
### Hermes + Ram
*Mythology: Hermes Kriophoros ("ram-bearer"); god of thieves.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hermes** | Melee | Assassin DPS (fastest hero) | **Swift Theft** (skill) — dash strike that steals 1 energy |
| **Ram** | Melee | Tank (bodyguard) | **Headbutt** — single-target knockback that interrupts attacks |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Hermes** — Swift messenger of the gods and patron of thieves, Hermes strikes before the enemy sees him coming. With every blow he steals a little of their divine power for his own cause.
- **Ram** — Faithful companion of Hermes, the Ram is a stubborn wall of horn and wool. It shields its master from harm and sends attackers reeling with a crushing headbutt.

**Skill — Hermes: Swift Theft**
- Cooldown Time: 20s
- Dashes to the target enemy on winged sandals (~150 px), dealing 180% of Attack Power and stealing 1 scroll energy from the enemy team.
- *Balance:* An assassin's gap-closer with an economic edge. The steal is a hard cap of 1 energy per cast. The dash lands Hermes inside the enemy, so he needs Ram or a quick retreat. Can't target structures.
- *Needs:* Targeted dash; an `EnergySystem` transfer (spend from one team, add to the other). Note: energy is server-authority material (`architecture.md` §7), so this is the first skill that touches the economy.
 
---
 
### Aphrodite + Eros
*Mythology: Eros constantly attends Aphrodite in art and myth.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Aphrodite** | Ranged | Support/Healer hybrid | **Cestus of Desire** (skill) — charm units, weaken the god |
| **Eros** | Ranged | Support | **Love Arrow** — links two allies; they share 20% of healing received |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Aphrodite** — Goddess of love and beauty, Aphrodite was also worshipped armed among the warriors of Sparta. Her gaze bends the will of her enemies and turns foes into allies who fight at her command.
- **Eros** — Son and constant companion of Aphrodite, Eros never misses with his golden bow. His arrows bind allies together, so the strength of one sustains the other.

**Skill — Aphrodite: Cestus of Desire**
- Cooldown Time: 26s
- Unleashes the power of her enchanted girdle in a radius. Up to 2 enemy units are charmed for 4s and fight for her team. An enemy god caught in it is smitten: it deals 25% less damage for 3s.
- *Balance:* **Gods are never charmed**: taking control of the enemy god would be the one effect a player can't play against. Charm is capped at 2 units so it can't flip a whole squad. Charmed units return to their owner afterwards with their HP unchanged.
- *Needs:* Team swap for a timed duration on units (collision layers are computed from team at `_ready()`, so swapping needs a re-apply). A damage-dealt debuff on the god.
 
---
 
### Hephaestus + Automaton
*Mythology: Hephaestus built golden mechanical servants and the bronze giant Talos.*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hephaestus** | Melee | Tank (slow, heavy) | **Forge Turret** (skill) — drops a temporary bronze turret |
| **Automaton** | Melee | Bruiser | **Self-Repair** — regenerates when out of combat for 2s |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Hephaestus** — Smith of the gods and master of the divine forge, Hephaestus shaped the weapons of Olympus. Slow but unbreakable, he raises fire-forged machines that guard the battlefield in his place.
- **Automaton** — Forged from bronze in the workshop of Hephaestus, the Automaton knows neither fear nor fatigue. Whenever the fighting pauses, its tireless mechanism repairs itself for the next clash.

**Skill — Hephaestus: Forge Turret**
- Cooldown Time: 25s
- Hammers a bronze turret into the ground at his feet. It lasts 8s, has 30% of Hephaestus's max HP, and fires at the nearest enemy for 60% of his Attack Power every second.
- *Balance:* Zone control for a slow tank: the turret holds ground he can't reach quickly. It can't be placed inside an enemy protection zone (same deploy rule as unit cards), so it can't be used to siege.
- *Needs:* A summon from the god (reuse the `spawn_unit` / healing-pod stub pattern), with a lifetime/despawn timer. Unit lifetime is already on the `cards_greek.md` §4a wish list for Shades.
 
---
 
### Demeter + Persephone
*Mythology: The defining mother-daughter myth; note thematic overlap with Hades's domain (potential faction tension flavor).*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Demeter** | Ranged | Healer | **Harvest Bloom** (skill) — healing field that slows enemies |
| **Persephone** | Ranged | Support (state-switcher) | **Season Shift** — toggle: Spring = ally heal aura / Winter = enemy slow aura |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Demeter** — Goddess of the harvest and the fertile earth, Demeter brings life wherever she walks. Fields bloom beneath her allies' feet and heal every wound they carry into battle.
- **Persephone** — Queen of the Underworld and maiden of spring, Persephone commands the turning of the seasons. In spring she restores her allies, and in winter she chills her enemies to a crawl.

**Skill — Demeter: Harvest Bloom**
- Cooldown Time: 24s
- Makes a field of grain burst from the ground for 5s. Allies inside heal 4% of their max HP every second, and enemies inside are slowed by 25%.
- *Balance:* Area healer: strong when allies fight inside it, wasted on an empty field. Built on the `SpellZone` model (re-query every tick), so walking out ends it. The healing is per tick, with no HoT carried out of the zone.
- *Needs:* Ally-targeted zone ticks (`SpellZone` today only queries the opposing team). Everything else already exists (zone, slow).
 
---
 
### Dionysus + Silenus
*Mythology: Silenus was Dionysus's tutor and constant companion (mentor archetype).*
 
| Unit | Type | Role | Special |
|------|------|------|---------|
| **Dionysus** | Melee | Bruiser (drain-tank) | **Bacchic Frenzy** (skill) — AoE madness: enemies stagger and can't attack |
| **Silenus** | Melee | Support | **Old Master's Blessing** — random strong buff to one ally (damage, speed, or shield) |

**Intros** *(Card Detail lore — `HeroData.description` once the `.tres` exists)*
- **Dionysus** — God of wine and revelry, Dionysus once marched his wild army to the very edge of the world. His frenzy spreads through enemy ranks and leaves them stumbling, lost in the chaos.
- **Silenus** — Wise old tutor of Dionysus, Silenus has followed his student through every wild campaign. His blessings are unpredictable, but whoever receives one fights with the strength of a god.

**Skill — Dionysus: Bacchic Frenzy**
- Cooldown Time: 22s
- Releases a wave of divine madness around himself, dealing 120% of Attack Power to nearby enemies and maddening them for 2.5s: they stagger in random directions and cannot attack. The enemy god is maddened for 1s.
- *Balance:* Crowd disruption: it breaks a push and pulls units off a turret. The god duration is short, like Athena's stun on gods. Radius ~90 px around Dionysus, so the melee bruiser has to be in the middle of the fight.
- *Needs:* A "maddened" status (random wander + no attack). It is close to stun, but the movement keeps it readable as a different effect.
 
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
- [x] God skill timing — **decided (Oct 2026): skills start on cooldown** (not ready at spawn), and the cooldown restarts in full on respawn. It keeps running while the god is stunned.
- [x] God skill input — **decided: tap-to-fire.** The skill fires toward the god's current target if that target is within the skill's `cast_range`. Aiming specifics get settled during the skill balancing pass.
- [x] AI — **decided: the AI god uses its skill too.** When/condition is part of the balancing pass.
- [ ] Which new mechanics to build next: shield, charm, summon, maddened status, dash, execute. Chain targeting and knockback are built (Zeus, Poseidon).
- [ ] AI skill timing: today the AI casts the moment the skill is ready and anything is in range. Smarter use (wait for a cluster, save it to peel) is part of the balancing pass.
- [ ] Skill presentation: cast animation, sounds, button art, a range indicator — none exist yet.
- [ ] Skill numbers are first-pass placeholders, pending a balance pass alongside the unit stats.
 