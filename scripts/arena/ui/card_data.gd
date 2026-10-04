extends Resource
class_name CardData

@export var id: StringName
@export var display_name: String
@export var cost: int = 1
@export var scroll_texture: Texture2D
# unit_data a spell_data su NAVZAJOM VYLUCNE — karta je unit karta ALEBO
# spell karta, nikdy oboje (CardDB._load_into to vynucuje pri skene).
@export var unit_data: UnitData
@export var spell_data: SpellData

# Kolko jednotiek karta sumonuje (squad). 1 = jedna jednotka.
@export var unit_count: int = 1
# Polomer formacie pri unit_count > 1 (world units).
@export var formation_radius: float = 12.0

# --- Scrolls (zbierka kariet) metadata ---
# Plain int kody, NIE enum — rovnaky dovod ako SpellData.spell_type.
# rarity: 0 = COMMON, 1 = RARE, 2 = EPIC, 3 = LEGENDARY (4 = UNIQUE je len pre bohov)
@export var rarity: int = 0
# Odkial hrac ziskava DALSIE kopie. 0 = NONE (test/placeholder karta, nikdy
# sa neudeluje), 1 = PACK, 2 = ACHIEVEMENT, 3 = QUEST, 4 = EVENT.
# Starter grant sa tu NEKODUJE — to je zoznam v neskorsom kroku.
@export var obtain_source: int = 0

# Panteon karty (greek, norse, ...). Panteony sa v jednom balicku mozu miesat.
@export var faction: StringName = &"greek"
# Domena napriec panteonmi (olympus/sky, sea, underworld). &"" = common pool.
# Pouzije sa pre synergy bonus boha v neskorsom kroku.
@export var domain: StringName
# Volne znacky (holy, undead, beast, ...). Boh moze niektore odmietat
# (HeroData.forbidden_tags). faction a domain sa pri pravidlach rataju ako
# znacky automaticky — netreba ich sem opakovat.
@export var tags: Array[StringName] = []
# Kratky popis pre flashcard (encyklopedia). Prazdny = nic sa nezobrazi.
@export_multiline var description: String = ""
