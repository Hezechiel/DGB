extends Control

@onready var nav_rail: VBoxContainer = $Background/NavRail
@onready var main_content: Control = $Background/MainContent
@onready var home_view: HBoxContainer = $Background/MainContent/HomeView
@onready var hero_showcase: Control = $Background/MainContent/HomeView/HeroShowcase
@onready var zeus_idle: AnimatedSprite2D = $Background/MainContent/HomeView/HeroShowcase/ZeusIdle
@onready var battle_button: TextureButton = $Background/MainContent/HomeView/BattleCard
@onready var settings_button: TextureButton = $Background/TopBar/SettingsButton
@onready var battles_button: TextureButton = $Background/NavRail/BattlesButton
@onready var deck_button: TextureButton = $Background/NavRail/DeckButton
@onready var pantheon_button: TextureButton = $Background/NavRail/PantheonButton
@onready var shop_button: TextureButton = $Background/NavRail/ShopButton
@onready var rewards_button: TextureButton = $Background/NavRail/RewardsButton
@onready var exit_button: TextureButton = $Background/NavRail/ExitButton
@onready var version_label: Label = $Background/FooterBar/VersionLabel
@onready var mail_button: TextureButton = $Background/TopBar/MailButton
@onready var gift_button: TextureButton = $Background/TopBar/GiftButton
@onready var coming_soon_toast: PanelContainer = $Background/ComingSoonToast
@onready var coming_soon_label: Label = $Background/ComingSoonToast/ComingSoonLabel
@onready var background: Panel = $Background

@onready var setting_overlay: SettingsOverlay = $SettingOverlay
@onready var credits_overlay: CreditsOverlay = $CreditsOverlay
@onready var card_detail: CardDetail = $CardDetail
@onready var shop_overlay: ShopOverlay = $Background/MainContent/ShopOverlay
@onready var deck_overlay: DeckOverlay = $Background/MainContent/DeckOverlay
@onready var pantheon_overlay: PantheonOverlay = $Background/MainContent/PantheonOverlay

# NavRail taby — kazdy prepina stranku v MainContent (rail, TopBar a FooterBar ostavaju).
enum Tab { HOME, DECK, PANTHEON, SHOP }

# Idle klip boha v showcase — obaja sucasni bohovia maju preklep "iddle_left",
# "idle_left" je spravny nazov pre buducich. / Idle clip names, typo first.
const SHOWCASE_ANIMS: Array[StringName] = [&"iddle_left", &"idle_left"]

const PREMATCH_FLOW_SCENE := "res://scenes/ui/PreMatchFlow.tscn"
const COMING_SOON_DURATION := 1.5
# Menu pozadia podla tieru — neskor sa vyber naviaze na player level
const MENU_BACKGROUNDS: Array[String] = [
	"res://assets/menu/background/greek/greek_tier1.png",
	"res://assets/menu/background/greek/greek_tier2.png",
	"res://assets/menu/background/greek/greek_tier3.png",
]

var _toast_token := 0
# Frames zo sceny (Zeus) — fallback, ked aktivny boh este nema idle animaciu.
var _default_showcase_frames: SpriteFrames

