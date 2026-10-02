## The HUD ability bar:
## - a slot's widget follows its cooldown while the bound player is alive,
## - once that player leaves the tree (its level unloads for the shop), the
##   bar keeps showing the run's slots, every one ready, and stops following
##   the freed player.
## The ability and its cooldown are test-owned.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const BAR_SCENE: PackedScene = preload("res://UserInterface/ability_bar.tscn")
const FIREBALL: AbilityResource = preload("res://Abilities/AbilityResources/ability_fireball.tres")
const PAYLOAD_SCENE: PackedScene = preload("res://Enemy/fireball_projectile.tscn")
## Test-owned cooldown, long enough to still run when the player is freed.
const TEST_COOLDOWN: float = 30.0
const TEST_RELEASE_TIME: float = 0.2
## Frame budget for a cast.
const ACTION_FRAMES: int = 600

var _arena: Node3D
var _player: Character
var _bar: AbilityBar


func before_each() -> void:
	_arena = load_arena()
	_player = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	_bar = spawn(BAR_SCENE) as AbilityBar


func test_a_freed_players_slots_stay_shown_and_ready() -> void:
	var ability: AbilityResource = _ability()
	var asc: AbilitySystemComponent = _player.ability_system_component
	asc.grant_ability(ability, null, 0)
	_bar.bind(_player)
	if not await wait_until(func() -> bool: return _player.is_on_floor(), "setup: the player should land"):
		return
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return asc.get_cooldown_fraction(0) > 0.0, "setup: the cast should start the cooldown", ACTION_FRAMES):
		return
	var widget: AbilitySlotWidget = _bar.get_widget(0)
	if not await wait_until(func() -> bool: return widget.cooldown_bar.value > 0.0, "the widget should show the live cooldown"):
		return

	var slot_count: int = asc.get_slot_count()
	_player.queue_free()
	await wait_until(func() -> bool: return not is_instance_valid(_player), "setup: the player should be freed")
	await wait_physics_frames(2)
	check(_bar.visible, "the bar should stay shown without a player")
	check_eq(_bar.get_slot_count(), slot_count, "the bar should keep every slot")
	check(widget.icon_rect.texture == ability.icon, "the slot should keep showing its ability")
	check_eq(widget.cooldown_bar.value, 0.0, "the slot should show ready, not a frozen cooldown")


func _ability() -> AbilityResource:
	var ability: AbilityResource = AbilityResource.new()
	ability.id = &"test_bar_ability"
	ability.display_name = "Test Spell"
	ability.icon = PlaceholderTexture2D.new()
	ability.cooldown = TEST_COOLDOWN
	ability.release_time = TEST_RELEASE_TIME
	ability.cast_animation = FIREBALL.cast_animation
	ability.payload_scene = PAYLOAD_SCENE
	return ability
