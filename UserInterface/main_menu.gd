## Main menu overlay presented at game startup.
## Displays the title, start run, fullscreen toggle, and game quit actions.
## Positioned to the right of the screen to showcase the 3D menu level on the left.
class_name MainMenu
extends CanvasLayer

## Emitted when the start game button is triggered.
signal start_requested

## Emitted when the quit button is triggered.
signal quit_requested

## Title text rendered with the wave BBCode effect at the top of the screen.
@export var title_text: String = "Tutorial Hell"
## Title accent color. Matches pause menu cyan accent.
@export var title_color: Color = Color(0.31, 0.66, 0.8)

@onready var title_label: RichTextLabel = %Title
@onready var start_button: Button = %StartButton
@onready var fullscreen_button: Button = %FullscreenButton
@onready var quit_button: Button = %QuitButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_apply_configuration()

	if start_button != null:
		start_button.pressed.connect(_on_start_pressed)
		start_button.grab_focus()
	if fullscreen_button != null:
		fullscreen_button.pressed.connect(_on_fullscreen_pressed)
		_update_fullscreen_button_text()
	if quit_button != null:
		quit_button.pressed.connect(_on_quit_pressed)


func _apply_configuration() -> void:
	if title_label != null:
		title_label.text = "[center][wave amp=25.0 freq=3.0][color=#%s]%s[/color][/wave][/center]" % [title_color.to_html(false), title_text]


## Begins a new run by resetting progression (including the run's player gear
## and health) and loading the first level.
func start_game() -> void:
	start_requested.emit()
	UI.is_in_main_menu = false
	ProgressionState.reset_run()
	SceneTransition.load_next_level()


## Toggles window fullscreen mode via the global UI service and updates button text.
func toggle_fullscreen() -> void:
	UI.toggle_fullscreen()
	_update_fullscreen_button_text()


## Quits the application cleanly.
func quit_game() -> void:
	quit_requested.emit()
	get_tree().quit()


func _on_start_pressed() -> void:
	start_game()


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
