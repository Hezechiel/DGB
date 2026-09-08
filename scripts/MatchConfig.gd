extends Node
# Drzitel udajov o zapase pre pre-match flow.
# Neskor toto naplni matchmaking; teraz iba placeholder hodnoty.
# NIC z tohto sa neposiela po sieti — iba lokalny display holder.

var rank_label: String = "Pantheon Tier"
# map_id nastavuje PreMatchFlow cez MapDB.get_random_map_id(), NIE tu —
# MatchConfig neberie zavislost na inom autoloade pre logiku ktoru nevlastni.
var map_id: StringName = &""
var local_name: String = "Player"
var local_faction: String = "Olympus"
var opponent_name: String = "Opponent"
var opponent_faction: String = "Underworld"

func setup_placeholder_match() -> void:
	# Naplni holder mock hodnotami. Neskor nahradi matchmaking.
	rank_label = "Pantheon Tier"
	local_name = "Player"
	local_faction = "Olympus"
	opponent_name = "Opponent"
	opponent_faction = "Underworld"