var _current_tab: int = -1
var _pending_tab: int = -1          # tab cakajuci na Discard v Deck tabe
var _tab_pages: Dictionary = {}     # Tab -> Control
var _tab_buttons: Dictionary = {}   # Tab -> TextureButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Mobile: hide Exit (Android usually doestn need it)
	#if OS.has_feature("android") or OS.has_feature("ios"):
		#$ExitButton.visible = false
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0-dev")
	_apply_menu_background()
	nav_rail.visible = true
	battle_button.pressed.connect(_on_battle_button_pressed)
	# Node2D deti Control containera sa necentruju automaticky (HBoxContainer
	# rata len s Control potomkami) — preto centrujeme ZeusIdle rucne cez
	# HeroShowcase.resized, aby to sedelo spravne aj pri roznom aspect ratio
	# (window/stretch/aspect = "expand").
	hero_showcase.resized.connect(_on_hero_showcase_resized)
	_on_hero_showcase_resized()
	_default_showcase_frames = zeus_idle.sprite_frames
	_apply_showcase_god()
	# Zmena balicka (Deck screen ulozi noveho aktivneho boha) -> prekresli showcase
	PlayerProfile.profile_changed.connect(_apply_showcase_god)
	settings_button.pressed.connect(_on_settings_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	mail_button.pressed.connect(_show_coming_soon.bind("Mail"))
	gift_button.pressed.connect(_show_coming_soon.bind("Gift"))
	rewards_button.pressed.connect(_show_coming_soon.bind("Rewards"))
	_tab_pages = {
		Tab.HOME: home_view,
		Tab.DECK: deck_overlay,
		Tab.PANTHEON: pantheon_overlay,
		Tab.SHOP: shop_overlay,
	}
	_tab_buttons = {
		Tab.HOME: battles_button,
		Tab.DECK: deck_button,
		Tab.PANTHEON: pantheon_button,
		Tab.SHOP: shop_button,
	}
	# ButtonGroup: vzdy presne jeden stlaceny — texture_pressed ukazuje aktivny tab.
	var group := ButtonGroup.new()
	for tab in _tab_buttons:
		var button: TextureButton = _tab_buttons[tab]
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_request_tab.bind(tab))
	deck_overlay.leave_confirmed.connect(_on_deck_leave_confirmed)
	pantheon_overlay.card_detail_requested.connect(_on_card_detail_requested)
	card_detail.closed.connect(_on_card_detail_closed)
	_switch_tab(Tab.HOME)
	#setting_overlay.visible = false
	AudioManager.play_music(&"menu")

# Zatial nahodny vyber. TODO: neskor podla player levelu (vyssi level = rozvinutejsie
# pozadie) — vtedy sa meni len tato funkcia.
func _pick_background_path() -> String:
	return MENU_BACKGROUNDS.pick_random()

# load() (nie preload) — v pamati je len jedna textura. StyleBox duplikujeme,
# aby sme nemenili cached sub_resource z PackedScene (modulate_color ostane).
func _apply_menu_background() -> void:
	var path := _pick_background_path()
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("Menu background failed to load: %s (keeping scene default)" % path)
		return
	var sb := background.get_theme_stylebox("panel").duplicate() as StyleBoxTexture
	sb.texture = tex
	background.add_theme_stylebox_override("panel", sb)
	DebugLog.info("menu", "background: %s" % path)

# Docasny "Coming soon" toast pre placeholder tlacidla (Mail/Gift/Rewards —
# Rewards nie je tab, vybrany tab sa nemeni). _toast_token zaruci ze rychle po sebe idúce
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

# Showcase ukazuje boha aktivneho balicka (PlayerProfile.get_deck_hero()).
# Boh bez sprite_frames / bez idle klipu -> Zeus zo sceny. Shared SpriteFrames
# sa len priradi uzlu, nikdy sa nemeni (architecture.md §6).
func _apply_showcase_god() -> void:
	var frames: SpriteFrames = null
	var hero_id := PlayerProfile.get_deck_hero()
	if CardDB.has_hero(hero_id):
		frames = CardDB.get_hero(hero_id).sprite_frames
	var anim := _find_idle_anim(frames)
	if anim == &"":
		frames = _default_showcase_frames
		anim = _find_idle_anim(frames)
	if anim == &"":
		return  # ani fallback nema idle — nechaj scenu tak
	if zeus_idle.sprite_frames == frames and zeus_idle.animation == anim and zeus_idle.is_playing():
		return  # rovnaky boh — nerestartuj animaciu
	zeus_idle.sprite_frames = frames
	zeus_idle.play(anim)
	DebugLog.info("menu", "showcase: %s (%s)" % [hero_id, anim])

func _find_idle_anim(frames: SpriteFrames) -> StringName:
	if frames == null:
		return &""
	for anim in SHOWCASE_ANIMS:
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			return anim
	return &""

