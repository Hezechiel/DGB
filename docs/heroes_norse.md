# Heroes & Cards — Norse Era (Season 2 Draft Spec)

> **Divine Gestures: Babylon — Arena Mode**
> Draft ahead of asset production. Format follows `heroes_greek.md` (hero/sidekick
> pairs) + `cards_greek.md` (common pool + rarity). NOT implementation-ready —
> numbers, factions, and several sidekick choices are placeholders pending the
> same open questions already logged for the Greek era.

---

## Design rules (carried over from Greek era)

1. Every pair contains at least one melee OR one ranged unit.
2. Sidekicks define hero identity mechanically, not just visually.
3. Mythological accuracy first — flagged inline where a pairing takes liberties.
4. One special ability per unit.

---

## Hero + Companion roster

### Odin + Huginn & Muninn
*Mythology: Odin's two ravens, "Thought" and "Memory," fly the world and report back to him daily (Prose Edda).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Odin** | Ranged | Support/Burst hybrid | **All-Father's Gaze** — reveals the whole enemy half briefly, allies gain a small damage buff on revealed targets |
| **Huginn & Muninn** | Ranged | Support (dual-unit, low HP) | **Raven Scout** — flies ahead; first enemy unit it passes is marked for bonus damage |

> ⭐ Suggested tutorial/prototype pair — clean reveal+mark mechanic, reuses Owl of Athena's mark system.

---

### Thor + Tanngrisnir & Tanngnjóstr
*Mythology: Thor's two goats pull his chariot; he can eat them and resurrect them from their hides overnight (Gylfaginning).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Thor** | Melee | Bruiser (highest single-hit damage) | **Mjölnir Throw** — hammer thrown at a target, boomerangs back through the path |
| **Tanngrisnir & Tanngnjóstr** | Melee | Tank (dual-unit) | **Hide and Bone** — first time this unit would die, it revives once at low HP (myth-accurate self-resurrection) |

---

### Freyja + Battle Cats
*Mythology: Freyja's chariot is drawn by two cats, a gift from Thor (Prose Edda).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Freyja** | Ranged | Support/Healer hybrid | **Seiðr Song** — AoE heal + brief damage buff to allies in range |
| **Battle Cats** | Melee | DPS (fast, pair) | **Pounce** — short leap onto nearest enemy, guaranteed first-hit crit |

---

### Freyr + Gullinbursti
*Mythology: The dwarves gifted Freyr a golden boar, Gullinbursti, that pulls his chariot and glows in the dark (Skáldskaparmál).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Freyr** | Ranged | DPS | **Sword That Fights Itself** — auto-attacks continue briefly even if Freyr is interrupted (references his sacrificed self-fighting sword) |
| **Gullinbursti** | Melee | Bruiser | **Golden Charge** — short-range charge, leaves a brief glowing trail that lights up the area (vision utility) |

---

### Loki + Fenrir
*Mythology: Loki fathers Fenrir with the giantess Angrboða; the wolf is prophesied to kill Odin at Ragnarök (Gylfaginning).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Loki** | Ranged | Trickster DPS | **Shapeshift** — briefly disguises as a random enemy unit type (visual only, no stat copy — keep it simple per design rule 4) |
| **Fenrir** | Melee | Tank (breaker) | **Unbound** — the longer Fenrir stays alive in a fight, the more his damage ramps (references the gods' failed attempts to bind him) |

> ⚠️ Thematically strong pairing (foreshadowing/irony) but same-family pairing is a *design* choice, not forced by myth — flag if you'd rather keep Loki's chaos-god identity separate from a "loyal companion" framing.

---

### Tyr + Garmr
*Mythology: Garmr is the hound bound at Gnipahellir, guarding the entrance to Hel's realm, fated to fight Tyr at Ragnarök (Völuspá). Parallels Hades + Cerberus across pantheons.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Tyr** | Melee | Tank (self-sacrifice theme) | **Oathkeeper** — taking damage below 50% HP grants a shield (references losing his hand to Fenrir to keep an oath) |
| **Garmr** | Melee | Tank (taunt) | **Hellhound Howl** — taunts nearby enemies briefly |

> ⚠️ Two taunting tanks in one pair is a mechanical overlap risk — consider giving Garmr a bite/burst variant instead if playtesting shows redundancy with Tyr.

---

### Baldr + Nanna
*Mythology: Nanna is Baldr's wife; she dies of grief on his funeral pyre and is burned beside him (Gylfaginning).*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Baldr** | Ranged | Support/Healer | **Beloved of All** — periodic passive shield pulse to nearest ally (references his near-invulnerability myth) |
| **Nanna** | Ranged | Support | **Grief Bond** — if Baldr dies, Nanna gets a temporary damage/speed buff (references her following him in death) |

---

### Heimdall + Ram
*Mythology: Heimdall is called "Hallinskiði" (a name linked to rams) in skaldic kennings; direct ram-companion myth is thin — this leans on the kenning association rather than a clear narrative pairing.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Heimdall** | Ranged | Vision/Support | **Gjallarhorn Blast** — reveals nearby stealth/disguise effects (counters Loki's Shapeshift directly — cross-hero synergy, same caution flag as Apollo+Corvus) |
| **Ram** | Melee | Bruiser | **Headlong Charge** — knockback charge |

> ⚠️ Weakest mythology grounding in the roster — consider swapping for a different Heimdall companion, or accept as a minor liberty (kenning-based, not fabricated).

---

### Skadi + Wolves
*Mythology: Skadi is a jötunn associated with skiing, hunting, and mountains (Gylfaginning); the wolf-companion angle is a modern/reconstructionist association, not found directly in the Eddas.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Skadi** | Ranged | Burst DPS (mobile kiter) | **Ski Retreat** — short hop + next shot crits (mirrors Artemis's Hunter's Step) |
| **Wolves** | Melee | DPS (chaser, pair) | **Pack Hunt** — bonus damage when both wolves hit the same target |

> ⚠️ Flagged as the second-weakest mythology grounding — the wolf pairing is inferred, not textual. If accuracy matters more than parity-with-Artemis symmetry, consider Skadi solo with a ski/hunting-bow kit and no animal companion.

---

### Hel + Nidhogg
*Mythology: Nidhogg is the dragon/serpent gnawing the roots of Yggdrasil in Niflheim, near Hel's domain (Gylfaginning) — a thematic underworld neighbor rather than a direct attendant, similar honesty-flag as Demeter+Persephone's "faction tension" note in `heroes_greek.md`.*

| Unit | Type | Role | Special |
|------|------|------|---------|
| **Hel** | Ranged | Debuff/Attrition | **Half-Life** — marks an enemy; it takes stacking damage over time if not healed (references her half-living, half-dead form) |
| **Nidhogg** | Melee | Heavy tank | **Root Gnaw** — anti-structure bonus damage (references gnawing Yggdrasil's roots) |

---

## Roster balance overview

| Mechanic niche | Pair |
|---|---|
| Reveal / mark | Odin + Huginn & Muninn |
| Self-resurrection / hammer AoE | Thor + Goats |
| Heal + crit pounce | Freyja + Cats |
| Sustained auto-attack / charge | Freyr + Gullinbursti |
| Disguise / ramping breaker | Loki + Fenrir |
| Self-sacrifice tank / taunt | Tyr + Garmr |
| Shield pulse / death-triggered buff | Baldr + Nanna |
| Anti-stealth vision / knockback | Heimdall + Ram |
| Kiting / pack damage | Skadi + Wolves |
| DoT debuff / anti-structure tank | Hel + Nidhogg |