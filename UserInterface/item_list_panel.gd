## Reusable inventory list column for the pause menu concept layout.
## Shows equipped gear as a selectable list with stack counts (e.g. "Laser sword x2").
## Used by PauseMenu (column 1) and InventoryMenu; selection is forwarded via
## gear_selected so hosts can drive a details panel.
class_name ItemListPanel
extends VBoxContainer

## Emitted when a list row is selected (real ItemList.item_selected path).
signal gear_selected(index: int)

## Selectable gear rows.
@onready var gear_list: ItemList = %GearList

## Matches BBCode tags so gear titles render as plain text in the list.
var _tag_regex: RegEx = RegEx.create_from_string("\\[[^\\]]*\\]")


func _ready() -> void:
	if gear_list != null and not gear_list.item_selected.is_connected(_on_item_selected):
		gear_list.item_selected.connect(_on_item_selected)
	refresh()


## Rebuilds the list from the player in the tree. Keeps the previous selection
## when that gear is still equipped, otherwise shows the first entry.
func refresh() -> void:
	if gear_list == null:
		return
	var selected_gear: GearItemResource = get_selected_gear()
	gear_list.clear()
	var equipment: EquipmentComponent = _read_player_equipment()
	for gear: GearItemResource in _read_equipped_gear(equipment):
		var idx: int = gear_list.add_item(_display_name(gear, equipment), gear.icon)
		gear_list.set_item_metadata(idx, gear)
	if gear_list.item_count == 0:
		var empty_idx: int = gear_list.add_item("No gear equipped")
		gear_list.set_item_disabled(empty_idx, true)
		gear_list.set_item_metadata(empty_idx, null)
		return
	var restore_idx: int = _find_gear_index(selected_gear)
	var show_idx: int = restore_idx if restore_idx >= 0 else 0
	gear_list.select(show_idx)
	_update_bullets(show_idx)
	gear_selected.emit(show_idx)


## Returns the currently selected gear resource, or null when the selection
## is empty or points at the "no gear" placeholder row.
func get_selected_gear() -> GearItemResource:
	if gear_list == null:
		return null
	var selected: PackedInt32Array = gear_list.get_selected_items()
	if selected.is_empty():
		return null
	return gear_list.get_item_metadata(selected[0]) as GearItemResource


## Selects a row programmatically (mirrors a real click path for tests).
func select_row(index: int) -> void:
	if gear_list == null:
		return
	if index < 0 or index >= gear_list.item_count:
		return
	gear_list.select(index)
	_update_bullets(index)
	gear_list.item_selected.emit(index)


## Returns the player-facing equipment tracker, or null when no run with
## equipment is active (e.g. menus shown without a player in the tree).
func _read_player_equipment() -> EquipmentComponent:
	if not is_inside_tree():
		return null
	var player: Character = get_tree().get_first_node_in_group("player") as Character
	if player == null:
		return null
	return player.equipment_component


## Reads the equipped gear from a tracker. Empty when no tracker is present.
func _read_equipped_gear(equipment: EquipmentComponent) -> Array[GearItemResource]:
	var result: Array[GearItemResource] = []
	if equipment == null:
		return result
	for gear: GearItemResource in equipment.equipped_gear:
		if gear != null:
			result.append(gear)
	return result


func _on_item_selected(index: int) -> void:
	_update_bullets(index)
	gear_selected.emit(index)


## Rewrites row texts so the selected row reads plain while every other row
## carries a bullet prefix, matching the pause concept layout.
func _update_bullets(selected_idx: int) -> void:
	if gear_list == null:
		return
	var equipment: EquipmentComponent = _read_player_equipment()
	for idx: int in gear_list.item_count:
		var gear: GearItemResource = gear_list.get_item_metadata(idx) as GearItemResource
		if gear == null:
			continue
		var base: String = _display_name(gear, equipment)
		if idx == selected_idx:
			gear_list.set_item_text(idx, base)
		else:
			gear_list.set_item_text(idx, "• " + base)


## Finds a gear resource in the current list, or -1 when absent.
func _find_gear_index(gear: GearItemResource) -> int:
	if gear == null or gear_list == null:
		return -1
	for idx: int in gear_list.item_count:
		if gear_list.get_item_metadata(idx) as GearItemResource == gear:
			return idx
	return -1


## Renders a gear row as plain list text (titles carry BBCode effects),
## suffixed with the owned stack count, e.g. "Laser sword x2". Single items
## show no suffix.
func _display_name(gear: GearItemResource, equipment: EquipmentComponent) -> String:
	var plain: String = _tag_regex.sub(gear.title.strip_edges(), "", true).strip_edges()
	if plain.is_empty():
		if not gear.id.is_empty():
			plain = String(gear.id)
		else:
			plain = "Unnamed gear"
	if equipment != null and equipment.get_purchase_count(gear) > 1:
		plain += " x%d" % equipment.get_purchase_count(gear)
	return plain
