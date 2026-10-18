extends Resource
class_name CardData

# Spolocny ZAKLAD kazdej karty (Oct 2026). Sam o sebe sa nepouziva — kazda
# karta je UnitData (jednotka/squad) alebo SpellData (spell), obe dedia
# odtialto. Jeden .tres = karta + jej herne data, rovnako ako HeroData.
# Shared base of every card; a card file is a UnitData or a SpellData.

@export var id: StringName
@export var display_name: String
@export var cost: int = 1
@export var scroll_texture: Texture2D
# Typove pristupy: karta SAMA je unit/spell data. Vrati self pretypovane,
# alebo null ak karta je druheho typu. Nie su exportovane (neukladaju sa).
# Typed views: the card itself, or null when it is the other kind.
var unit_data: UnitData:
	get:
		return self as UnitData
var spell_data: SpellData:
	get:
		return self as SpellData

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
# Pri pravidlach balicka aj pri prahu synergy boha sa domain rata ako znacka.
@export var domain: StringName
# Volne znacky (holy, undead, beast, ...). Boh moze niektore odmietat
# (HeroData.forbidden_tags). faction a domain sa pri pravidlach rataju ako
# znacky automaticky — netreba ich sem opakovat.
@export var tags: Array[StringName] = []
# Lore intro pre Card Detail / flashcard. Prazdny = nic sa nezobrazi.
@export_multiline var description: String = ""
