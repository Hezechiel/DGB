extends PanelContainer
class_name Card

# PLACEHOLDER: drag-to-deploy input handling is added in a later step.

@onready var scroll_icon: TextureRect = $VBoxContainer/MarginContainer/ScrollIcon
@onready var name_label: Label = $VBoxContainer/NameLabel

var card_data: CardData = null

func configure(data: CardData) -> void:
	card_data = data
	scroll_icon.texture = data.scroll_texture
	name_label.text = data.display_name

func clear() -> void:
	card_data = null
	scroll_icon.texture = null
	name_label.text = ""
