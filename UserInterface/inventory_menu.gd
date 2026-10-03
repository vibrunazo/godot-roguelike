## The inventory screen, opened from the pause menu's Inventory button: the
## player's equipped gear (spell books included) in an ItemListPanel, the
## selected item in an ItemDetailPanel, and a CharacterStatsPanel previewing
## what the selected item changes. A small Back button (or the pause/cancel
## action, handled by the host) returns to the pause menu. Purely UI; it
## keeps processing while the tree is paused with its host.
class_name InventoryMenu
extends Control

## Emitted when the Back button is pressed.
signal back_requested

## Gear list column.
@onready var list_panel: ItemListPanel = %InventoryPanel
## Selected item details column.
@onready var detail_panel: ItemDetailPanel = %ItemDetailPanel
## Character stats column, previewing the selected item.
@onready var stats_panel: CharacterStatsPanel = %CharacterStatsPanel
## Returns to the pause menu.
@onready var back_button: Button = %BackButton


func _ready() -> void:
	list_panel.gear_selected.connect(_on_gear_selected)
	back_button.pressed.connect(back_requested.emit)
	refresh()


## Rebuilds every column from the player in the tree.
func refresh() -> void:
	list_panel.refresh()
	stats_panel.refresh()
	_show_selected_gear()


## The gear selected in the list, or null.
func get_selected_gear() -> GearItemResource:
	return list_panel.get_selected_gear()


## Gives keyboard focus to the list (Back when it is empty).
func focus_default() -> void:
	if list_panel.get_selected_gear() != null:
		list_panel.gear_list.grab_focus()
	else:
		back_button.grab_focus()


func _on_gear_selected(_index: int) -> void:
	_show_selected_gear()


## Shows the selected gear in the details column and previews its stat
## contribution as arrows in the stats column.
func _show_selected_gear() -> void:
	var gear: GearItemResource = list_panel.get_selected_gear()
	detail_panel.set_item(gear)
	stats_panel.set_selected_item(gear)
