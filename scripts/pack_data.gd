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
# Cena — zatial vzdy 0, mena este neexistuje.
@export var price: int = 0
