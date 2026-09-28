## HealthBar: a character's floating health bar follows its AttributeComponent.
## - The player and enemies wire their bar to their own AttributeComponent.
## - The bar starts at the owner's current health fraction.
## - Damage snaps the front bar to the new fraction at once while the back
##   bar lags, then catches up within damage_lag_duration.
## - Healing raises both bars immediately.
## - When the owner is defeated the bar fades out and frees itself within
##   fade_out_duration.
## Expected values are fractions of the live max health, and waits derive
## from the bar's own durations, so retuning health or animation timing
## never breaks the suite.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const HEALTH_BAR_SCENE: PackedScene = preload("res://Components/health_bar.tscn")
## Test-owned fraction of max health dealt or healed per step.
const STEP_FRACTION: float = 0.25

var _arena: Node3D


func before_each() -> void:
	_arena = load_arena()


func test_characters_wire_the_bar_to_their_own_attributes() -> void:
	for scene: PackedScene in [PLAYER_SCENE, MELEE_SCENE]:
		var character: Character = _spawn(scene)
		var bar: HealthBar = character.get_node_or_null("HealthBar") as HealthBar
		if check(bar != null, "%s should carry a HealthBar" % character.name):
			check(bar.attribute_component == character.attribute_component, "%s's HealthBar should follow its own AttributeComponent" % character.name)


func test_bar_starts_at_the_current_health_fraction() -> void:
	var fresh: HealthBar = _spawn(PLAYER_SCENE).get_node("HealthBar") as HealthBar
	check_approx(fresh.front_progress_bar.value, fresh.front_progress_bar.max_value, "a character at full health should start with a full bar")
	# A bar attached to an owner that is already wounded.
	var attributes: AttributeComponent = autofree(AttributeComponent.new()) as AttributeComponent
	add_child(attributes)
	attributes.damage_pool(AttributeComponent.POOL_HEALTH, attributes.get_current(AttributeComponent.STAT_MAX_HEALTH) * STEP_FRACTION)
	var bar: HealthBar = HEALTH_BAR_SCENE.instantiate() as HealthBar
	bar.attribute_component = attributes
	autofree(bar)
	add_child(bar)
	check_approx(bar.front_progress_bar.value, _percentage(attributes), "the bar should start at the owner's current health, not at full")
	check_approx(bar.health_progress_bar.value, _percentage(attributes), "the back bar should start at the owner's current health too")


func test_damage_snaps_the_front_bar_and_the_back_bar_catches_up() -> void:
	var player: Character = _spawn(PLAYER_SCENE)
	var bar: HealthBar = player.get_node("HealthBar") as HealthBar
	var attributes: AttributeComponent = player.attribute_component
	attributes.damage_pool(AttributeComponent.POOL_HEALTH, attributes.get_current(AttributeComponent.STAT_MAX_HEALTH) * STEP_FRACTION)
	var target: float = _percentage(attributes)
	check_approx(bar.front_progress_bar.value, target, "the front bar should snap to the new health at once")
	await wait_physics_frames(1)
	check(bar.health_progress_bar.value > target, "the back bar should lag behind the front bar after damage")
	await wait_until(func() -> bool: return is_equal_approx(bar.health_progress_bar.value, target), "the back bar should catch up within damage_lag_duration", _frames_for(bar.damage_lag_duration))


func test_healing_raises_both_bars_immediately() -> void:
	var player: Character = _spawn(PLAYER_SCENE)
	var bar: HealthBar = player.get_node("HealthBar") as HealthBar
	var attributes: AttributeComponent = player.attribute_component
	var step: float = attributes.get_current(AttributeComponent.STAT_MAX_HEALTH) * STEP_FRACTION
	attributes.damage_pool(AttributeComponent.POOL_HEALTH, step * 2.0)
	await wait_until(func() -> bool: return is_equal_approx(bar.health_progress_bar.value, _percentage(attributes)), "the back bar should settle after damage", _frames_for(bar.damage_lag_duration))
	attributes.restore_pool(AttributeComponent.POOL_HEALTH, step)
	check_approx(bar.front_progress_bar.value, _percentage(attributes), "healing should raise the front bar at once")
	check_approx(bar.health_progress_bar.value, _percentage(attributes), "healing should raise the back bar at once")


func test_defeat_fades_the_bar_out_and_frees_it() -> void:
	var enemy: Character = _spawn(MELEE_SCENE)
	var bar: HealthBar = enemy.get_node("HealthBar") as HealthBar
	var fade_duration: float = bar.fade_out_duration
	enemy.hurtbox.receive_hit(enemy.attribute_component.get_current(AttributeComponent.POOL_HEALTH), Vector3.ZERO)
	await wait_physics_frames(1)
	if is_instance_valid(bar):
		check(bar.sprite_3d.transparency > 0.0, "the bar should start fading out on defeat")
	var bar_ref: WeakRef = weakref(bar)
	await wait_until(func() -> bool: return bar_ref.get_ref() == null or (bar_ref.get_ref() as Node).is_queued_for_deletion(), "the bar should free itself after fading out", _frames_for(fade_duration))


func _spawn(scene: PackedScene) -> Character:
	var character: Character = spawn(scene, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	disable_ai(character)
	return character


func _percentage(attributes: AttributeComponent) -> float:
	return attributes.get_current(AttributeComponent.POOL_HEALTH) / attributes.get_current(AttributeComponent.STAT_MAX_HEALTH) * 100.0


## Physics frames covering the given game time, plus a small margin.
func _frames_for(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 5
