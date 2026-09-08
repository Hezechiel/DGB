extends Resource
class_name MapData

# Systemove (neviditelne) udaje o mape — hranice a kamera-tuning, ktore sa
# museli doteraz zhodovat naprieč BattleManager (deploy_bounds) a
# ArenaCamera (bounds_min/max, edge_margin, edge_pan_speed_max) bez
# zdielaneho zdroja (architecture.md §6). Struktury (veze/zakladne/pody)
# TU NIE SU — ostavaju rucne umiestnene v scene kazdej mapy (princip #1).

@export var id: StringName
@export var display_name: String

# Ci mapa patri do realneho hraciho poolu. Default true — existujuce/normalne
# mapy sa nemusia prihlasovat. false = WIP/test mapa (napr. nedokoncena era mapa).
# MapDB.get_random_map_id() je TEMP testovaci picker a NEfiltruje podla tohto pola
# zamerne — nech WIP mapy vidno pocas testovania. Realny mode/rotation/vote picker
# (az vznikne) je to co bude filtrovat podla release_ready — nie je to teraz scoped.
@export var release_ready: bool = true

# PackedScene s obsahom tejto mapy — pozadie/tilemap/prekazky/struktury.
# Zrkadli princip UnitData.archetype_scene: data ukazuju na scenu, nie naopak.
# arena.tscn ju bude vediet nacitat za behu (buduci krok migracie).
@export var map_scene: PackedScene

# Hranice mapy — jediny zdroj pravdy pre BattleManager.deploy_bounds AJ
# ArenaCamera.bounds_min/bounds_max.
@export var bounds: Rect2 = Rect2(-450.0, -350.0, 900.0, 700.0)

# Drag-to-deploy edge-pan (arena_camera.gd) — per-map, kedze vacsia mapa
# chce sirsi okraj/rychlejsi pan.
@export var camera_edge_margin: float = 100.0
@export var camera_edge_pan_speed_max: float = 650.0

# Spawn pozicie hrdinov — predtym @export priamo na arena.gd.
@export var hero_spawn_player: Vector2 = Vector2(-250, 0)
@export var hero_spawn_enemy: Vector2 = Vector2(250, 0)
