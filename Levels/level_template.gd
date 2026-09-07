class_name LevelTemplate
extends Node3D

@onready var player: Player = $Player


func _ready() -> void:
	if SceneTransition.player_cache:
		var old_player_position: Vector3 = player.global_position
		player.queue_free()
		SceneTransition.player_cache.reparent(self)
		SceneTransition.player_cache.global_position = old_player_position
		SceneTransition.player_cache.process_mode = Node.PROCESS_MODE_INHERIT
		player = SceneTransition.player_cache
