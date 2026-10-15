extends PanelContainer
class_name StatTile

# StatTile — jedna dlazdica statu v Card Detail: nazov, hodnota a volitelna
# zelena delta k dalsiemu levelu. / One stat tile: name, value, optional
# next-level delta. Vzhlad ide z theme variacie "StatTile" (dgb_theme).

@onready var name_label: Label = $VBox/NameLabel
@onready var value_label: Label = $VBox/ValueRow/ValueLabel
@onready var delta_label: Label = $VBox/ValueRow/DeltaLabel

# Prazdna delta = DeltaLabel skryty. / Empty delta hides DeltaLabel.
func set_stat(stat_name: String, value: String, delta: String = "") -> void:
	name_label.text = stat_name
	value_label.text = value
	delta_label.text = delta
	delta_label.visible = delta != ""

# Farba hodnoty (napr. rarita). / Value color override (e.g. rarity).
func set_value_color(color: Color) -> void:
	value_label.add_theme_color_override(&"font_color", color)
