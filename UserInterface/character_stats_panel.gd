## Reusable character stats column for the pause menu concept layout.
## Reads the live player AttributeComponent plus run progression and renders
## eight stat rows (level, pools, attack, defense, speed, attack speed, fire
## resistance). Refresh on ready, on show, and whenever the player's
## attributes change. When a gear item is selected via set_selected_item(),
## stat rows touched by its persistent effects preview the contribution as
## "Label: without -> with" (without excludes the item when it is equipped,
## otherwise the current value); untouched rows show their plain current value.
class_name CharacterStatsPanel
extends VBoxContainer

## Row labels in concept order.
@onready var level_row: RichTextLabel = %LevelRow
@onready var hp_row: RichTextLabel = %HpRow
@onready var mana_row: RichTextLabel = %ManaRow
@onready var attack_row: RichTextLabel = %AttackRow
@onready var defense_row: RichTextLabel = %DefenseRow
@onready var speed_row: RichTextLabel = %SpeedRow
@onready var attack_speed_row: RichTextLabel = %AttackSpeedRow
@onready var resist_row: RichTextLabel = %ResistRow

var _tracked_attrs: AttributeComponent = null
## Gear selected in the inventory list whose stat contribution is previewed
## with current -> projected arrows. Null renders every row plain.
var _selected_item: GearItemResource = null


func _ready() -> void:
	refresh()
	_watch_player_attributes()


func _exit_tree() -> void:
	_unwatch_player_attributes()


## Sets the gear selected in the inventory list. Stat rows touched by its
## persistent effects render as "Label: without -> with"; other rows render
## their plain current value. Null clears the preview.
func set_selected_item(gear: GearItemResource) -> void:
	_selected_item = gear
	refresh()


## Re-reads the player and progression state and rewrites all eight rows.
## Missing player (e.g. menu preview) renders placeholder dashes.
func refresh() -> void:
	var player: Character = _read_player()
	var attrs: AttributeComponent = null
	var equipment: EquipmentComponent = null
	if player != null:
		attrs = player.attribute_component
		equipment = player.equipment_component
	if attrs != _tracked_attrs:
		_unwatch_player_attributes()
		_tracked_attrs = attrs
		_watch_player_attributes()
	if attrs == null:
		_render_placeholders()
		return
	var level: int = ProgressionState.dungeon_level if ProgressionState != null else 1
	_set_row(level_row, "Level", "%d" % level, "e8c85a")
	var hp_cur: float = attrs.get_current(AttributeComponent.POOL_HEALTH)
	var hp_max: float = attrs.get_current(AttributeComponent.STAT_MAX_HEALTH)
	_set_row(hp_row, "Max HP", "%s/%s" % [_fmt(hp_cur), _fmt(hp_max)], "7fe8a8")
	var mana_cur: float = attrs.get_current(AttributeComponent.POOL_MANA)
	var mana_max: float = attrs.get_current(AttributeComponent.STAT_MAX_MANA)
	_set_row(mana_row, "Max Mana", "%s/%s" % [_fmt(mana_cur), _fmt(mana_max)], "8ac8ff")
	_render_stat_row(attack_row, "Attack", AttributeComponent.STAT_ATTACK, attrs, equipment, "7fe8a8", false)
	_render_stat_row(defense_row, "Defense", AttributeComponent.STAT_DEFENSE, attrs, equipment, "7fe8a8", false)
	_render_stat_row(speed_row, "Speed", AttributeComponent.STAT_SPEED, attrs, equipment, "7fe8a8", false)
	_render_stat_row(attack_speed_row, "Attack Speed", AttributeComponent.STAT_ATTACK_SPEED, attrs, equipment, "e8e8e8", true)
	_render_stat_row(resist_row, "Fire Resist", AttributeComponent.STAT_FIRE_RESISTANCE, attrs, equipment, "e8e8e8", true)


