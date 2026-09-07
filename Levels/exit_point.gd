class_name ExitPoint
extends Node3D

var locked: bool = true


func _ready() -> void:
	visible = false


func unlock() -> void:
	visible = true
	locked = false


func _on_area_3d_body_entered(body: Node3D) -> void:
	if locked:
		return
	if body is Player:
		locked = true
		GlobalVars.finish_level()
		get_tree().change_scene_to_file.call_deferred("res://Levels/LevelTemplate.tscn")

