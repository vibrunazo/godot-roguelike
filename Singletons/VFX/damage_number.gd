class_name DamageNumber
extends Node2D

var target_position: Vector3 = Vector3.ZERO


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	position = camera.unproject_position(target_position)
