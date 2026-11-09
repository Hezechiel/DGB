extends Resource
class_name RewardsConfig

# RewardsConfig — zdroje relikviarov (Rewards). Cisla su PLACEHOLDER a ladia sa v .tres.
# Relikviar = PackData so shop_visible = false (len karty, hadze PackRoller).

# FREE: jeden relikviar kazdych free_interval_hours, max free_max_stock vo fronte naraz.
@export var free_pack_id: StringName = &"greek_free_reliquary"
@export var free_interval_hours: float = 4.0
@export var free_max_stock: int = 2
# DAILY PLAY: play_goal odohranych zapasov za den -> jeden relikviar.
@export var play_pack_id: StringName = &"greek_play_reliquary"
@export var play_goal: int = 5
# VICTORY: kazda vyhra -> jeden relikviar.
@export var victory_pack_id: StringName = &"greek_victory_reliquary"
