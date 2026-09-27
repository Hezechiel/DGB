extends Node
class_name MatchAnnouncer

# Hlasatel zapasu — samostatny konzument BattleManager signalov (self-subscribe
# v _ready, rovnaky vzor ako death_telegraph / respawn countery). BattleManager
# o zvuku nevie nic. Zije so scenou areny → per-match stav sa resetuje sam.
# Dalsie hlasky (veza padla, double kill...) pribudnu sem, ked budu assety.

var _first_blood_done: bool = false

func _ready() -> void:
	BattleManager.hero_died.connect(_on_hero_died)

func _on_hero_died(_team: String, _respawn_seconds: int) -> void:
	if _first_blood_done:
		return
	_first_blood_done = true
	AudioManager.play_announcer(&"announcer_first_blood")
