## Pause menu overlay presented when pausing gameplay. Doubles as the game-over
## screen: UI.show_game_over() reuses this scene with a red backdrop, a
## "GAME OVER" title, and the resume button hidden.
## Two screens share the overlay: the pause screen (title and the
## MenuButtonsPanel) and the InventoryMenu, opened by the Inventory button.
## Only one shows at a time; the inventory's Back button, or the pause or
## cancel action, returns to the pause screen. The run gold counter lives only
## in the HUD scene, which stays visible under this menu.
class_name PauseMenu
extends CanvasLayer

## Emitted when the resume button or pause action is triggered from this menu.
signal resume_requested

## Emitted when the restart button is triggered.
signal restart_requested

## Title text rendered with the wave BBCode effect. "PAUSED" for the pause
## menu, "GAME OVER" for the game-over screen.
@export var title_text: String = "PAUSED"
## Title accent color. Concept gold by default; game over uses red.
@export var title_color: Color = Color(0.83, 0.69, 0.37)
## Full-screen backdrop tint. Dark blue by default; game over uses dark red.
@export var backdrop_color: Color = Color(0.039, 0.047, 0.078, 0.745)
## Hides the resume button (and focuses restart instead) for terminal menus
## like game over, where there is nothing to resume to.
@export var show_resume_button: bool = true

@onready var title_label: RichTextLabel = %Title
@onready var backdrop_rect: ColorRect = %Backdrop
## The pause screen: title and menu buttons.
@onready var pause_screen: Control = %PauseScreen
## Menu buttons of the pause screen.
@onready var buttons_panel: MenuButtonsPanel = %MenuButtonsPanel
## The inventory screen, hidden until the Inventory button opens it.
@onready var inventory_menu: InventoryMenu = %InventoryMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_apply_configuration()

	buttons_panel.resume_requested.connect(_on_panel_resume)
	buttons_panel.restart_requested.connect(_on_panel_restart)
	buttons_panel.inventory_requested.connect(open_inventory)
	inventory_menu.back_requested.connect(close_inventory)
	_show_pause_screen()
	buttons_panel.focus_default()


## While the inventory shows, the pause and cancel actions go back to the
## pause screen instead of resuming (this menu sees input before the UI
## autoload, its parent).
func _unhandled_input(event: InputEvent) -> void:
	if is_inventory_open() and (event.is_action_pressed(&"ui_pause") or event.is_action_pressed(&"ui_cancel")):
		close_inventory()
		get_viewport().set_input_as_handled()


## Applies the exported title, backdrop, and resume-button configuration to
## the scene nodes. Runs on entry so UI can set the exports per use-case
## (pause vs game over) between instantiate and add_child.
func _apply_configuration() -> void:
	title_label.text = "[center][wave amp=25.0 freq=3.0][color=#%s]%s[/color][/wave][/center]" % [title_color.to_html(false), title_text]
	backdrop_rect.color = backdrop_color
	buttons_panel.show_resume_button = show_resume_button


## Shows the inventory screen in place of the pause screen.
func open_inventory() -> void:
	pause_screen.visible = false
	inventory_menu.visible = true
	inventory_menu.refresh()
	inventory_menu.focus_default()


## Returns from the inventory screen to the pause screen, focusing the
## Inventory button it was opened from.
func close_inventory() -> void:
	_show_pause_screen()
	buttons_panel.inventory_button.grab_focus()


func _show_pause_screen() -> void:
	inventory_menu.visible = false
	pause_screen.visible = true


## Whether the inventory screen is showing.
func is_inventory_open() -> bool:
	return inventory_menu.visible


## Closes the pause menu and resumes the game.
func resume() -> void:
	resume_requested.emit()
	UI.resume_game()


## Unpauses, resets the run progression and loads the new run's first level,
## as the main menu's Start does: a dungeon picked for the first encounter,
## never the level the run ended in (dying to a boss restarts at level 1, not
## in its arena).
func restart_run() -> void:
	restart_requested.emit()
	UI.resume_game()
	ProgressionState.reset_run()
	SceneTransition.load_next_level()


## Toggles window fullscreen mode via the buttons column.
func toggle_fullscreen() -> void:
	buttons_panel.toggle_fullscreen()


## Quits the application cleanly.
func quit_game() -> void:
	get_tree().quit()


func _on_panel_resume() -> void:
	resume()


func _on_panel_restart() -> void:
	restart_run()
