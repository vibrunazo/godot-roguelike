class_name DamageNumber
extends Node2D

@onready var label: Label = $Label

var target_position: Vector3 = Vector3.ZERO


func set_damage_text(amount: float) -> void:
	if not is_inside_tree():
		await ready
	label.text = "%d" % amount


func _physics_process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return
	position = camera.unproject_position(target_position)
