class_name PlayerDash
extends PlayerState

## State we'll go to after dash timer is finished
@export var running_state: PlayerRun

@onready var dash_duration: Timer = $DashDuration

var direction: Vector3

func enter(_previous_state_path: String, _data := {}) -> void:
	direction = _data.direction
	player.velocity = direction * player.dash_speed
	player.dash_cooldown.start()
	dash_duration.start()
	player.mannequin_animation_tree.change_immediate("DodgeForward")
	
func physics_update(_delta: float) -> void:
	if dash_duration.is_stopped():
		finished.emit(running_state.name)
	player.move_and_slide()
