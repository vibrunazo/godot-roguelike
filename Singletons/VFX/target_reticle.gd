## Screen-space reticle ring tracking the player character's current_target.
## Follows the DamageNumber projection pattern (re-projects a 3D position via
## the active camera every physics frame). Owned exclusively by VfxManager as a
## single persistent instance for the player: enemies never spawn a reticle and
## no reticle position math runs for them.
class_name TargetReticle
extends Node2D

## 3D node the reticle follows. The reticle hides while null or freed.
var target: Node3D = null
## Vertical offset in meters above the target's origin.
@export var height_offset: float = 1.6


func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		visible = false
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(target.global_position):
		visible = false
		return
	visible = true
	position = camera.unproject_position(target.global_position + Vector3(0.0, height_offset, 0.0))
