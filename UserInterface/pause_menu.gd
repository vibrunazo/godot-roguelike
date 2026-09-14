## Pause menu overlay presented when pausing gameplay.
## Handles resume, restart run, fullscreen toggle, and game quit actions.
class_name PauseMenu
extends CanvasLayer

## Emitted when the resume button or pause action is triggered from this menu.
signal resume_requested

## Emitted when the restart button is triggered.
signal restart_requested

@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var fullscreen_button: Button = %FullscreenButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	if resume_button != null:
		resume_button.pressed.connect(_on_resume_pressed)
		resume_button.grab_focus()
	if restart_button != null:
		restart_button.pressed.connect(_on_restart_pressed)
	if fullscreen_button != null:
		fullscreen_button.pressed.connect(_on_fullscreen_pressed)
		_update_fullscreen_button_text()
	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)


## Closes the pause menu and resumes the game.
func resume() -> void:
	resume_requested.emit()
	UI.resume_game()


## Unpauses, resets the run progression, and reloads the current scene.
func restart_run() -> void:
	restart_requested.emit()
	UI.resume_game()
	ProgressionState.reset_run()
	get_tree().reload_current_scene()


## Toggles window fullscreen mode via the global UI service and updates button text.
func toggle_fullscreen() -> void:
	UI.toggle_fullscreen()
	_update_fullscreen_button_text()


## Quits the application cleanly.
func quit_game() -> void:
	get_tree().quit()


func _on_resume_pressed() -> void:
	resume()


func _on_restart_pressed() -> void:
	restart_run()


func _on_fullscreen_pressed() -> void:
	toggle_fullscreen()


func _on_quit_pressed() -> void:
	quit_game()


func _update_fullscreen_button_text() -> void:
	if fullscreen_button == null:
		return
	if UI.is_fullscreen():
		fullscreen_button.text = "Fullscreen: ON"
	else:
		fullscreen_button.text = "Fullscreen: OFF"
