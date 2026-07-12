extends Panel
class_name RespawnCounter

# Mechanika respawnu pride v dalsom kroku; counter je skryty kym je hrdina nazive.

@onready var hero_thumbnail: TextureRect = $HeroThumbnail
@onready var countdown_label: Label = $CountdownLabel

func show_countdown(seconds_left: int) -> void:
	visible = true
	countdown_label.text = str(seconds_left)

func hide_counter() -> void:
	visible = false
