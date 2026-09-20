## Reusable character stats column for the pause menu concept layout.
## Reads the live player AttributeComponent plus run progression and renders
## eight stat rows (level, pools, attack/defense/speed with bases, attack
## speed, fire resistance). Refresh on ready, on show, and whenever the
## player's attributes change.
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


func _ready() -> void:
	refresh()
	_watch_player_attributes()


func _exit_tree() -> void:
	_unwatch_player_attributes()


## Re-reads the player and progression state and rewrites all eight rows.
## Missing player (e.g. menu preview) renders placeholder dashes.
func refresh() -> void:
	var player: Character = _read_player()
	var attrs: AttributeComponent = null
	if player != null:
		attrs = player.attribute_component
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
	var atk: float = attrs.get_current(AttributeComponent.STAT_ATTACK)
	var atk_base: float = attrs.get_base(AttributeComponent.STAT_ATTACK)
	_set_row(attack_row, "Total Attack", "+%s (+%s base)" % [_fmt(atk), _fmt(atk_base)], "7fe8a8")
	var dfn: float = attrs.get_current(AttributeComponent.STAT_DEFENSE)
	var dfn_base: float = attrs.get_base(AttributeComponent.STAT_DEFENSE)
	_set_row(defense_row, "Total Defense", "+%s (+%s base)" % [_fmt(dfn), _fmt(dfn_base)], "7fe8a8")
	var spd: float = attrs.get_current(AttributeComponent.STAT_SPEED)
	_set_row(speed_row, "Total Speed", "+%s" % _fmt(spd), "7fe8a8")
	var atk_spd: float = attrs.get_current(AttributeComponent.STAT_ATTACK_SPEED)
	_set_row(attack_speed_row, "Attack Speed", "%s%%" % _fmt(atk_spd * 100.0), "e8e8e8")
	var resist: float = attrs.get_current(AttributeComponent.STAT_FIRE_RESISTANCE)
	_set_row(resist_row, "Fire Resist", "%s%%" % _fmt(resist * 100.0), "e8e8e8")


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
