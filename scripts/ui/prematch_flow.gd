extends Control

# PreMatchFlow — placeholder pred-zapasovy flow medzi MainMenu a arenou.
# FindingPanel (~FIND_SECONDS) → PreMatchPanel (~PREMATCH_SECONDS) → arena.tscn.
# Ziadne realne matchmaking; vsetky udaje su mock hodnoty z MatchConfig.
#
# LocalAvatar/LocalFactionRect/OpponentAvatar/OpponentFactionRect su docasne
# ColorRect placeholdery — pri napojeni skutocnych faction/avatar assetov ich
# nahradit TextureRect s EXPAND_IGNORE_SIZE + KEEP_ASPECT_CENTERED
# (architecture.md §6).

const ARENA_SCENE := "res://scenes/arena/arena.tscn"
const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const FIND_SECONDS := 1.0
const PREMATCH_SECONDS := 1.0

@onready var finding_panel: Control = $FindingPanel
@onready var prematch_panel: Control = $PreMatchPanel

@onready var finding_title_label: Label = $FindingPanel/InfoBox/TitleLabel
@onready var finding_rank_label: Label = $FindingPanel/InfoBox/RankLabel
@onready var finding_mode_label: Label = $FindingPanel/InfoBox/ModeLabel
@onready var finding_map_label: Label = $FindingPanel/InfoBox/MapLabel
@onready var search_time_label: Label = $FindingPanel/SearchTimeLabel
@onready var cancel_button: Button = $FindingPanel/CancelButton

@onready var prematch_mode_label: Label = $PreMatchPanel/ModeLabel
@onready var local_faction_label: Label = $PreMatchPanel/VersusRow/LocalBlock/LocalFactionLabel
@onready var local_name_label: Label = $PreMatchPanel/VersusRow/LocalBlock/LocalNameLabel
@onready var opponent_faction_label: Label = $PreMatchPanel/VersusRow/OpponentBlock/OpponentFactionLabel
@onready var opponent_name_label: Label = $PreMatchPanel/VersusRow/OpponentBlock/OpponentNameLabel

var _search_elapsed: float = 0.0
var _last_search_seconds: int = -1

func _ready() -> void:
	MatchConfig.setup_placeholder_match()

	finding_title_label.text = "Searching for a battle..."
	finding_rank_label.text = MatchConfig.rank_label
	finding_mode_label.text = "Ranked Match 1 vs 1"
	finding_map_label.text = MatchConfig.map_name
	search_time_label.text = "00:00"

	prematch_mode_label.text = "Ranked Match"
	local_name_label.text = MatchConfig.local_name
	local_faction_label.text = MatchConfig.local_faction
	opponent_name_label.text = MatchConfig.opponent_name
	opponent_faction_label.text = MatchConfig.opponent_faction

	finding_panel.visible = true
	prematch_panel.visible = false

	cancel_button.pressed.connect(_on_cancel_pressed)

	get_tree().create_timer(FIND_SECONDS).timeout.connect(_on_finding_done)

func _process(delta: float) -> void:
	if not finding_panel.visible:
		return
	_search_elapsed += delta
	var secs := int(_search_elapsed)
	if secs != _last_search_seconds:
		_last_search_seconds = secs
		@warning_ignore("integer_division")
		search_time_label.text = "%02d:%02d" % [secs / 60, secs % 60]

func _on_finding_done() -> void:
	finding_panel.visible = false
	prematch_panel.visible = true
	get_tree().create_timer(PREMATCH_SECONDS).timeout.connect(_on_prematch_done)

func _on_prematch_done() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)

func _on_cancel_pressed() -> void:
	# kozmeticky funkcny navrat; realny cancel pride s matchmakingom.
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
