class_name ExitPoint
extends Node3D

@export_file("*.tscn") var next_scene_path: String = ""

var next_level_path: String:
	get:
		return next_scene_path
	set(value):
		next_scene_path = value

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
		if not next_scene_path.is_empty():
			SceneTransition.load_scene_path(next_scene_path)
		else:
			SceneTransition.load_scene_path("res://UserInterface/UpgradeShop.tscn")
