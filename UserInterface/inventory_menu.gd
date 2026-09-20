## Inventory panel listing the player's equipped gear. Selecting an entry
## shows its details in the embedded INSPECT-mode UpgradeIcon card.
class_name InventoryMenu
extends PanelContainer

## Unique-name references so the panel survives scene reparenting.
@onready var gear_list: ItemList = %GearList
@onready var details_card: UpgradeIcon = %DetailsCard

## Matches BBCode tags so gear titles render as plain text in the list.
var _tag_regex: RegEx = RegEx.create_from_string("\\[[^\\]]*\\]")


func _ready() -> void:
	gear_list.item_selected.connect(_on_gear_selected)
	refresh()


## Rebuilds the gear list from the player in the tree. Keeps the previous
## selection when that gear is still equipped, otherwise shows the first entry.
func refresh() -> void:
	var selected_gear: GearItemResource = get_selected_gear()
	gear_list.clear()
	for gear: GearItemResource in _read_equipped_gear():
		var idx: int = gear_list.add_item(_display_name(gear), gear.icon)
		gear_list.set_item_metadata(idx, gear)
	if gear_list.item_count == 0:
		var empty_idx: int = gear_list.add_item("No gear equipped")
		gear_list.set_item_disabled(empty_idx, true)
		gear_list.set_item_metadata(empty_idx, null)
		details_card.visible = false
		return
	details_card.visible = true
	var restore_idx: int = _find_gear_index(selected_gear)
	var show_idx: int = restore_idx if restore_idx >= 0 else 0
	gear_list.select(show_idx)
	_show_details(show_idx)


## Returns the currently selected gear resource, or null when the selection
## is empty or points at the "no gear" placeholder row.
func get_selected_gear() -> GearItemResource:
	var selected: PackedInt32Array = gear_list.get_selected_items()
	if selected.is_empty():
		return null
	return gear_list.get_item_metadata(selected[0]) as GearItemResource


## Reads the equipped gear of the player in the tree. Empty when no player
## with equipment is present (e.g. menus shown without an active run).
func _read_equipped_gear() -> Array[GearItemResource]:
	var result: Array[GearItemResource] = []
	var player: Character = get_tree().get_first_node_in_group("player") as Character
	if player == null or player.equipment_component == null:
		return result
	for gear: GearItemResource in player.equipment_component.equipped_gear:
		if gear != null:
			result.append(gear)
	return result


## Shows the selected list entry's gear in the details card.
func _on_gear_selected(index: int) -> void:
	_show_details(index)


## Shows one list row's gear in the details card. Ignores placeholder rows.
func _show_details(index: int) -> void:
	if index < 0 or index >= gear_list.item_count:
		return
	var gear: GearItemResource = gear_list.get_item_metadata(index) as GearItemResource
	if gear == null:
		return
	details_card.visible = true
	details_card.set_item_resource(gear)


## Finds a gear resource in the current list, or -1 when absent.
func _find_gear_index(gear: GearItemResource) -> int:
	if gear == null:
		return -1
	for idx: int in gear_list.item_count:
		if gear_list.get_item_metadata(idx) as GearItemResource == gear:
			return idx
	return -1


## Renders a gear title as plain list text (titles carry BBCode effects).
func _display_name(gear: GearItemResource) -> String:
	var plain: String = _tag_regex.sub(gear.title.strip_edges(), "", true).strip_edges()
	if plain.is_empty():
		if not gear.id.is_empty():
			return String(gear.id)
		return "Unnamed gear"
	return plain
