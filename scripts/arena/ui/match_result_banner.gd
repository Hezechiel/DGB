extends CanvasLayer
class_name MatchResultBanner

# Vysledkovy banner zaverecnej sekvencie (padla zakladna) — VICTORY / DEFEAT
# nad zamrazenym zaberom kamery. Ciste prezentacne: nevie nic o BattleManageri,
# dostane len winner string z arena.gd. Vlastny CanvasLayer, lebo HUD je
# pocas sekvencie skryty. Nazvy nodov nechat — neskor sa vymenia za textury.

const COLOR_VICTORY := Color(1.0, 0.82, 0.3)    # zlata
const COLOR_DEFEAT := Color(0.85, 0.15, 0.15)   # karmínova
const REVEAL_DELAY := 0.6    # kamera uz je v pohybe (play_focus trva 0.8 s)
const OPEN_TIME := 0.25      # pas sa roztvori zo stredu
const TITLE_TIME := 0.35     # titulok "dopadne" z 1.6x na 1.0x
const SUBTITLE_TIME := 0.3   # podtitulok sa zviditelni
const FADE_OUT_TIME := 0.35  # stmavnutie tesne pred zmenou sceny

@onready var band: ColorRect = $Band
@onready var title: Label = $Band/Title
@onready var subtitle: Label = $Band/Subtitle
@onready var fade: ColorRect = $Fade

func _ready() -> void:
	visible = false

# winner: "player" / "enemy" (z pohladu lokalneho hraca). total_duration =
# dlzka celej sekvencie z arena.gd — fade to black skonci presne na jej konci.
func show_result(winner: String, total_duration: float) -> void:
	var won := winner == "player"
	title.text = "VICTORY" if won else "DEFEAT"
	title.add_theme_color_override("font_color", COLOR_VICTORY if won else COLOR_DEFEAT)
	subtitle.text = "The enemy Command Post has fallen" if won else "Your Command Post has fallen"

	# vychodzi stav pred odhalenim
	band.scale = Vector2(1.0, 0.0)
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	fade.color.a = 0.0
	visible = true
	# pivot na stred — velkosti su znama az po layoute, preto az teraz
	band.pivot_offset = band.size / 2.0
	title.pivot_offset = title.size / 2.0
	title.scale = Vector2(1.6, 1.6)

	var t := create_tween()
	t.tween_interval(REVEAL_DELAY)
	# 1) pas sa "roztvori" zo stredu
	t.tween_property(band, "scale:y", 1.0, OPEN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 2) titulok "dopadne" (zmensi sa z 1.6 na 1.0) a zviditelni sa
	t.tween_property(title, "scale", Vector2.ONE, TITLE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(title, "modulate:a", 1.0, 0.2)
	# 3) podtitulok
	t.tween_property(subtitle, "modulate:a", 1.0, SUBTITLE_TIME)
	# 4) drz, potom stmavni celu obrazovku tesne pred zmenou sceny
	var used := REVEAL_DELAY + OPEN_TIME + TITLE_TIME + SUBTITLE_TIME
	t.tween_interval(maxf(total_duration - used - FADE_OUT_TIME, 0.0))
	t.tween_property(fade, "color:a", 1.0, FADE_OUT_TIME)
