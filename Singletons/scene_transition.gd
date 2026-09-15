## Level transition service, registered as the `SceneTransition` autoload (scene
## `Singletons/scene_transition.tscn`) in `project.godot`. Access from anywhere
## via `SceneTransition`, e.g. `SceneTransition.load_next_level()`.
##
## Unique responsibilities:
## - Fade in/out transitions between scenes (`fade_in`, `fade_out`).
## - Level rotation (`levels`, `load_next_level`) and direct scene loading
##   (`load_scene_path`), preserving the player across scene changes
##   (`player_cache`).
## - Boss fight routing (`boss_arenas`): dungeon levels listed there detour
##   to their boss arena instead of rotating.
extends CanvasLayer

@onready var color_rect: ColorRect = $ColorRect

var player_cache: Character
## Level scenes rotated by load_next_level. Editable in scene_transition.tscn.
@export var levels: Array[String] = [
	"res://Levels/level_1.tscn",
	"res://Levels/level_2.tscn",
	"res://Levels/level_3.tscn",
	"res://Levels/level_4.tscn",
	"res://Levels/level_5.tscn",
	"res://Levels/level_6.tscn",
	"res://Levels/level_7.tscn",
	"res://Levels/level_8.tscn",
	"res://Levels/level_9.tscn",
	"res://Levels/level_10.tscn"
]

## Boss fights keyed by dungeon level: when the run reaches one of these
## levels, load_next_level goes to that boss arena instead of rotating.
## The arena scene carries its boss on its WaveObjective.boss_resources.
## Reusable: later bosses only need a new entry here plus their arena scene.
@export var boss_arenas: Dictionary = {
	10: "res://Levels/boss_arena_1.tscn",
}


func _ready() -> void:
	levels.shuffle()
	fade_out(create_tween())


func fade_out(tween: Tween) -> void:
	tween.tween_property(color_rect, "color:a", 0.0, 1.0)


func fade_in(tween: Tween) -> void:
	tween.tween_property(color_rect, "color:a", 1.0, 1.0)


func load_scene_path(path_in: String, args: Dictionary = {}) -> void:
	var player: Character = get_tree().get_first_node_in_group("player") as Character
	if player:
		# Cancel upfront so movement, abilities, SFX, and the damage flash
		# stop the moment the fade starts (not only after the new level
		# adopts the player). LevelTemplate re-applies the same cancel on
		# restore as a safety net.
		player.cancel_movement_and_abilities()
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var tween: Tween = create_tween()
	fade_in(tween)
	tween.tween_callback(
		func() -> void:
			if player:
				player.reparent(self)
				player_cache = player
			get_tree().change_scene_to_file(path_in)
	)
	tween.tween_interval(0.5)
	fade_out(tween)


func load_next_level(args: Dictionary = {}) -> void:
	var dungeon_level: int = ProgressionState.dungeon_level if ProgressionState != null else 0
	if boss_arenas.has(dungeon_level):
		load_scene_path(str(boss_arenas[dungeon_level]), args)
		return
	levels.push_back(levels.pop_front())
	load_scene_path(levels.front(), args)
