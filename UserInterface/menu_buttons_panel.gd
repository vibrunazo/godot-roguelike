## Reusable menu options column for the pause menu concept layout.
## Hosts the six concept buttons (Resume, Restart Run, Controls, Fullscreen,
## Exit to Main Menu, Quit Game) and owns their behaviors except resume and
## restart, which are forwarded so PauseMenu (and its tests) stay the authority
## on pausing and run resets. Other panels and future menus can instance this
## column directly.
class_name MenuButtonsPanel
extends VBoxContainer

## Emitted when resume is requested (button or host forwarding).
signal resume_requested
## Emitted when a run restart is requested.
signal restart_requested
## Emitted when the controls dialog is opened.
signal controls_requested
## Emitted when fullscreen is toggled.
signal fullscreen_toggled
## Emitted when exiting to the main menu.
signal exit_to_menu_requested
## Emitted when quitting the game.
signal quit_requested

## Hides the resume button for terminal menus like game over.
@export var show_resume_button: bool = true:
	set(value):
		show_resume_button = value
		_apply_resume_visibility()

@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var controls_button: Button = %ControlsButton
@onready var fullscreen_button: Button = %FullscreenButton
@onready var exit_menu_button: Button = %ExitMenuButton
@onready var quit_button: Button = %QuitButton
@onready var controls_dialog: AcceptDialog = %ControlsDialog


func _ready() -> void:
	_apply_resume_visibility()
	if resume_button != null:
		resume_button.pressed.connect(_on_resume_pressed)
	if restart_button != null:
		restart_button.pressed.connect(_on_restart_pressed)
	if controls_button != null:
		controls_button.pressed.connect(_on_controls_pressed)
	if fullscreen_button != null:
		fullscreen_button.pressed.connect(_on_fullscreen_pressed)
		_update_fullscreen_button_text()
	if exit_menu_button != null:
		exit_menu_button.pressed.connect(_on_exit_menu_pressed)
	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)
	if controls_dialog != null:
		controls_dialog.process_mode = Node.PROCESS_MODE_ALWAYS


## Gives keyboard focus to resume (or restart when resume is hidden).
func focus_default() -> void:
	if show_resume_button and resume_button != null:
		resume_button.grab_focus()
	elif restart_button != null:
		restart_button.grab_focus()


## Toggles window fullscreen mode via the global UI service and updates button text.
func toggle_fullscreen() -> void:
	UI.toggle_fullscreen()
	_update_fullscreen_button_text()
	fullscreen_toggled.emit()


## Shows the controls help dialog.
func show_controls() -> void:
	controls_requested.emit()
	if controls_dialog != null:
		controls_dialog.popup_centered()


## Unpauses, resets the run, and returns to the main menu diorama level.
func exit_to_main_menu() -> void:
	exit_to_menu_requested.emit()
	UI.resume_game()
	ProgressionState.reset_run()
	if SceneTransition != null:
		SceneTransition.player_cache = null
		SceneTransition.load_scene_path("res://Levels/menu_level.tscn")


## Quits the application cleanly.
func quit_game() -> void:
	quit_requested.emit()
	get_tree().quit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_controls_pressed() -> void:
	show_controls()


func _on_fullscreen_pressed() -> void:
	toggle_fullscreen()


func _on_exit_menu_pressed() -> void:
	exit_to_main_menu()


func _on_quit_pressed() -> void:
	quit_game()


func _apply_resume_visibility() -> void:
	if resume_button == null or not is_node_ready():
		return
	resume_button.visible = show_resume_button


func _update_fullscreen_button_text() -> void:
	if fullscreen_button == null:
		return
	if UI.is_fullscreen():
		fullscreen_button.text = "Fullscreen: ON"
	else:
		fullscreen_button.text = "Fullscreen: OFF"