## Renders one stat row: "Label: without -> with" when the selected item
## touches the stat, otherwise the plain current value. Percent stats (attack
## speed, fire resistance) display scaled to 0-100 on both sides of the arrow.
func _render_stat_row(row: RichTextLabel, label: String, stat: StringName, attrs: AttributeComponent, equipment: EquipmentComponent, value_color: String, is_percent: bool) -> void:
	if row == null or attrs == null:
		return
	var current: float = attrs.get_current(stat)
	var arrow: Dictionary = _selected_arrow(stat, current, equipment)
	if arrow.is_empty():
		_set_row(row, label, _display_value(current, is_percent), value_color)
		return
	var from_text: String = _display_value(float(arrow["from"]), is_percent)
	var to_text: String = _display_value(float(arrow["to"]), is_percent)
	row.text = "%s: %s -> [color=#%s]%s[/color]" % [label, from_text, value_color, to_text]


## Returns {"from": float, "to": float} describing the selected item's
## persistent effect on a stat, or an empty Dictionary when the item never
## touches it. Only exact ADD math is previewed; other operations fall back
## to the plain row. Equipped items preview excluding their own contribution
## ("100 -> 150"); unequipped items preview a single copy applied on top.
func _selected_arrow(stat: StringName, current: float, equipment: EquipmentComponent) -> Dictionary:
	if _selected_item == null:
		return {}
	var copies: int = 0
	if equipment != null:
		for gear: GearItemResource in equipment.equipped_gear:
			if gear == _selected_item:
				copies += 1
	var magnitude_sum: float = 0.0
	for eff: GameplayEffect in _selected_item.gameplay_effects:
		if eff == null:
			continue
		if eff.target_attribute != stat:
			continue
		if eff.duration > 0.0:
			continue
		if eff.operation != Attribute.Op.ADD:
			continue
		if is_zero_approx(eff.magnitude):
			continue
		var stacks: int = 1
		if copies >= 1 and eff.stacking == GameplayEffect.Stacking.STACK:
			stacks = copies
		magnitude_sum += eff.magnitude * float(stacks)
	if is_zero_approx(magnitude_sum):
		return {}
	if copies >= 1:
		return {"from": current - magnitude_sum, "to": current}
	return {"from": current, "to": current + magnitude_sum}


func _read_player() -> Character:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as Character


func _watch_player_attributes() -> void:
	if _tracked_attrs != null and is_instance_valid(_tracked_attrs):
		if not _tracked_attrs.attribute_changed.is_connected(_on_attribute_changed):
			_tracked_attrs.attribute_changed.connect(_on_attribute_changed)


func _unwatch_player_attributes() -> void:
	if _tracked_attrs != null and is_instance_valid(_tracked_attrs):
		if _tracked_attrs.attribute_changed.is_connected(_on_attribute_changed):
			_tracked_attrs.attribute_changed.disconnect(_on_attribute_changed)
	_tracked_attrs = null


func _on_attribute_changed(_attribute_name: StringName, _current_value: float) -> void:
	refresh()


func _render_placeholders() -> void:
	_set_row(level_row, "Level", "--", "e8c85a")
	_set_row(hp_row, "Max HP", "--", "7fe8a8")
	_set_row(mana_row, "Max Mana", "--", "8ac8ff")
	_set_row(attack_row, "Total Attack", "--", "7fe8a8")
	_set_row(defense_row, "Total Defense", "--", "7fe8a8")
	_set_row(speed_row, "Total Speed", "--", "7fe8a8")
	_set_row(attack_speed_row, "Attack Speed", "--", "e8e8e8")
	_set_row(resist_row, "Fire Resist", "--", "e8e8e8")


func _set_row(row: RichTextLabel, label: String, value: String, value_color: String) -> void:
	if row == null:
		return
	row.text = "%s: [color=#%s]%s[/color]" % [label, value_color, value]


## Formats a number for UI display: whole values as integers, others with one decimal.
func _fmt(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value


## Formats a stat value for a row: percent stats scale to 0-100 with a
## percent sign, others render flat.
func _display_value(value: float, is_percent: bool) -> String:
	if is_percent:
		return "%s%%" % _fmt(value * 100.0)
	return _fmt(value)
