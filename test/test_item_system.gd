## Items and equipment:
## - equipping gear changes the stat by the effect's magnitude; unequipping
##   restores it exactly,
## - every gear item in the shop pool changes the stats it targets when
##   equipped and restores them exactly when unequipped,
## - a consumable heals and is never kept as equipment,
## - defeating an enemy awards its gold_drop; gold can be spent down to zero
##   but never below,
## - purchase limits: an item can be bought max_purchases times, then no more,
## - an item visual attaches to a bone of the character and detaches cleanly,
## - the persistent HUD is the only gold display and follows the gold count,
## - leaving the shop needs no purchase. That changes the scene, so it runs
##   last.
## Magnitudes, gold amounts and limits are test-owned or read from the items.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const SHOP_SCENE: PackedScene = preload("res://UserInterface/upgrade_shop.tscn")
const LEVEL_TEMPLATE_SCENE: PackedScene = preload("res://Levels/level_template.tscn")
## Test-owned values.
const TEST_MAGNITUDE: float = 35.0
const TEST_HEAL_PERCENT: float = 25.0
const TEST_GOLD: int = 12
const TEST_STACK: int = 3
## GameplayEffect.operation value for a flat addition ("ADD").
const OPERATION_ADD: int = 0

var _player: Character
var _saved_gold: int = 0


func before_each() -> void:
	_saved_gold = ProgressionState.currency_gold
	_player = spawn(PLAYER_SCENE) as Character
	await get_tree().process_frame


func after_each() -> void:
	ProgressionState.currency_gold = _saved_gold
	ProgressionState.currency_gold_changed.emit(_saved_gold)


func test_equipping_gear_adds_its_effect_and_unequipping_restores_the_stat() -> void:
	var gear: GearItemResource = _gear(&"test_gear", AttributeComponent.STAT_ATTACK, TEST_MAGNITUDE)
	var before: float = _stat(AttributeComponent.STAT_ATTACK)
	check(_player.equipment_component.equip_gear(gear) and _player.equipment_component.is_equipped(gear), "equipping should succeed")
	check_approx(_stat(AttributeComponent.STAT_ATTACK), before + TEST_MAGNITUDE, "equipping should add the effect's magnitude")
	check(_player.equipment_component.unequip_gear(gear) and not _player.equipment_component.is_equipped(gear), "unequipping should succeed")
	check_approx(_stat(AttributeComponent.STAT_ATTACK), before, "unequipping should restore the stat exactly")


func test_every_shop_gear_applies_and_reverts_its_stats() -> void:
	var tested: int = 0
	for item: ItemResource in GlobalVars.items:
		var gear: GearItemResource = item as GearItemResource
		if gear == null or gear.gameplay_effects.is_empty():
			continue
		tested += 1
		var baseline: Dictionary[StringName, float] = {}
		for effect: GameplayEffect in gear.gameplay_effects:
			baseline[effect.target_attribute] = _stat(effect.target_attribute)
		if not check(_player.equipment_component.apply_item(gear), "%s should equip" % gear.id):
			continue
		for attribute: StringName in baseline:
			check(not is_equal_approx(_stat(attribute), baseline[attribute]), "%s should change %s" % [gear.id, attribute])
		_player.equipment_component.unequip_gear(gear)
		for attribute: StringName in baseline:
			check_approx(_stat(attribute), baseline[attribute], "unequipping %s should restore %s" % [gear.id, attribute])
	check(tested > 0, "setup: the shop pool should offer gear with effects")


func test_a_consumable_heals_and_is_not_kept() -> void:
	var attributes: AttributeComponent = _player.attribute_component
	attributes.damage_pool(AttributeComponent.POOL_HEALTH, attributes.get_current(AttributeComponent.STAT_MAX_HEALTH) * 0.5)
	var before: float = attributes.get_current(AttributeComponent.POOL_HEALTH)
	var potion: ConsumableItemResource = ConsumableItemResource.new()
	potion.id = &"test_potion"
	potion.heal_percent = TEST_HEAL_PERCENT
	check(_player.equipment_component.use_consumable(potion), "using the consumable should succeed")
	check(attributes.get_current(AttributeComponent.POOL_HEALTH) > before, "the consumable should heal")
	check(not _player.equipment_component.is_equipped(potion), "a consumable must not be kept as equipment")


