## Global UI service, registered as the `UI` autoload (script) in `project.godot`.
## Access from anywhere via `UI`, e.g. `UI.toggle_fullscreen()`.
##
## Unique responsibilities:
## - Fullscreen state and toggling (`is_fullscreen`, `go_fullscreen`, `toggle_fullscreen`).
## - Global UI input events (e.g. the `ui_toggle_fullscreen` action in `_unhandled_key_input`).
## - Global UI state and menu flow (opening/closing menus, tracking which menu is
##   open). No menu flow exists yet; new menu logic belongs here, not in levels
##   or character scripts.
## It owns `PROCESS_MODE_ALWAYS` so UI input keeps working while the tree is paused.
extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	go_fullscreen()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_toggle_fullscreen"):
		toggle_fullscreen()


## Returns true when the window is currently in any fullscreen mode.
func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN \
		or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


## Switches the window to exclusive fullscreen, unless the game is embedded in the editor.
func go_fullscreen() -> void:
	if Engine.is_embedded_in_editor() or get_window().is_embedded():
		print("Cannot toggle fullscreen while game is embedded in the editor. Disable 'Game Embed Mode' in Editor Settings -> Run -> Window Placement.")
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


## Toggles the window between fullscreen and windowed mode, unless embedded in the editor.
func toggle_fullscreen() -> void:
	if Engine.is_embedded_in_editor() or get_window().is_embedded():
		print("Cannot toggle fullscreen while game is embedded in the editor. Disable 'Game Embed Mode' in Editor Settings -> Run -> Window Placement.")
		return
	if is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		go_fullscreen()
