extends Resource
class_name SkillData

# Aktivny skill boha (jeden na boha). Resource je ZDIELANY — runtime stav
# (zostavajuci cooldown a pod.) sa nikdy nezapisuje spat, len do uzlu boha.
# God's active skill. Shared resource — runtime state lives on the god node.
#
# Pravidla (Oct 2026): skill zacina na cooldowne (nie je ready pri spawne),
# tap-to-fire na aktualny ciel ak je v cast_range, AI ho pouziva tiez.
# Runtime system zatial NEEXISTUJE — toto su data + text pre Card Detail.

@export var id: StringName
@export var display_name: String
# Sekundy medzi pouzitiami. / Seconds between uses.
@export var cooldown: float = 20.0
# Max vzdialenost k cielu, aby sa skill spustil (world px).
# Max distance to the current target for the skill to fire.
@export var cast_range: float = 100.0
# Ladiace hodnoty — JEDINE miesto na balans. Kluc = nazov parametra,
# hodnota = cislo. Konvencia: kluce s "_pct" su percenta (220 = 220 %
# Attack Power), ostatne su sekundy / px / pocty podla nazvu.
# Tuning values — the one place to balance a skill.
@export var values: Dictionary = {}
# Text pre Card Detail s placeholdermi {kluc} z `values` (+ {cooldown},
# {cast_range}). Zmena cisla vo `values` sa prejavi v texte sama.
# Card Detail text; {key} placeholders are filled from `values`.
@export_multiline var description_template: String = ""

# Hodnota parametra pre runtime (napr. get_value(&"damage_pct") / 100.0).
func get_value(key: StringName, default_value: float = 0.0) -> float:
	return float(values.get(key, default_value))

# Hotovy text: template s dosadenymi hodnotami. Neznamy placeholder ostane
# viditelny ako "{kluc}", aby sa chyba v texte hned vsimla.
func get_description() -> String:
	var params := {
		"cooldown": format_number(cooldown),
		"cast_range": format_number(cast_range),
	}
	for key in values:
		params[String(key)] = format_number(float(values[key]))
	return description_template.format(params)

# 220.0 -> "220", 0.4 -> "0.4", 1.25 -> "1.25"
static func format_number(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(roundi(v))
	return String.num(v, 2)
