# TODO: Autoloads should be separated into different global systems with different names and responsibilities, instead of a generic GlobalVars autoload with multiple responsibilities.
extends Node

const DIFFICULTY_CURVE: Curve = preload("res://Singletons/difficulty_curve.tres")

const UPGRADE_DAMAGE: PackedScene = preload("res://UserInterface/upgrade_damage.tscn")
const UPGRADE_HEALTH: PackedScene = preload("res://UserInterface/upgrade_health.tscn")
const UPGRADE_SPEED: PackedScene = preload("res://UserInterface/upgrade_speed.tscn")

var upgrades: Array[PackedScene] = [
	UPGRADE_DAMAGE,
	UPGRADE_HEALTH,
	UPGRADE_SPEED
]

var level: int = 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_toggle_fullscreen"):
		toggle_fullscreen()


func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN \
		or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func go_fullscreen() -> void:
	if Engine.is_embedded_in_editor() or get_window().is_embedded():
		print("Cannot toggle fullscreen while game is embedded in the editor. Disable 'Game Embed Mode' in Editor Settings -> Run -> Window Placement.")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func toggle_fullscreen() -> void:
	if Engine.is_embedded_in_editor() or get_window().is_embedded():
		print("Cannot toggle fullscreen while game is embedded in the editor. Disable 'Game Embed Mode' in Editor Settings -> Run -> Window Placement.")
		return
	if is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		go_fullscreen()


func finish_level() -> void:
	level += 1


func get_enemy_count() -> int:
	return int(floor(DIFFICULTY_CURVE.sample(float(level))))
