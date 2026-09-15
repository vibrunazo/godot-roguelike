## Pause menu overlay presented when pausing gameplay. Doubles as the game-over
## screen: UI.show_game_over() reuses this scene with a red backdrop, a
## "GAME OVER" title, and the resume button hidden.
## Handles resume, restart run, fullscreen toggle, and game quit actions.
class_name PauseMenu
extends CanvasLayer

## Emitted when the resume button or pause action is triggered from this menu.
signal resume_requested

## Emitted when the restart button is triggered.
signal restart_requested

## Title text rendered with the wave BBCode effect. "PAUSED" for the pause
## menu, "GAME OVER" for the game-over screen.
@export var title_text: String = "PAUSED"
## Title accent color. Pause blue by default; game over uses red.
@export var title_color: Color = Color(0.31, 0.66, 0.8)
## Full-screen backdrop tint. Dark blue by default; game over uses dark red.
@export var backdrop_color: Color = Color(0.039, 0.047, 0.078, 0.745)
## Hides the resume button (and focuses restart instead) for terminal menus
## like game over, where there is nothing to resume to.
@export var show_resume_button: bool = true

@onready var title_label: RichTextLabel = %Title
@onready var backdrop_rect: ColorRect = %Backdrop
@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var fullscreen_button: Button = %FullscreenButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_apply_configuration()

	if resume_button != null:
		resume_button.pressed.connect(_on_resume_pressed)
	if restart_button != null:
		restart_button.pressed.connect(_on_restart_pressed)
	if show_resume_button and resume_button != null:
		resume_button.grab_focus()
	elif restart_button != null:
		restart_button.grab_focus()
	if fullscreen_button != null:
		fullscreen_button.pressed.connect(_on_fullscreen_pressed)
		_update_fullscreen_button_text()
	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)


## Applies the exported title, backdrop, and resume-button configuration to
## the scene nodes. Runs on entry so UI can set the exports per use-case
## (pause vs game over) between instantiate and add_child.
func _apply_configuration() -> void:
	if title_label != null:
		title_label.text = "[center][wave amp=25.0 freq=3.0][color=#%s]%s[/color][/wave][/center]" % [title_color.to_html(false), title_text]
	if backdrop_rect != null:
		backdrop_rect.color = backdrop_color
	if resume_button != null:
		resume_button.visible = show_resume_button


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
