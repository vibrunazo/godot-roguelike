## Behavioral suite for the inventory menu, the inspect-mode upgrade card,
## and the pause menu two-panel layout.
## Covers: flat stat readout with a player present, INSPECT cards never
## charging gold or emitting purchase, gear list tracking equipped gear with
## click-to-details, and pause buttons docked right with inventory left.
extends Node


func _ready() -> void:
	print("--- RUNNING INVENTORY MENU TEST ---")

	var card_scene: PackedScene = load("res://UserInterface/upgrade_icon.tscn") as PackedScene
	if card_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/upgrade_icon.tscn.")
		get_tree().quit(1)
		return

	# ---------------------------------------------------------
	# PART 1: Stats read flat even with a player in the tree
	# ---------------------------------------------------------
	print("\n>>> PART 1: Flat stat readout with player present")
	var player_scene: PackedScene = load("res://Player/player.tscn") as PackedScene
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	await get_tree().process_frame
	if player.equipment_component == null:
		printerr("TEST FAILED: Player has no EquipmentComponent.")
		get_tree().quit(1)
		return

	var flat_effect: GameplayEffect = GameplayEffect.new()
	flat_effect.effect_name = "test_flat_effect"
	flat_effect.target_attribute = AttributeComponent.STAT_ATTACK
	flat_effect.operation = 0 # ADD
	flat_effect.magnitude = 7.0
	var flat_res: GearItemResource = GearItemResource.new()
	flat_res.id = &"test_flat_card"
	flat_res.title = "Flat Blade"
	flat_res.description = "Flavor."
	flat_res.cost = 5
	flat_res.gameplay_effects.append(flat_effect)

	var flat_card: UpgradeIcon = card_scene.instantiate() as UpgradeIcon
	add_child(flat_card)
	flat_card.set_item_resource(flat_res)
	await get_tree().process_frame

	var flat_stats: RichTextLabel = flat_card.get_node_or_null("%StatsLabel") as RichTextLabel
	var flat_desc: RichTextLabel = flat_card.get_node_or_null("%Description") as RichTextLabel
	if not flat_stats.text.contains("Attack") or not flat_stats.text.contains("+"):
		printerr("TEST FAILED: Stats readout missing flat bonus. Got: ", flat_stats.text)
		get_tree().quit(1)
		return
	if flat_stats.text.contains("->") or flat_desc.text != flat_res.description:
		printerr("TEST FAILED: Card shows a projected preview instead of flat stats. Stats: ", flat_stats.text, " Desc: ", flat_desc.text)
		get_tree().quit(1)
		return
	print("ok: Card shows what the item gives, never a projected preview.")

	# ---------------------------------------------------------
	# PART 2: INSPECT cards never charge or emit a purchase
	# ---------------------------------------------------------
	print("\n>>> PART 2: Inspect mode is display-only")
	var inspect_card: UpgradeIcon = card_scene.instantiate() as UpgradeIcon
	inspect_card.card_mode = UpgradeIcon.CardMode.INSPECT
	add_child(inspect_card)
	inspect_card.set_item_resource(flat_res)
	await get_tree().process_frame

	ProgressionState.add_gold(50)
	var gold_before: int = ProgressionState.currency_gold
	var emitted: Array[UpgradeIcon] = []
	inspect_card.upgrade_taken.connect(func(taken: UpgradeIcon) -> void: emitted.append(taken))
	inspect_card.take_upgrade()
	if not emitted.is_empty():
		printerr("TEST FAILED: INSPECT card emitted upgrade_taken.")
		get_tree().quit(1)
		return
	if ProgressionState.currency_gold != gold_before:
		printerr("TEST FAILED: INSPECT card changed the gold balance.")
		get_tree().quit(1)
		return
	var inspect_footer: RichTextLabel = inspect_card.get_node_or_null("%CostLabel") as RichTextLabel
	if inspect_footer.visible:
		printerr("TEST FAILED: INSPECT card shows a cost footer for owned gear. Got: ", inspect_footer.text)
		get_tree().quit(1)
		return
	print("ok: INSPECT cards cannot be purchased and hide the cost.")

	# ---------------------------------------------------------
	# PART 3: Gear list tracks equipped gear, click shows details
	# ---------------------------------------------------------
	print("\n>>> PART 3: Inventory list and details")
	var gear_a: GearItemResource = GearItemResource.new()
	gear_a.id = &"test_gear_alpha"
	gear_a.title = "[wave]Alpha Gear[/wave]"
	gear_a.description = "First."
	var gear_b: GearItemResource = GearItemResource.new()
	gear_b.id = &"test_gear_beta"
	gear_b.title = "Beta Gear"
	gear_b.description = "Second."
	if not player.equipment_component.equip_gear(gear_a):
		printerr("TEST FAILED: Could not equip test gear A.")
		get_tree().quit(1)
		return
	if not player.equipment_component.equip_gear(gear_b):
		printerr("TEST FAILED: Could not equip test gear B.")
		get_tree().quit(1)
		return
	# Own gear A twice so its row must carry a stack count.
	player.equipment_component.record_purchase(gear_a)
	player.equipment_component.record_purchase(gear_a)

	var inventory_scene: PackedScene = load("res://UserInterface/inventory_menu.tscn") as PackedScene
	if inventory_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/inventory_menu.tscn.")
		get_tree().quit(1)
		return
	var inventory: InventoryMenu = inventory_scene.instantiate() as InventoryMenu
	add_child(inventory)
	await get_tree().process_frame

	if inventory.gear_list.item_count != 2:
		printerr("TEST FAILED: Gear list should show 2 equipped items. Got: ", inventory.gear_list.item_count)
		get_tree().quit(1)
		return
	if inventory.gear_list.get_item_text(0).contains("["):
		printerr("TEST FAILED: Gear list shows raw BBCode. Got: ", inventory.gear_list.get_item_text(0))
		get_tree().quit(1)
		return
	if inventory.gear_list.get_item_text(0) != "Alpha Gear x2":
		printerr("TEST FAILED: Stacked gear row must show its count. Got: ", inventory.gear_list.get_item_text(0))
		get_tree().quit(1)
		return
	if inventory.gear_list.get_item_text(1) != "Beta Gear":
		printerr("TEST FAILED: Single gear row must show no count suffix. Got: ", inventory.gear_list.get_item_text(1))
		get_tree().quit(1)
		return
	# Mirror a real click on the second row: select it, then drive the
	# real selection signal path.
	inventory.gear_list.select(1)
	inventory.gear_list.item_selected.emit(1)
	if inventory.get_selected_gear() != gear_b:
		printerr("TEST FAILED: Selecting row 1 did not select the second gear.")
		get_tree().quit(1)
		return
	if inventory.details_card.item_resource != gear_b:
		printerr("TEST FAILED: Details card did not show the selected gear.")
		get_tree().quit(1)
		return
	if inventory.details_card.card_mode != UpgradeIcon.CardMode.INSPECT:
		printerr("TEST FAILED: Inventory details card is not in INSPECT mode.")
		get_tree().quit(1)
		return
	print("ok: Gear list mirrors equipped gear; selection drives the details card.")

	# Unequipping refreshes the list and keeps a valid selection.
	if not player.equipment_component.unequip_gear(gear_a):
		printerr("TEST FAILED: Could not unequip test gear A.")
		get_tree().quit(1)
		return
	inventory.refresh()
	if inventory.gear_list.item_count != 1 or inventory.get_selected_gear() != gear_b:
		printerr("TEST FAILED: List did not shrink to the remaining gear after unequip.")
		get_tree().quit(1)
		return
	print("ok: Unequip refreshes the list with a valid selection.")

	# ---------------------------------------------------------
	# PART 4: Pause menu hosts inventory left, buttons right
	# ---------------------------------------------------------
	print("\n>>> PART 4: Pause two-panel layout")
	var pause_scene: PackedScene = load("res://UserInterface/pause_menu.tscn") as PackedScene
	if pause_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/pause_menu.tscn.")
		get_tree().quit(1)
		return
	var pause_menu: PauseMenu = pause_scene.instantiate() as PauseMenu
	add_child(pause_menu)
	await get_tree().process_frame

	if pause_menu.inventory_menu == null:
		printerr("TEST FAILED: PauseMenu has no inventory panel reference.")
		get_tree().quit(1)
		return
	var left_side: MarginContainer = pause_menu.get_node_or_null("LeftMarginContainer") as MarginContainer
	var right_side: MarginContainer = pause_menu.get_node_or_null("RightMarginContainer") as MarginContainer
	if left_side == null or left_side.anchor_right != 0.0:
		printerr("TEST FAILED: Inventory is not docked to the left side.")
		get_tree().quit(1)
		return
	if right_side == null or right_side.anchor_left != 1.0:
		printerr("TEST FAILED: Buttons panel is not docked to the right side.")
		get_tree().quit(1)
		return
	if not left_side.is_ancestor_of(pause_menu.inventory_menu):
		printerr("TEST FAILED: Inventory panel is not inside the left container.")
		get_tree().quit(1)
		return
	if pause_menu.resume_button == null or pause_menu.quit_button == null:
		printerr("TEST FAILED: Pause buttons missing after re-layout.")
		get_tree().quit(1)
		return
	if pause_menu.inventory_menu.gear_list.item_count != 1:
		printerr("TEST FAILED: Pause inventory did not pick up equipped gear. Got: ", pause_menu.inventory_menu.gear_list.item_count)
		get_tree().quit(1)
		return
	print("ok: Pause shows inventory left, buttons right, both wired.")

	pause_menu.queue_free()
	inventory.queue_free()
	flat_card.queue_free()
	inspect_card.queue_free()
	player.queue_free()
	await get_tree().process_frame

	print("\n====================================================")
	print("  ALL INVENTORY MENU TESTS PASSED!                   ")
	print("====================================================")
	get_tree().quit(0)
