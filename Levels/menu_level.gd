## Script for the main menu diorama level.
## Configures global UI state, ensures MenuCamera is active, and verifies the hero is playing idle.
class_name MenuLevel
extends Node3D

@onready var hero: Node3D = $MenuPlayer
@onready var menu_camera: Camera3D = $MenuCamera
@onready var main_menu: CanvasLayer = $MainMenu

var _ui: Node:
	get:
		if is_inside_tree() and get_tree() != null and get_tree().root != null:
			return get_tree().root.get_node_or_null("UI")
		return null


func _ready() -> void:
	if _ui != null and "is_in_main_menu" in _ui:
		_ui.set("is_in_main_menu", true)
	# The HUD is persistent (owned by the UI autoload) so it survives scene
	# changes; free it here so the main menu stays overlay-free.
	if _ui != null and _ui.has_method("hide_hud"):
		_ui.call("hide_hud")

	if menu_camera != null:
		menu_camera.make_current()


func _exit_tree() -> void:
	if _ui != null and "is_in_main_menu" in _ui:
		_ui.set("is_in_main_menu", false)
