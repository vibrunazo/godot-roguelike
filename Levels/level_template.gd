class_name LevelTemplate
extends Node3D

@onready var player: Character = $Player


func _ready() -> void:
	# The level's own, fresh player becomes the run's player.
	ProgressionState.bind_player(player)
	# Show the persistent HUD overlay. The HUD is owned by the UI autoload
	# (not this scene) so the same instance, including its gold count, stays
	# on screen across level and shop transitions.
	UI.show_hud()
	UI.show_level_title(ProgressionState.dungeon_level)
