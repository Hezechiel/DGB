extends Node
# Drzitel udajov o zapase pre pre-match flow.
# Neskor toto naplni matchmaking; teraz iba placeholder hodnoty.
# Display polia (mena, faction labely, rank) su iba lokalne — neposielaju sa
# po sieti. Deck polia nizsie su zaklad buduceho match manifestu.

var rank_label: String = "Pantheon Tier"
# map_id nastavuje PreMatchFlow cez MapDB.get_random_map_id(), NIE tu —
# MatchConfig neberie zavislost na inom autoloade pre logiku ktoru nevlastni.
var map_id: StringName = &""
var local_name: String = "Player"
var local_faction: String = "Olympus"
var opponent_name: String = "Opponent"
var opponent_faction: String = "Underworld"

# Balicky pre zapas — naplna PreMatchFlow z PlayerProfile (MatchConfig sam
# neberie zavislost na inom autoloade). Zaklad buduceho "deck manifest"-u,
# ktory si klienti vymenia na zaciatku zapasu; levely pridu v dalsom kroku.
var local_hero_id: StringName = &""
var local_deck_card_ids: Array[StringName] = []
var opponent_hero_id: StringName = &""
var opponent_deck_card_ids: Array[StringName] = []

func setup_placeholder_match() -> void:
	# Naplni holder mock hodnotami. Neskor nahradi matchmaking.
	rank_label = "Pantheon Tier"
	local_name = "Player"
	local_faction = "Olympus"
	opponent_name = "Opponent"
	opponent_faction = "Underworld"