func _on_hero_showcase_resized() -> void:
	zeus_idle.position = hero_showcase.size / 2

func _on_battle_button_pressed() -> void:
	get_tree().change_scene_to_file(PREMATCH_FLOW_SCENE)

# --- Taby ---

func _request_tab(tab: int) -> void:
	if tab == _current_tab:
		return
	if _current_tab == Tab.DECK and deck_overlay.has_unsaved_changes():
		_pending_tab = tab
		# ButtonGroup uz stlacil novy button — vrat vyber na Deck
		_tab_buttons[Tab.DECK].button_pressed = true
		deck_overlay.confirm_leave()
		return
	_switch_tab(tab)

# Discard v Deck tabe — Deck sa uz sam deaktivoval. Cancel netreba riesit:
# Deck button je uz znovu vybrany a stary _pending_tab sa prepise pri dalsom
# _request_tab(), takze je neskodny.
func _on_deck_leave_confirmed() -> void:
	if _pending_tab >= 0:
		_switch_tab(_pending_tab)
		_pending_tab = -1

func _switch_tab(tab: int) -> void:
	if _current_tab >= 0:
		var old_page: Control = _tab_pages[_current_tab]
		if old_page.has_method("deactivate"):
			old_page.deactivate()
		else:
			old_page.visible = false
	var page: Control = _tab_pages[tab]
	if page.has_method("activate"):
		page.activate()
	else:
		page.visible = true
	# set button_pressed emituje len toggled, nie pressed — ziadna rekurzia
	_tab_buttons[tab].button_pressed = true
	_current_tab = tab
	DebugLog.info("menu", "tab: %s" % Tab.keys()[tab])

# Rail + obsah sa skryju pod fullscreen overlay (Settings/Credits/CardDetail).
# Stranka aktivneho tabu ostava nedotknuta, takze po zatvoreni je tab rovnaky.
func _set_menu_chrome_visible(v: bool) -> void:
	nav_rail.visible = v
	main_content.visible = v

func _on_card_detail_requested(id: StringName, kind: StringName) -> void:
	_set_menu_chrome_visible(false)
	card_detail.move_to_front()
	card_detail.open_for(id, kind)

func _on_card_detail_closed() -> void:
	_set_menu_chrome_visible(true)

func _on_settings_button_pressed() -> void:
	# overlay version
	#get_tree().paused = true
	_set_menu_chrome_visible(false)
	# Background je posledne dieta MainMenu (kreslene navrchu) — bez tohto
	# by overlay ostal skryty za nim aj pri visible = true.
	setting_overlay.move_to_front()
	setting_overlay.open(false)

func _on_credits_button_pressed() -> void:
	# overlay version
	_set_menu_chrome_visible(false)
	credits_overlay.move_to_front()
	credits_overlay.open()

func _on_setting_overlay_close_requested() -> void:
	#print("Close_request signal received by main menu")
	setting_overlay.close()
	_set_menu_chrome_visible(true)
	#get_tree().paused = false

func _on_credits_overlay_closed() -> void:
	_set_menu_chrome_visible(true)

func _on_exit_button_pressed() -> void:
	get_tree().quit()

# --- DEBUG profil (len debug build) ---
# F9  = reset profilu na starter
# F10 = +1 kopia kazdej ziskatelnej karty a kazdeho boha
# F11 = zapni/vypni DebugLog vypisy
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F9:
			PlayerProfile.reset_profile()
			print("[debug] profile reset to starter")
		KEY_F10:
			var ids: Array[StringName] = []
			for id in CardDB.list_card_ids():
				if CardDB.get_card(id).obtain_source != 0:
					ids.append(id)
			ids.append_array(CardDB.list_hero_ids())
			PlayerProfile.grant_cards(ids)
			print("[debug] granted +1 copy of %d cards/gods" % ids.size())
		KEY_F11:
			DebugLog.enabled = not DebugLog.enabled
			print("[debug] DebugLog %s" % ("ON" if DebugLog.enabled else "OFF"))
