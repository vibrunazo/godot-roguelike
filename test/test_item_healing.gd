## Healing items: ItemResource.heal_percent is always a percentage of max
## health (50 heals 50%, 1 heals 1%, 0.5 heals 0.5%), whatever its size, and
## the item card's summary projects the same heal the item applies.
## (Regression: values up to 1.0 used to be read as fractions, so 1.0 healed
## 100% while 1.5 healed 1.5%.)
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned heal percentages on both sides of the old 1.0 threshold.
const TEST_PERCENTS: Array[float] = [50.0, 1.0, 0.5]
## Test-owned max health, large enough that every heal is measurable.
const TEST_MAX_HEALTH: float = 1000.0

var _player: Character


func before_each() -> void:
	var arena: Node3D = load_arena()
	_player = spawn(PLAYER_SCENE, arena, (arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	_player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, TEST_MAX_HEALTH)


func test_heal_percent_heals_that_percentage_of_max_health() -> void:
	var attributes: AttributeComponent = _player.attribute_component
	for percent: float in TEST_PERCENTS:
		_wound_to_one_hit_point()
		var before: float = _health()
		var item: ItemResource = _healing_item(percent)
		check(item.apply(_player), "a healing item should apply to the player")
		var expected: float = attributes.get_current(AttributeComponent.STAT_MAX_HEALTH) * percent / 100.0
		check_approx(_health() - before, expected, "heal_percent %s should heal %s%% of max health" % [percent, percent])


func test_item_summary_projects_the_heal_the_item_applies() -> void:
	for percent: float in TEST_PERCENTS:
		_wound_to_one_hit_point()
		var item: ItemResource = _healing_item(percent)
		var summary: String = item.get_stat_summary(_player)
		item.apply(_player)
		check(summary.contains(_format(_health())), "the summary for heal_percent %s should project the health the item actually leaves (%s), got: %s" % [percent, _format(_health()), summary])


func _healing_item(percent: float) -> ItemResource:
	var item: ItemResource = ItemResource.new()
	item.heal_percent = percent
	return item


func _wound_to_one_hit_point() -> void:
	_player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, 1.0)


func _health() -> float:
	return _player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## Health formatted the way item summaries print amounts (whole numbers bare,
## otherwise one decimal).
func _format(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
