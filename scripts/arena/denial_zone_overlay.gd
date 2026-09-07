extends Node2D
# Vizualny hint pocas drag-to-deploy: precervenene prekryje kazdu
# aktualne aktivnu ochrannu zonu OPACNEHO timu (BattleManager.
# get_active_protection_zones), takze hrac vidi celu zakazanu oblast,
# nie len bod pod prstom (to uz robi DeployGhost). Lacnejsia alternativa
# k shaderu — kresli kazdu zonu ako samostatny obdlznik, ziadna
# kompozitna "diera" geometria; prekryvajuce sa zony sa preto vizualne
# mierne stmavia tam kde sa prekryvaju — akceptovany kozmeticky vedlajsi
# efekt tejto jednoduchsej metody.
#
# DOLEZITE: tento uzol MUSI zostat na position = Vector2(0,0) — kresli
# priamo v absolutnych world-space suradniciach zon (na rozdiel od
# DeployGhost, ktory sa sam premiestnuje na bod dragu a kresli lokalne
# okolo seba).

@export var zone_color := Color(0.9, 0.2, 0.2, 0.2)

# TEMP: len lokalny hrac tahá karty — rovnaky predpoklad ako card_hand.gd
# hardcoduje "player" vsade (BattleManager.is_card_target_valid volania
# atd). Ked pribudne remote/AI drag UI, zmenit na parameter.
const DRAGGING_TEAM := "player"

func _ready() -> void:
	visible = false

# Volane z arena.gd pri deploy_preview_started — raz na zaciatku dragu.
# Spell karty ignoruju ochranne zony (BattleManager.is_card_target_valid
# ich kontroluje len proti deploy_bounds — rovnaka asymetria ako uz
# existuje pre samotnu validaciu, §3.11), takze hint sa pre ne vobec
# nezobrazi — ukazovat zakaz ktory sa v skutocnosti na dragovanu kartu
# nevztahuje by hraca len mýlilo.
func show_for_card(card: CardData) -> void:
	if card != null and card.spell_data != null:
		visible = false
		return
	visible = true
	queue_redraw()

# Volane z arena.gd pri deploy_preview_ended.
func hide_zones() -> void:
	visible = false

func _draw() -> void:
	var enemy_team := "enemy" if DRAGGING_TEAM == "player" else "player"
	for zone in BattleManager.get_active_protection_zones(enemy_team):
		draw_rect(zone, zone_color)
