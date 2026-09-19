class_name LevelTemplate
extends Node3D

@onready var player: Character = $Player


func _ready() -> void:
	if SceneTransition.player_cache:
		var old_player_position: Vector3 = player.global_position
		player.queue_free()
		SceneTransition.player_cache.reparent(self)
		SceneTransition.player_cache.global_position = old_player_position
		SceneTransition.player_cache.cancel_movement_and_abilities()
		SceneTransition.player_cache.process_mode = Node.PROCESS_MODE_INHERIT
		player = SceneTransition.player_cache

	var current_level: int = ProgressionState.dungeon_level if ProgressionState != null else 1
	if UI != null:
		# Show the persistent HUD overlay. The HUD is owned by the UI autoload
		# (not this scene) so the same instance — including its gold count —
		# stays on screen across level and shop transitions.
		UI.show_hud()
		UI.show_level_title(current_level)
