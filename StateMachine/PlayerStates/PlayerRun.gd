class_name PlayerRun
extends PlayerState

@export var fall_state: PlayerState

func physics_update(_delta: float) -> void:
	core_movement(_delta, player.movement_speed)
	if player.get_movement_direction():
		player.mannequin_animation_tree.blend_target = 1.0
	else:
		player.mannequin_animation_tree.blend_target = -1.0
	if player.is_on_floor() == false:
		finished.emit(fall_state.name)
	player.move_and_slide()

func handle_input(_event: InputEvent) -> void:
	check_dash(_event)
	if _event.is_action_pressed("click"):
		finished.emit("PlayerAttack")
