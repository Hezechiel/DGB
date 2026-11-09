extends Resource
class_name PackData

# PackData — definicia jedneho balicka zvitkov. Cisla su PLACEHOLDER a
# ladia sa v .tres. Vahy rarit su PER BALICEK: lacne balicky maju UNIQUE
# (bohovia) na 0, sancu davaju len "cherished" balicky a eventy.

@export var id: StringName
@export var display_name: String
@export var card_count: int = 5
# Filter panteonu. &"" = bez filtra.
@export var faction: StringName = &"greek"
# Vahy podla rarity, index = rarity kod (0 COMMON .. 4 UNIQUE). Dlzka 5.
# Nemusia davat sucet 100 — su relativne.
@export var rarity_weights: PackedFloat32Array
# POSLEDNY slot balicka ma zarucenu aspon tuto raritu. 0 = bez garancie.
@export var guaranteed_min_rarity: int = 1
# Cena v mene `currency`; <= 0 = zadarmo.
@export var price: int = 0
# Shop vizual — cesta k art truhlice; chyba subor -> placeholder
@export var chest_texture_path: String = ""
# Mena: &"free" / &"gold" / &"crystals" (urcuje aj ikonu a farbu tlacidla)
@export var currency: StringName = &"free"
# Poradie v shope (vzostupne)
@export var shop_order: int = 0
# false = relikviar (Rewards), nezobrazuje sa v Shope
@export var shop_visible: bool = true
