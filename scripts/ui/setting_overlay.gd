extends FramedOverlay
class_name SettingsOverlay

signal closed_requested
signal exit_requested
signal credits_requested

@onready var exit_button: Button = $FrameFit/FrameRoot/ContentArea/ScrollContainer/SettingsContent/ButtonRow/ExitButton
@onready var lock_camera_toggle: CheckButton = $FrameFit/FrameRoot/ContentArea/ScrollContainer/SettingsContent/LockCameraRow/LockCameraToggle
@onready var credits_button: Button = $FrameFit/FrameRoot/ContentArea/ScrollContainer/SettingsContent/ButtonRow/CreditsButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()  # FramedOverlay: close button, god layout
	exit_button.pressed.connect(_on_exit_button_pressed)
	lock_camera_toggle.toggled.connect(_on_lock_camera_toggled)
	credits_button.pressed.connect(_on_credits_button_pressed)
	visible = false

#show_return_to_mainmenu_button sluzi na skritie alebo ukazanie Main Menu tlacidla
#toto tlacidlo nie je vzdy ziaduce na obrazovke
func open(show_return_to_mainmenu_button: bool = true) -> void:
	#print("menu opened")
	exit_button.visible = show_return_to_mainmenu_button
	# synchnronizuj checkbox so skutocnym stavom nastavenia
	lock_camera_toggle.button_pressed = Settings.lock_camera
	_frame_opened()
	visible = true

func close() -> void:
	#print("Close settings overlay function firred")
	visible = false
	_frame_closed()  # skryty overlay nema co animovat
	#closed.emit()

func _on_frame_close_pressed() -> void:
	#print("Close_request emited")
	closed_requested.emit()

func _on_credits_button_pressed() -> void:
	# Settings sa zatvori PRED vyziadanim Credits — oba su fullscreen overlay,
	# nechceme mat naraz otvorene oba naraz.
	close()
	credits_requested.emit()

func _on_exit_button_pressed() -> void:
	exit_requested.emit()

func _on_lock_camera_toggled(pressed: bool) -> void:
	Settings.set_lock_camera(pressed)
