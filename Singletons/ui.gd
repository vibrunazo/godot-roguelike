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


## Damage dealt to each enemy by the `debug_kill` action.
const DEBUG_KILL_DAMAGE: float = 50.0

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
	if overlays_enabled:
		go_fullscreen()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_toggle_fullscreen"):
		toggle_fullscreen()
	elif event.is_action_pressed("ui_pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_kill"):
		debug_kill_enemies()
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
const HUD_SCENE: PackedScene = preload("res://UserInterface/hud.tscn")
const HUD = preload("res://UserInterface/hud.gd")

var _current_level_overlay: LevelTitleOverlay = null
var _current_pause_menu: PauseMenu = null
var _current_hud: HUD = null
## True while the game-over screen owns the pause state. The pause toggle is
## disabled then: there is nothing to resume to, only restart or quit.
var _is_game_over: bool = false
## True while in the main menu, disabling the in-game pause toggle.
var is_in_main_menu: bool = false

## Pause menu scene override. When null, uses GlobalVars.pause_menu_scene or DEFAULT_PAUSE_MENU_SCENE.
@export var pause_menu_scene: PackedScene = null


## Globally enables or disables UI overlays. When set to false, existing overlays are freed immediately.
func set_overlays_visible(p_visible: bool) -> void:
	overlays_enabled = p_visible
	if not overlays_enabled:
		if _current_level_overlay != null and is_instance_valid(_current_level_overlay):
			_current_level_overlay.queue_free()
			_current_level_overlay = null
		if _current_hud != null and is_instance_valid(_current_hud):
			_current_hud.queue_free()
			_current_hud = null
	if is_inside_tree():
		for hud: Node in get_tree().get_nodes_in_group("hud"):
			if hud is CanvasLayer:
				(hud as CanvasLayer).visible = overlays_enabled


## Displays the HUD overlay on screen.
func show_hud() -> HUD:
	if not overlays_enabled:
		return null
	if _current_hud != null and is_instance_valid(_current_hud):
		return _current_hud
	var hud: HUD = HUD_SCENE.instantiate() as HUD
	add_child(hud)
	_current_hud = hud
	return hud


## Hides and removes the current HUD overlay.
func hide_hud() -> void:
	if _current_hud != null and is_instance_valid(_current_hud):
		_current_hud.queue_free()
		_current_hud = null
	if is_inside_tree():
		for hud: Node in get_tree().get_nodes_in_group("hud"):
			if hud is CanvasLayer:
				(hud as CanvasLayer).visible = false


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

	var menu: PauseMenu = _spawn_menu()
	add_child(menu)
	_current_pause_menu = menu
	pause_state_changed.emit(true)


## Resolves the configured pause menu scene and instantiates it. Callers set
## per-use-case exports before adding it to the tree (its _ready applies them).
func _spawn_menu() -> PauseMenu:
	var scene: PackedScene = pause_menu_scene
	if scene == null and GlobalVars != null and GlobalVars.pause_menu_scene != null:
		scene = GlobalVars.pause_menu_scene
	if scene == null:
		scene = DEFAULT_PAUSE_MENU_SCENE
	return scene.instantiate() as PauseMenu


## Unpauses the game tree and removes the pause menu overlay.
func resume_game() -> void:
	get_tree().paused = false
	_is_game_over = false
	if _current_pause_menu != null and is_instance_valid(_current_pause_menu):
		_current_pause_menu.queue_free()
		_current_pause_menu = null
	pause_state_changed.emit(false)


## Pauses the game tree and displays the game-over screen: the pause menu
## scene with a red backdrop, a "GAME OVER" title, and no resume button.
## The pause toggle stays disabled until restart or quit.
func show_game_over() -> void:
	if _current_pause_menu != null and is_instance_valid(_current_pause_menu):
		_current_pause_menu.queue_free()
		_current_pause_menu = null
	get_tree().paused = true
	_is_game_over = true
	var menu: PauseMenu = _spawn_menu()
	menu.title_text = "GAME OVER"
	menu.title_color = Color(0.85, 0.2, 0.2)
	menu.backdrop_color = Color(0.25, 0.03, 0.03, 0.78)
	menu.show_resume_button = false
	add_child(menu)
	_current_pause_menu = menu
	pause_state_changed.emit(true)


## Toggles pause state between paused and unpaused. Does nothing on the
## game-over screen or in the main menu, where resume is unavailable.
func toggle_pause() -> void:
	if _is_game_over or is_in_main_menu:
		return
	if is_paused():
		resume_game()
	else:
		pause_game()


## Deals damage to every living enemy in the "enemy" group. Routes hits
## through Hurtbox.receive_hit() so damage numbers, hit audio, and stun
## reactions fire exactly like combat hits; falls back to direct pool
## damage only when an enemy has no wired hurtbox.
func debug_kill_enemies(damage: float = DEBUG_KILL_DAMAGE) -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	for node: Node in enemies:
		if not (node is Character):
			continue
		var enemy: Character = node as Character
		if not enemy.is_alive():
			continue
		var hurtbox: Hurtbox = enemy.hurtbox
		if hurtbox == null or not is_instance_valid(hurtbox):
			hurtbox = enemy.get_node_or_null("Hurtbox") as Hurtbox
		if hurtbox != null and is_instance_valid(hurtbox):
			hurtbox.receive_hit(damage, Vector3.ZERO)
		elif enemy.attribute_component != null and is_instance_valid(enemy.attribute_component):
			enemy.attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, damage)
