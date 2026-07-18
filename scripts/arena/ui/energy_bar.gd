extends Control
class_name EnergyBar

# Energy bar hraca. Cita z EnergySystem, sam NEDRZI ziadny stav.
#
# DVE vrstvy vyplne, ZAMERNE dva rozne mechanizmy:
#  - regen_bar (tlmena zlta, POD texturou) sa POLLUJE v _process() — ukazuje
#    suru energiu vratane desatin, takze hrac vidi regeneraciu bezat a vie si
#    naplanovat drahsi scroll. Signal by znamenal ~60 emitov/s.
#  - bar (zlata textura) + CountLabel idu cez signal energy_int_changed, lebo
#    sa menia len pri prechode celeho cisla — zlata ukazuje kolko energie je
#    REALNE k dispozicii (floor). Jeden zdroj pravdy, jeden handler.
#
# bar aj regen_bar su typovane ako Range (spolocny predok ProgressBar aj
# TextureProgressBar), takze zmena vzhladu NEVYZADUJE zmenu tohto skriptu.
#
# process_mode na ROOTe scény je explicitne PAUSABLE (1), nie zdedene z HUD
# (CanvasLayer je WHEN_PAUSED=2 kvoli SettingOverlay). Zdedenie by _process()
# spustalo LEN pocas pauzy — bar by pocas hry stal. PAUSABLE zrkadli
# EnergySystem (autoloady su defaultne pausable), takze bar a model mrznu spolu.

const TEAM := "player"

@onready var bar: Range = $Bar
@onready var regen_bar: Range = $RegenBar
@onready var count_label: Label = $CountLabel

# Pociatocnu hodnotu citame priamo, NIE zo signalu: EnergySystem.reset_match_state()
# bezi v arena._enter_tree(), teda davno predtym nez sa tento _ready() staci
# pripojit — signal by sme prepasli.
func _ready() -> void:
	bar.min_value = 0.0
	bar.max_value = float(EnergySystem.get_max_energy())
	bar.value = float(EnergySystem.get_energy_int(TEAM))
	regen_bar.min_value = 0.0
	regen_bar.max_value = float(EnergySystem.get_max_energy())
	regen_bar.value = EnergySystem.get_energy(TEAM)
	count_label.text = str(EnergySystem.get_energy_int(TEAM))
	EnergySystem.energy_int_changed.connect(_on_energy_int_changed)

func _process(_delta: float) -> void:
	regen_bar.value = EnergySystem.get_energy(TEAM)

func _on_energy_int_changed(team: String, value: int) -> void:
	if team != TEAM:
		return
	bar.value = float(value)
	count_label.text = str(value)
