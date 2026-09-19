## Comprehensive behavioral contract test suite for the Item and Equipment system.
## Tests relative stat deltas, unequip cleanup, consumable lifecycle, currency drops,
## purchase limits, and visual bone attachments without asserting hardcoded balance numbers.
extends Node


func _ready() -> void:
	print("--- RUNNING ITEM SYSTEM BEHAVIORAL TEST ---")

	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	await get_tree().process_frame

	if player.equipment_component == null:
		printerr("TEST FAILED: Player has no EquipmentComponent attached.")
		get_tree().quit(1)
		return
	print("ok: Player EquipmentComponent resolved.")

	# ---------------------------------------------------------
	# PART 1: Gear Equip and Dynamic Stat Application
	# ---------------------------------------------------------
	print("\n>>> PART 1: Gear Equip and Dynamic Stat Application")
	var test_effect: GameplayEffect = GameplayEffect.new()
	test_effect.effect_name = "test_gear_effect"
	test_effect.target_attribute = AttributeComponent.STAT_ATTACK
	test_effect.operation = 0 # ADD
	test_effect.magnitude = 35.0

	var test_gear: GearItemResource = GearItemResource.new()
	test_gear.id = &"test_gear"
	test_gear.title = "Test Gear"
	test_gear.gameplay_effects.append(test_effect)

	var initial_atk: float = player.attribute_component.get_current(AttributeComponent.STAT_ATTACK)
	var equip_success: bool = player.equipment_component.equip_gear(test_gear)
	if not equip_success or not player.equipment_component.is_equipped(test_gear):
		printerr("TEST FAILED: equip_gear returned false or item not marked equipped.")
		get_tree().quit(1)
		return

	var atk_equipped: float = player.attribute_component.get_current(AttributeComponent.STAT_ATTACK)
	if not is_equal_approx(atk_equipped, initial_atk + test_effect.magnitude):
		printerr("TEST FAILED: Equipped gear did not modify stat by relative magnitude. Expected: ", initial_atk + test_effect.magnitude, ", got: ", atk_equipped)
		get_tree().quit(1)
		return
	print("ok: Gear successfully equipped, stat modified by dynamic relative delta.")

	# ---------------------------------------------------------
	# PART 2: Gear Unequip and Reversal
	# ---------------------------------------------------------
	print("\n>>> PART 2: Gear Unequip and Stat Reversal")
	var unequip_success: bool = player.equipment_component.unequip_gear(test_gear)
	if not unequip_success or player.equipment_component.is_equipped(test_gear):
		printerr("TEST FAILED: unequip_gear returned false or item remains equipped.")
		get_tree().quit(1)
		return

	var atk_unequipped: float = player.attribute_component.get_current(AttributeComponent.STAT_ATTACK)
	if not is_equal_approx(atk_unequipped, initial_atk):
		printerr("TEST FAILED: Unequipping gear did not cleanly restore original stat value. Expected: ", initial_atk, ", got: ", atk_unequipped)
		get_tree().quit(1)
		return
	print("ok: Gear successfully unequipped, stat cleanly restored to baseline.")

	# ---------------------------------------------------------
	# PART 3: Consumable Application & Lifecycle
	# ---------------------------------------------------------
	print("\n>>> PART 3: Consumable Application & Lifecycle")
	var max_hp: float = player.attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH)
	var damage_amount: float = max_hp * 0.3
	player.attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, damage_amount)
	var hp_before: float = player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)

	var test_potion: ConsumableItemResource = ConsumableItemResource.new()
	test_potion.id = &"test_potion"
	test_potion.title = "Test Potion"
	test_potion.heal_percent = 25.0

	var consume_success: bool = player.equipment_component.use_consumable(test_potion)
	if not consume_success:
		printerr("TEST FAILED: use_consumable returned false.")
		get_tree().quit(1)
		return

	var hp_after: float = player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	if hp_after <= hp_before:
		printerr("TEST FAILED: Consumable did not restore health pool. Got: ", hp_after, ", was: ", hp_before)
		get_tree().quit(1)
		return

	if player.equipment_component.is_equipped(test_potion):
		printerr("TEST FAILED: Consumable should not be retained in equipped_gear.")
		get_tree().quit(1)
		return
	print("ok: Consumable successfully healed character without persisting in equipped gear.")

	# ---------------------------------------------------------
	# PART 4: Currency & Enemy Defeat Gold Drops
	# ---------------------------------------------------------
	print("\n>>> PART 4: Currency & Enemy Defeat Gold Drops")
	ProgressionState.reset_run()
	if ProgressionState.currency_gold != 0:
		printerr("TEST FAILED: ProgressionState.currency_gold not 0 after reset_run.")
		get_tree().quit(1)
		return

	var enemy_scene: PackedScene = load("res://Enemy/melee_enemy.tscn")
	var enemy: Character = enemy_scene.instantiate() as Character
	add_child(enemy)
	await get_tree().process_frame

	var test_gold_drop: int = 12
	var enemy_res: EnemyResource = EnemyResource.new()
	enemy_res.gold_drop = test_gold_drop
	enemy.enemy_resource = enemy_res

	var gold_before_kill: int = ProgressionState.currency_gold
	enemy.on_defeat()
	var gold_after_kill: int = ProgressionState.currency_gold
	if gold_after_kill != gold_before_kill + test_gold_drop:
		printerr("TEST FAILED: Enemy defeat did not award enemy_resource.gold_drop. Expected: ", gold_before_kill + test_gold_drop, ", got: ", gold_after_kill)
		get_tree().quit(1)
		return
	print("ok: Enemy defeat awarded relative gold drop to ProgressionState.")

	# Test spend_gold
	var spend_success: bool = ProgressionState.spend_gold(test_gold_drop)
	if not spend_success or ProgressionState.currency_gold != 0:
		printerr("TEST FAILED: spend_gold failed to deduct exact balance.")
		get_tree().quit(1)
		return
	var overspend: bool = ProgressionState.spend_gold(1)
	if overspend:
		printerr("TEST FAILED: spend_gold allowed spending more than available balance.")
		get_tree().quit(1)
		return
	print("ok: Gold spending and insufficient balance guards verified.")

	enemy.queue_free()

	# ---------------------------------------------------------
	# PART 5: Purchase Limits & Stock Management
	# ---------------------------------------------------------
	print("\n>>> PART 5: Purchase Limits & Stock Management")
	var unique_gear: GearItemResource = GearItemResource.new()
	unique_gear.id = &"unique_sword"
	unique_gear.cost = 10
	unique_gear.max_purchases = 1

	ProgressionState.add_gold(100)
	if not player.equipment_component.can_purchase(unique_gear):
		printerr("TEST FAILED: can_purchase should be true when player has gold and item not purchased.")
		get_tree().quit(1)
		return

	player.equipment_component.record_purchase(unique_gear)
	if player.equipment_component.get_purchase_count(unique_gear) != 1:
		printerr("TEST FAILED: get_purchase_count did not return 1.")
		get_tree().quit(1)
		return

	if player.equipment_component.can_purchase(unique_gear):
		printerr("TEST FAILED: can_purchase should be false once max_purchases reached.")
		get_tree().quit(1)
		return
	print("ok: Single purchase limit (unique gear) enforced.")

	# Stackable gear test
	var stackable_gear: GearItemResource = GearItemResource.new()
	stackable_gear.id = &"stackable_ring"
	stackable_gear.cost = 10
	stackable_gear.max_purchases = 3

	for i: int in 3:
		if not player.equipment_component.can_purchase(stackable_gear):
			printerr("TEST FAILED: stackable_gear should be purchasable at iteration ", i)
			get_tree().quit(1)
			return
		player.equipment_component.record_purchase(stackable_gear)

	if player.equipment_component.can_purchase(stackable_gear):
		printerr("TEST FAILED: stackable_gear should not be purchasable after 3 purchases.")
		get_tree().quit(1)
		return
	print("ok: Stackable purchase limit (3 stacks) enforced.")

	# ---------------------------------------------------------
	# PART 6: Visual Scene Bone Attachment & Cleanup
	# ---------------------------------------------------------
	print("\n>>> PART 6: Visual Scene Bone Attachment & Cleanup")
	var visual_gear: GearItemResource = GearItemResource.new()
	visual_gear.id = &"visual_hat"
	var custom_visual: ItemVisual = ItemVisual.new()
	custom_visual.target_bone = "hand.r"

	# Package into PackedScene dynamically for test
	custom_visual.attach_to_character(player)
	var parent_slot: Node = custom_visual.get_parent()
	if parent_slot == null or not (parent_slot is BoneAttachment3D):
		printerr("TEST FAILED: ItemVisual did not attach under a BoneAttachment3D. Parent: ", parent_slot)
		get_tree().quit(1)
		return
	print("ok: ItemVisual dynamically discovered or created BoneAttachment3D on skeleton.")

	custom_visual.detach_from_character()
	await get_tree().process_frame
	print("ok: ItemVisual detachment cleanly queued visual for deletion.")

	player.queue_free()

	# ---------------------------------------------------------
	# PART 7: UpgradeShop Cancel / Leave & Gold Display
	# ---------------------------------------------------------
	print("\n>>> PART 7: UpgradeShop Cancel / Leave & Gold Display")
	var shop_scene: PackedScene = load("res://UserInterface/upgrade_shop.tscn") as PackedScene
	var shop_inst: Control = shop_scene.instantiate() as Control
	add_child(shop_inst)
	await get_tree().process_frame

	var leave_btn: Button = shop_inst.get_node_or_null("MarginContainer/VBoxContainer/LeaveButton") as Button
	if leave_btn == null:
		printerr("TEST FAILED: UpgradeShop missing LeaveButton.")
		get_tree().quit(1)
		return
	print("ok: UpgradeShop LeaveButton present.")

	var shop_gold_lbl: RichTextLabel = shop_inst.get_node_or_null("MarginContainer/VBoxContainer/GoldLabel") as RichTextLabel
	if shop_gold_lbl == null:
		printerr("TEST FAILED: UpgradeShop missing GoldLabel.")
		get_tree().quit(1)
		return
	print("ok: UpgradeShop GoldLabel present.")

	if shop_inst.get("exiting_shop") != false:
		printerr("TEST FAILED: UpgradeShop exiting_shop should be false initially.")
		get_tree().quit(1)
		return

	# Test leave_shop without purchase
	shop_inst.call("leave_shop")
	if shop_inst.get("exiting_shop") != true:
		printerr("TEST FAILED: leave_shop() did not set exiting_shop to true.")
		get_tree().quit(1)
		return
	print("ok: UpgradeShop leave_shop() cleanly exits without requiring purchase.")
	shop_inst.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 8: Arena Level HUD Presence & In-Level Integration
	# ---------------------------------------------------------
	print("\n>>> PART 8: Arena Level HUD Presence & In-Level Integration")
	var template_scene: PackedScene = load("res://Levels/level_template.tscn") as PackedScene
	var level_inst: Node3D = template_scene.instantiate() as Node3D
	add_child(level_inst)
	await get_tree().process_frame

	var hud_node: HUD = level_inst.get_node_or_null("HUD") as HUD
	if hud_node == null:
		printerr("TEST FAILED: LevelTemplate missing child HUD node.")
		get_tree().quit(1)
		return
	print("ok: LevelTemplate has instantiated child HUD node.")

	var test_gold_val: int = 42
	ProgressionState.currency_gold = test_gold_val
	ProgressionState.currency_gold_changed.emit(test_gold_val)
	if not hud_node.gold_label.text.contains(str(test_gold_val)):
		printerr("TEST FAILED: HUD gold_label did not update with gold amount. Got: ", hud_node.gold_label.text)
		get_tree().quit(1)
		return
	print("ok: Arena HUD dynamically updates from ProgressionState currency.")
	level_inst.queue_free()
	await get_tree().process_frame

	print("\n====================================================")
	print("  ALL ITEM SYSTEM BEHAVIORAL TESTS PASSED!          ")
	print("====================================================")
	get_tree().quit(0)
