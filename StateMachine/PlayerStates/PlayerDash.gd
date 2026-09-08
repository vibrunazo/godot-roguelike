class_name PlayerDash
extends PlayerState

## State we'll go to after dash timer is finished
@export var running_state: PlayerRun

@onready var dash_duration: Timer = $DashDuration

var direction: Vector3

func enter(_previous_state_path: String, _data := {}) -> void:
	if player.dash_audio != null:
		player.dash_audio.play()
	direction = _data.direction
	player.velocity = direction * player.dash_speed
	player.dash_cooldown.start()
	dash_duration.start()
	player.mannequin_animation_tree.change_immediate("DodgeForward")
	var move_dir: Vector3 = player.get_movement_direction()
	if not move_dir.is_zero_approx():
		player.dash_root.look_at(player.global_position + move_dir)
	elif not direction.is_zero_approx():
		player.dash_root.look_at(player.global_position + direction)
	player.dash_animation_player.stop()
	player.dash_animation_player.play("dash")
	
func physics_update(_delta: float) -> void:
	if dash_duration.is_stopped():
		finished.emit(running_state.name)
	player.move_and_slide()
