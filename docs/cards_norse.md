## Common pool — rarity tiers (asset planning)

Mirrors the "few basic, few rare, few unique" ask — sized for a first asset pass,
not a final balance spec. Cost/rarity mapping and exact numbers are placeholders,
same status as the Greek common pool's cost tiers.

### Basic (cheap, staple — high acquisition/use frequency)
Real historically-grounded Norse troop types, same pillar as the Greek hoplite/toxotes pool:

| Card | Type | Role | Notes |
|------|------|------|-------|
| **Huskarl** | Melee | Tank creep | Housecarl — sworn household warrior, shield + axe |
| **Skjaldmey** | Melee | DPS | Shieldmaiden — semi-legendary warrior women (sagas, disputed historicity — flag as folklore-adjacent, not settled fact) |
| **Bondi Spearman** | Melee | Cheap swarm | Levied farmer-warrior, spear + round shield |
| **Norse Archer** | Ranged | DPS | Yew/elm bow, staple backline |
| **Throwing Axeman** | Ranged | Short-range skirmisher | Hand-axes thrown at close quarters — outranges melee but falls well short of the archer, so it has to close before it can work. The Norse answer to the Greek peltast |
| **Runemaster** | Ranged | Support (buff) | Rune-carvers (*erilaz*) are historical; battlefield rune-magic is folklore — same caveat as Skjaldmey above. Cheap, fragile, no offense: while alive it raises the team's energy regen |
| **Jarl** | Melee | Elite leader | Earl/chieftain — quality against the Bondi's quantity: one expensive body with real stats instead of four cheap ones. **Sits awkwardly in a "cheap staple" tier** (see open questions) |
| **Longboat** | Melee | Squad delivery (3–4) | A raiding party that arrives together — "longboat" as flavor for the squad, since the arena has no water to sail (see open questions) |

- **Throwing Axeman** fills the real gap in this tier: everything else is either
  melee contact or full backline range, with nothing in between.
- **Runemaster's buff is the cheap version on purpose.** A team energy-regen boost
  reuses the modifier layer that already exists (`EnergySystem.add_modifier`, the
  same one behind the bloodlust discount), so it needs no new unit mechanic. The
  richer alternative — an armor or damage aura on nearby friendlies — is a new
  system with no current equivalent; cost it before choosing.
- **Longboat deliberately does not introduce transport.** As written it is the
  existing `unit_count` squad mechanic with Norse flavor. A real "sails in and
  unloads at the map edge" card means forward-deployment, which the deploy-zone
  rules (`game_design.md` §3.7) do not have and would need designing.

### Rare (stronger, mythologically flavored)
| Card | Type | Role | Notes |
|------|------|------|-------|
| **Berserker** | Melee | Glass-cannon DPS | Bear/wolf-skin warriors, battle-frenzy (Ynglinga saga) |
| **Ulfhednar** | Melee | DPS (wolf-warrior variant of berserker) | Wolf-pelt counterpart to the bear-associated berserker |
| **Valkyrie** | Ranged | Support/Healer (flying, visual only) | Choosers of the slain — thematically strong healer/reveal candidate |
| **Draugr** | Melee | Bruiser (undead, tough) | Reanimated mound-dwelling undead (sagas — Grettis saga et al.) |

### Unique (legendary, single high-impact unit — siege/heavy tier)
| Card | Type | Role | Notes |
|------|------|------|-------|
| **Jörmungandr** | Melee/Siege | Heavy anti-structure | World-serpent, Thor's fated foe — big single unit, not a squad |
| **Surtr** | Melee | Heavy tank/DPS | Fire jötunn of Muspelheim, wields a flaming sword, Ragnarök figure |
| **Sleipnir** | — | *(stub — mount/summon utility, not a combat creep)* | Odin's eight-legged horse; better suited to a hero-ability stub (mirrors the `spawn_healing_pod` precedent in `game_design.md` §6) than a standalone card |
| **Ice Golem** | Melee | Heavy control tank | Slow, enormous, and chills whatever it hits — reuses the `apply_slow` status that Storm already drives, so it costs no new mechanic. The deliberate opposite number to Surtr: fire and offense against ice and control. **The name is not Norse** (see open questions) |

- Ice Golem and Surtr are a matched pair by design — same tier, same weight class,
  opposite jobs. Playing both in one deck should feel redundant, not doubly strong.
- Of the four Unique cards, only Ice Golem is buildable on today's systems
  (`apply_slow` exists). Jörmungandr needs anti-structure damage weighting, Surtr
  needs whatever makes a Ragnarök-tier body distinct from a big Draugr, and
  Sleipnir is a hero ability rather than a card at all.

---

## Open questions (carried forward / new)

- [ ] Faction structure for Norse (Aesir/Vanir/Jotunn per `cards_greek.md` §7) —
      undecided until Greek's faction-bonus Open Question 1 resolves.
- [ ] Rarity tier (Basic/Rare/Unique) vs. cost tier (Cheap/Medium/High from
      Greek) — same system renamed, or two separate axes? Affects whether
      Greek needs a retrofit.
- [ ] Skadi's wolf companion and Heimdall's ram — accept the mythological
      liberty, or redesign those two kits without an animal sidekick?
- [ ] Loki + Fenrir: keep the "raise your own doom" irony, or is a
      villain-adjacent hero pairing off-tone for the roster?
- [ ] Sleipnir: hero-ability stub (which hero?) vs. cut entirely for this pass.
- [ ] Skjaldmey historicity note — keep as flavor text caveat, or omit the
      disputed-historicity framing from player-facing text entirely?
- [ ] **Ice Golem's name is wrong for the era.** Golems are Jewish folklore, not
      Norse. The authentic equivalents are the rime-thurs / *hrímþursar* (frost
      giants) — rename to **Rime-Thurs** (or Hrímthurs), or accept the generic
      fantasy name and drop the historicity pillar for Unique-tier cards?
- [ ] **Jarl and Longboat sit oddly in the Basic tier** — an elite leader and a
      3–4 unit squad are not "cheap staples". Promote both to Rare, widen what
      Basic means, or make Jarl genuinely cheap and weak?
- [ ] **Runemaster's buff shape**: team energy-regen boost (reuses the existing
      modifier layer, cheap to build) vs. an armor/damage aura on nearby
      friendlies (new system, no current equivalent)?
- [ ] Longboat: keep it as flavored squad delivery, or design real
      forward-deployment (arrive at the map edge, unload) — which the deploy-zone
      rules don't currently support?
- [ ] Norse rare/unique pools have no equivalent of the Greek §4a
      faction-unique split, because Norse factions are still undecided. Confirm
      the Unique tier here is a *rarity* tier and not a faction tier before more
      cards accumulate under it.