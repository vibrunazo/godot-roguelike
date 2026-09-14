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


## Emitted when the game pause state changes.
signal pause_state_changed(is_paused: bool)


## Whether UI overlays (e.g. level title banners, HUD overlays) are allowed to display.
var overlays_enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Auto-detect CLI capture or no-ui flags
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--hide-ui" or arg == "--no-ui":
			overlays_enabled = false
			break
	go_fullscreen()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_toggle_fullscreen"):
		toggle_fullscreen()
	elif event.is_action_pressed("ui_pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()


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


const LEVEL_TITLE_OVERLAY_SCENE: PackedScene = preload("res://UserInterface/level_title_overlay.tscn")
const DEFAULT_PAUSE_MENU_SCENE: PackedScene = preload("res://UserInterface/pause_menu.tscn")

var _current_level_overlay: LevelTitleOverlay = null
var _current_pause_menu: PauseMenu = null

## Pause menu scene override. When null, uses GlobalVars.pause_menu_scene or DEFAULT_PAUSE_MENU_SCENE.
@export var pause_menu_scene: PackedScene = null


## Globally enables or disables UI overlays. When set to false, existing overlays are freed immediately.
func set_overlays_visible(p_visible: bool) -> void:
	overlays_enabled = p_visible
	if not overlays_enabled and _current_level_overlay != null and is_instance_valid(_current_level_overlay):
		_current_level_overlay.queue_free()
		_current_level_overlay = null


## Displays a text overlay on screen indicating the current level number.
func show_level_title(level_number: int, duration: float = 2.0) -> LevelTitleOverlay:
	if not overlays_enabled:
		return null

	if _current_level_overlay != null and is_instance_valid(_current_level_overlay):
		_current_level_overlay.queue_free()
		_current_level_overlay = null

	var overlay: LevelTitleOverlay = LEVEL_TITLE_OVERLAY_SCENE.instantiate() as LevelTitleOverlay
	add_child(overlay)
	_current_level_overlay = overlay
	overlay.display_level(level_number, duration)
	return overlay


## Returns true if the scene tree is currently paused.
func is_paused() -> bool:
	return get_tree().paused


## Pauses the game tree and displays the pause menu overlay.
func pause_game() -> void:
	if is_paused():
		return
	get_tree().paused = true
	if _current_pause_menu != null and is_instance_valid(_current_pause_menu):
		_current_pause_menu.queue_free()
		_current_pause_menu = null

	var scene: PackedScene = pause_menu_scene
	if scene == null and GlobalVars != null and GlobalVars.pause_menu_scene != null:
		scene = GlobalVars.pause_menu_scene
	if scene == null:
		scene = DEFAULT_PAUSE_MENU_SCENE

	var menu: PauseMenu = scene.instantiate() as PauseMenu
	add_child(menu)
	_current_pause_menu = menu
	pause_state_changed.emit(true)


## Unpauses the game tree and removes the pause menu overlay.
func resume_game() -> void:
	get_tree().paused = false
	if _current_pause_menu != null and is_instance_valid(_current_pause_menu):
		_current_pause_menu.queue_free()
		_current_pause_menu = null
	pause_state_changed.emit(false)


## Toggles pause state between paused and unpaused.
func toggle_pause() -> void:
	if is_paused():
		resume_game()
	else:
		pause_game()
