class_name PlayerDash
extends PlayerState

## State we'll go to after dash timer is finished
@export var running_state: PlayerRun

@onready var dash_duration: Timer = $DashDuration

var direction: Vector3

func enter(_previous_state_path: String, _data := {}) -> void:
	if player.dash_audio != null:
		player.dash_audio.play()
	direction = _data.get("direction", Vector3.ZERO)
	if direction.is_zero_approx():
		direction = player.player_root.global_basis.z.normalized()
		if direction.is_zero_approx():
			direction = Vector3.FORWARD
	player.velocity = direction * player.dash_speed
	player.dash_cooldown.start()
	dash_duration.start()
	player.mannequin_animation_tree.change_immediate("DodgeForward")
	if not direction.is_zero_approx():
		player.dash_root.look_at(player.global_position + direction)
	player.dash_animation_player.stop()
	player.dash_animation_player.play("dash")
	
func physics_update(_delta: float) -> void:
	if dash_duration.is_stopped():
		finished.emit(running_state.name)
	player.move_and_slide()