func test_defeating_an_enemy_awards_its_gold_and_gold_never_goes_negative() -> void:
	var enemy: Character = spawn(MELEE_SCENE) as Character
	await get_tree().process_frame
	var resource: EnemyResource = EnemyResource.new()
	resource.gold_drop = TEST_GOLD
	enemy.enemy_resource = resource
	var before: int = ProgressionState.currency_gold
	enemy.on_defeat()
	check_eq(ProgressionState.currency_gold, before + TEST_GOLD, "a defeat should award the enemy's gold_drop")
	check(ProgressionState.spend_gold(ProgressionState.currency_gold), "all gold should be spendable")
	check_eq(ProgressionState.currency_gold, 0, "spending everything should leave zero")
	check(not ProgressionState.spend_gold(1), "spending more than the balance should be refused")


func test_an_item_can_be_bought_up_to_its_limit_and_no_more() -> void:
	ProgressionState.add_gold(1000)
	for limit: int in [1, TEST_STACK]:
		var gear: GearItemResource = _gear(StringName("test_limit_%d" % limit), AttributeComponent.STAT_ATTACK, TEST_MAGNITUDE)
		gear.cost = 1
		gear.max_purchases = limit
		for purchase: int in range(limit):
			check(_player.equipment_component.can_purchase(gear), "purchase %d of %d should be allowed" % [purchase + 1, limit])
			_player.equipment_component.record_purchase(gear)
		check_eq(_player.equipment_component.get_purchase_count(gear), limit, "the purchase count should reach the limit")
		check(not _player.equipment_component.can_purchase(gear), "a purchase past max_purchases (%d) should be refused" % limit)


func test_an_item_visual_attaches_to_a_bone_and_detaches() -> void:
	var visual: ItemVisual = ItemVisual.new()
	visual.target_bone = "hand.r"
	visual.attach_to_character(_player)
	check(visual.get_parent() is BoneAttachment3D, "the visual should hang from a bone attachment")
	var visual_ref: WeakRef = weakref(visual)
	visual.detach_from_character()
	await wait_until(func() -> bool: return visual_ref.get_ref() == null, "detaching should free the visual", 5)


func test_the_hud_is_the_only_gold_display_and_follows_the_gold() -> void:
	var shop: Control = spawn(SHOP_SCENE) as Control
	await get_tree().process_frame
	check(shop.get_node_or_null("%GoldLabel") == null, "the shop must not keep its own gold display")
	var level: Node3D = spawn(LEVEL_TEMPLATE_SCENE) as Node3D
	(level.get_node("WaveObjective") as WaveObjective).stop_spawning()
	await get_tree().process_frame
	var hud: HUD = get_tree().get_first_node_in_group("hud") as HUD
	if not check(hud != null, "a level should show the persistent HUD"):
		return
	ProgressionState.add_gold(TEST_GOLD)
	check(hud.gold_label.text.contains(str(ProgressionState.currency_gold)), "the HUD should show the new gold count")


## Changes the scene: keep it the last test.
func test_leaving_the_shop_needs_no_purchase() -> void:
	var shop: Control = spawn(SHOP_SCENE) as Control
	await get_tree().process_frame
	check(shop.get("exiting_shop") == false, "setup: the shop should start open")
	(shop.get_node("%LeaveButton") as Button).pressed.emit()
	check(shop.get("exiting_shop") == true, "the leave button should exit the shop without a purchase")


func _gear(id: StringName, attribute: StringName, magnitude: float) -> GearItemResource:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.effect_name = String(id) + "_effect"
	effect.target_attribute = attribute
	effect.operation = OPERATION_ADD
	effect.magnitude = magnitude
	var gear: GearItemResource = GearItemResource.new()
	gear.id = id
	gear.gameplay_effects.append(effect)
	return gear


func _stat(attribute: StringName) -> float:
	return _player.attribute_component.get_current(attribute)
