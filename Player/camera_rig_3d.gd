## Positions the player's camera rig independently from the player transform.
## The rig follows horizontal movement and upward movement, but never descends below its initial world Y.
## It is attached to CameraRoot in player.tscn; ShakeCamera3D remains a child for screen-shake offsets.
class_name CameraRig3D
extends Node3D

@onready var _target: Node3D = get_parent() as Node3D

var _initial_y: float = 0.0


## Detaches from the player's transform while preserving the rig's starting world position.
func _ready() -> void:
	var initial_position: Vector3 = global_position
	top_level = true
	global_position = initial_position
	_initial_y = initial_position.y


## Applies the player's horizontal position and any upward vertical position to the camera rig.
func _process(_delta: float) -> void:
	if _target == null:
		return
	var target_position: Vector3 = _target.global_position
	global_position = Vector3(
		target_position.x,
		maxf(_initial_y, target_position.y),
		target_position.z
	)
