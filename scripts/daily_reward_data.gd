extends Resource
class_name DailyRewardData

# DailyRewardData — rozsahy dennej odmeny. Zatial TESTER faucet: bez limitu a casovaca.
# TODO(economy): cooldown / denny limit + streak (2h/6h/12h/24h track) pred verejnym buildom
# Cisla su PLACEHOLDER a ladia sa v .tres. max < min sa pri hode prehodi, zaporne -> 0.

@export var gold_min: int = 100
@export var gold_max: int = 300
@export var crystals_min: int = 100
@export var crystals_max: int = 300
