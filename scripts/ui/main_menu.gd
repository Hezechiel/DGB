extends Control

@onready var nav_rail: VBoxContainer = $Background/NavRail
@onready var main_content: HBoxContainer = $Background/MainContent
@onready var hero_showcase: Control = $Background/MainContent/HeroShowcase
@onready var zeus_idle: AnimatedSprite2D = $Background/MainContent/HeroShowcase/ZeusIdle
@onready var battle_button: Button = $Background/MainContent/BattleCard
@onready var settings_button: TextureButton = $Background/TopBar/SettingsButton
@onready var exit_button: TextureButton = $Background/NavRail/ExitButton
@onready var deck_button: Button = $Background/NavRail/DeckButton
@onready var heroes_button: Button = $Background/NavRail/HeroesButton
@onready var shop_button: Button = $Background/NavRail/ShopButton
@onready var rewards_button: Button = $Background/NavRail/RewardsButton
@onready var version_label: Label = $Background/FooterBar/VersionLabel
@onready var mail_button: Button = $Background/TopBar/MailButton
@onready var gift_button: Button = $Background/TopBar/GiftButton
@onready var coming_soon_toast: PanelContainer = $Background/ComingSoonToast
@onready var coming_soon_label: Label = $Background/ComingSoonToast/ComingSoonLabel

@onready var setting_overlay: SettingsOverlay = $SettingOverlay
@onready var credits_overlay: CreditsOverlay = $CreditsOverlay

const PREMATCH_FLOW_SCENE := "res://scenes/ui/PreMatchFlow.tscn"
const COMING_SOON_DURATION := 1.5

var _toast_token := 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Mobile: hide Exit (Android usually doestn need it)
	#if OS.has_feature("android") or OS.has_feature("ios"):
		#$ExitButton.visible = false
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0-dev")
	nav_rail.visible = true
	battle_button.pressed.connect(_on_battle_button_pressed)
	# Node2D deti Control containera sa necentruju automaticky (HBoxContainer
	# rata len s Control potomkami) — preto centrujeme ZeusIdle rucne cez
	# HeroShowcase.resized, aby to sedelo spravne aj pri roznom aspect ratio
	# (window/stretch/aspect = "expand").
	hero_showcase.resized.connect(_on_hero_showcase_resized)
	_on_hero_showcase_resized()
	settings_button.pressed.connect(_on_settings_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	mail_button.pressed.connect(_show_coming_soon.bind("Mail"))
	gift_button.pressed.connect(_show_coming_soon.bind("Gift"))
	deck_button.pressed.connect(_show_coming_soon.bind("Deck"))
	heroes_button.pressed.connect(_show_coming_soon.bind("Heroes"))
	shop_button.pressed.connect(_show_coming_soon.bind("Shop"))
	rewards_button.pressed.connect(_show_coming_soon.bind("Rewards"))
	#setting_overlay.visible = false

# Docasny "Coming soon" toast pre placeholder tlacidla (Mail/Gift teraz, dalsie
# pribudnu v kroku 3 — nav rail). _toast_token zaruci ze rychle po sebe idúce
# tapnutia (napr. Mail hned po Gift) predlzia zobrazenie namiesto toho aby ho
# predcasne schovali — kazdy show() zrusi platnost predchadzajuceho timeoutu.
func _show_coming_soon(feature_name: String) -> void:
	coming_soon_label.text = "%s — coming soon" % feature_name
	coming_soon_toast.visible = true
	_toast_token += 1
	var token := _toast_token
	get_tree().create_timer(COMING_SOON_DURATION).timeout.connect(func():
		if token == _toast_token:
			coming_soon_toast.visible = false
	)

func _on_hero_showcase_resized() -> void:
	zeus_idle.position = hero_showcase.size / 2

func _on_battle_button_pressed() -> void:
	get_tree().change_scene_to_file(PREMATCH_FLOW_SCENE)

func _on_settings_button_pressed() -> void:
	# overlay version
	#get_tree().paused = true
	nav_rail.visible = false
	main_content.visible = false
	# Background je posledne dieta MainMenu (kreslene navrchu) — bez tohto
	# by overlay ostal skryty za nim aj pri visible = true.
	setting_overlay.move_to_front()
	setting_overlay.open(false)

func _on_credits_button_pressed() -> void:
	# overlay version
	nav_rail.visible = false
	main_content.visible = false
	credits_overlay.move_to_front()
	credits_overlay.open()

func _on_setting_overlay_close_requested() -> void:
	#print("Close_request signal received by main menu")
	setting_overlay.close()
	nav_rail.visible = true
	main_content.visible = true
	#get_tree().paused = false

func _on_credits_overlay_closed() -> void:
	nav_rail.visible = true
	main_content.visible = true

func _on_exit_button_pressed() -> void:
	get_tree().quit()
