## Level transition service, registered as the `SceneTransition` autoload (scene
## `Singletons/scene_transition.tscn`) in `project.godot`. Access from anywhere
## via `SceneTransition`, e.g. `SceneTransition.load_next_level()`.
##
## Unique responsibilities:
## - Fade in/out transitions between scenes (`fade_in`, `fade_out`).
## - Loading the next encounter's dungeon (`load_next_level`; the dungeon,
##   boss arenas included, is chosen by `ProgressionState` from the
##   `GlobalVars.dungeons` registry) and direct scene loading
##   (`load_scene_path`), preserving the player across scene changes
##   (`player_cache`).
extends CanvasLayer

@onready var color_rect: ColorRect = $ColorRect

var player_cache: Character


func _ready() -> void:
	fade_out(create_tween())


func fade_out(tween: Tween) -> void:
	tween.tween_property(color_rect, "color:a", 0.0, 1.0)


func fade_in(tween: Tween) -> void:
	tween.tween_property(color_rect, "color:a", 1.0, 1.0)


func load_scene_path(path_in: String, args: Dictionary = {}) -> void:
	var player: Character = get_tree().get_first_node_in_group("player") as Character
	if player:
		# Cancel upfront so movement, abilities, SFX, damage flash, fire,
		# and temporary status effects stop the moment the fade starts
		# (not only after the new level adopts the player). LevelTemplate
		# re-applies the same cancel on restore as a safety net.
		player.cancel_movement_and_abilities()
		player.process_mode = Node.PROCESS_MODE_DISABLED
	VfxManager.clear_temporary_effects()
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


## Loads the dungeon ProgressionState prepares for the current dungeon level:
## its boss arena when one is registered, otherwise a regular dungeon matching
## the planned encounter.
func load_next_level(args: Dictionary = {}) -> void:
	var dungeon: DungeonResource = ProgressionState.prepare_next_encounter()
	if dungeon == null or dungeon.scene == null:
		push_error("SceneTransition: no dungeon to load for dungeon level %d." % ProgressionState.dungeon_level)
		return
	load_scene_path(dungeon.scene.resource_path, args)
