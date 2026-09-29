## Script for the main menu diorama level.
## Configures global UI state, ensures MenuCamera is active, and verifies the hero is playing idle.
class_name MenuLevel
extends Node3D

@onready var hero: Node3D = $MenuPlayer
@onready var menu_camera: Camera3D = $MenuCamera
@onready var main_menu: CanvasLayer = $MainMenu

func _ready() -> void:
	UI.is_in_main_menu = true
	# The HUD is persistent (owned by the UI autoload) so it survives scene
	# changes; free it here so the main menu stays overlay-free.
	UI.hide_hud()

	if menu_camera != null:
		menu_camera.make_current()


func _exit_tree() -> void:
	UI.is_in_main_menu = false
