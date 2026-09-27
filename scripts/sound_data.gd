extends Resource
class_name SoundData

# Definicia jedneho zvukoveho eventu pre AudioManager.play_sfx(id, pos).
# Jeden .tres v data/sounds/ = jeden event (napr. "sword_hit"), nie jeden subor —
# varianty su v `streams`. Resource je ZDIELANY — runtime stav (posledna
# varianta, cas posledneho prehratia) drzi AudioManager, nikdy nie tu.

# Enum je tu (class_name), nie v AudioManageri — enum autoloadu nejde pouzit
# ako typ (architecture.md §6).
enum Priority { LOW, NORMAL, HIGH, CRITICAL }

@export var id: StringName
# Varianty — nahodny vyber, nikdy nie ta ista dvakrat po sebe. Prazdne pole =
# zvuk este nema asset (AudioManager raz varuje a mlci).
@export var streams: Array[AudioStream] = []
# Voice/Music id-cka hraju cez play_voice/play_announcer/play_stinger — pouzivaju
# volume_db a varianty, ale NIE jitter, positional ani SFX pool.
@export_enum("Combat", "Environment", "Voice", "Music") var bus: String = "Combat"
@export var priority: Priority = Priority.NORMAL
@export var volume_db: float = 0.0
# Nahodne stlmenie o 0..X dB pri kazdom prehrati (-X..0 dB).
@export_range(0.0, 6.0, 0.1) var volume_jitter_db: float = 1.0
# Nahodny pitch v rozsahu 1±X (0.03 = 0.97–1.03).
@export_range(0.0, 0.2, 0.005) var pitch_jitter: float = 0.03
# Max naraz hrajucich instancii TOHTO id — nad limit sa ukradne najstarsia vlastna.
@export var max_instances: int = 4
# Min rozostup (s) medzi dvoma spusteniami tohto id — tlmi "machine gun" efekt
# ked 10 jednotiek zasiahne v tom istom frame.
@export var min_interval: float = 0.05
# false = hra sa bez pozicie (stred, bez panningu/utlmu), aj ked caller poziciu posle.
@export var positional: bool = true
# Svetove px od stredu kamery. Dalej sa zvuk ani nespusti (neobsadi hlas).
@export var max_distance: float = 500.0
