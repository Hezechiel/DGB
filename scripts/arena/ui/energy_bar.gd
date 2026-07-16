extends Control
class_name EnergyBar

# Energy bar hraca. Cita z EnergySystem, sam NEDRZI ziadny stav.
#
# ZAMERNE dva rozne mechanizmy:
#  - VYPLN (bar.value) sa POLLUJE v _process(), lebo energia sa meni kazdy
#    frame (plynula regeneracia). Signal by znamenal ~60 emitov/s a
#    HealthBar-ovsky tween by nemal co dobiehat — hodnota sa medzitym uz posunula.
#  - CISLO (CountLabel) ide cez signal energy_int_changed, lebo sa meni len pri
#    prechode celeho cisla. Rovnaky pattern ako match_time_tick.
#
# bar je typovany ako Range (spolocny predok ProgressBar aj TextureProgressBar),
# takze vymena za texturovy bar v kroku 4 NEVYZADUJE zmenu tohto skriptu.
#
# process_mode na ROOTe scény je explicitne PAUSABLE (1), nie zdedene z HUD
# (CanvasLayer je WHEN_PAUSED=2 kvoli SettingOverlay). Zdedenie by _process()
# spustalo LEN pocas pauzy — bar by pocas hry stal. PAUSABLE zrkadli
# EnergySystem (autoloady su defaultne pausable), takze bar a model mrznu spolu.

const TEAM := "player"

@onready var bar: Range = $Bar
@onready var count_label: Label = $CountLabel

# Pociatocnu hodnotu citame priamo, NIE zo signalu: EnergySystem.reset_match_state()
# bezi v arena._enter_tree(), teda davno predtym nez sa tento _ready() staci
# pripojit — signal by sme prepasli.
func _ready() -> void:
	bar.min_value = 0.0
	bar.max_value = float(EnergySystem.get_max_energy())
	bar.value = EnergySystem.get_energy(TEAM)
	count_label.text = str(EnergySystem.get_energy_int(TEAM))
	EnergySystem.energy_int_changed.connect(_on_energy_int_changed)

func _process(_delta: float) -> void:
	bar.value = EnergySystem.get_energy(TEAM)

func _on_energy_int_changed(team: String, value: int) -> void:
	if team != TEAM:
		return
	count_label.text = str(value)
