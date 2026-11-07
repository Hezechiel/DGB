extends PanelContainer
class_name CurrencyCounter

# CurrencyCounter — zostatok jednej meny v TopBare (ikona + suma + "+").
# Self-subscribing: sam pocuva PlayerProfile.wallet_changed, nikto ho neplni.
# "+" len emituje add_pressed — nakup riesi rodic (zatial coming soon).

signal add_pressed(currency: StringName)

@export var currency: StringName = &"gold"
@export var icon: Texture2D

@onready var icon_rect: TextureRect = %Icon
@onready var amount_label: Label = %AmountLabel
@onready var add_button: Button = %AddButton

func _ready() -> void:
	icon_rect.texture = icon
	PlayerProfile.wallet_changed.connect(_on_wallet_changed)
	add_button.pressed.connect(func(): add_pressed.emit(currency))
	amount_label.text = format_amount(PlayerProfile.get_currency(currency))

func _on_wallet_changed(changed: StringName, amount: int) -> void:
	if changed != currency:
		return
	amount_label.text = format_amount(amount)

# 1737 -> "1,737" (Shop to pouziva aj na ceny)
static func format_amount(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = digits[i] + out
		count += 1
	return ("-" + out) if n < 0 else out
