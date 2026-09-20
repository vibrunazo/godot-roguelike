## Pause menu overlay presented when pausing gameplay. Doubles as the game-over
## screen: UI.show_game_over() reuses this scene with a red backdrop, a
## "GAME OVER" title, and the resume button hidden.
## Concept layout: gold PAUSED title and one outer panel with four reusable
## columns - ItemListPanel (inventory), ItemDetailPanel (item details),
## CharacterStatsPanel (character stats), MenuButtonsPanel (menu options).
## Each column is a standalone scene reusable elsewhere. The run gold counter
## lives only in the HUD scene, which stays visible under this menu.
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
## Inventory list column (concept column 1).
@onready var list_panel: ItemListPanel = %InventoryPanel
## Item details column (concept column 2).
@onready var detail_panel: ItemDetailPanel = %ItemDetailPanel
## Character stats column (concept column 3).
@onready var stats_panel: CharacterStatsPanel = %CharacterStatsPanel
## Menu buttons column (concept column 4).
@onready var buttons_panel: MenuButtonsPanel = %MenuButtonsPanel

## Resume button forwarded from the buttons column (kept for test compatibility).
var resume_button: Button:
	get:
		if buttons_panel != null and is_instance_valid(buttons_panel):
			return buttons_panel.resume_button
		return null
## Restart button forwarded from the buttons column.
var restart_button: Button:
	get:
		if buttons_panel != null and is_instance_valid(buttons_panel):
			return buttons_panel.restart_button
		return null
## Controls button forwarded from the buttons column.
var controls_button: Button:
	get:
		if buttons_panel != null and is_instance_valid(buttons_panel):
			return buttons_panel.controls_button
		return null
## Fullscreen button forwarded from the buttons column.
var fullscreen_button: Button:
	get:
		if buttons_panel != null and is_instance_valid(buttons_panel):
			return buttons_panel.fullscreen_button
		return null
## Exit-to-menu button forwarded from the buttons column.
var exit_menu_button: Button:
	get:
		if buttons_panel != null and is_instance_valid(buttons_panel):
			return buttons_panel.exit_menu_button
		return null
## Quit button forwarded from the buttons column.
var quit_button: Button:
	get:
		if buttons_panel != null and is_instance_valid(buttons_panel):
			return buttons_panel.quit_button
		return null
## Gear list forwarded from the inventory column.
var gear_list: ItemList:
	get:
		if list_panel != null and is_instance_valid(list_panel):
			return list_panel.gear_list
		return null
## Details card forwarded from the item details column.
var details_card: UpgradeIcon:
	get:
		if detail_panel != null and is_instance_valid(detail_panel):
			return detail_panel.details_card
		return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_apply_configuration()

	if list_panel != null:
		if not list_panel.gear_selected.is_connected(_on_list_gear_selected):
			list_panel.gear_selected.connect(_on_list_gear_selected)
		list_panel.refresh()
		_show_selected_details()
	if stats_panel != null:
		stats_panel.refresh()
	if buttons_panel != null:
		if not buttons_panel.resume_requested.is_connected(_on_panel_resume):
			buttons_panel.resume_requested.connect(_on_panel_resume)
		if not buttons_panel.restart_requested.is_connected(_on_panel_restart):
			buttons_panel.restart_requested.connect(_on_panel_restart)
		buttons_panel.focus_default()


## Applies the exported title, backdrop, and resume-button configuration to
## the scene nodes. Runs on entry so UI can set the exports per use-case
## (pause vs game over) between instantiate and add_child.
func _apply_configuration() -> void:
	if title_label != null:
		title_label.text = "[center][wave amp=25.0 freq=3.0][color=#%s]%s[/color][/wave][/center]" % [title_color.to_html(false), title_text]
	if backdrop_rect != null:
		backdrop_rect.color = backdrop_color
	if buttons_panel != null:
		buttons_panel.show_resume_button = show_resume_button


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


## Toggles window fullscreen mode via the buttons column.
func toggle_fullscreen() -> void:
	if buttons_panel != null:
		buttons_panel.toggle_fullscreen()


## Quits the application cleanly.
func quit_game() -> void:
	get_tree().quit()


func _on_panel_resume() -> void:
	resume()


func _on_panel_restart() -> void:
	restart_run()


func _on_list_gear_selected(_index: int) -> void:
	_show_selected_details()


## Shows the list column's selected gear in the details column.
func _show_selected_details() -> void:
	if list_panel == null or detail_panel == null:
		return
	detail_panel.set_item(list_panel.get_selected_gear())
