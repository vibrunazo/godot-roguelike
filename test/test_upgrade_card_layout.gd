## Regression suite for the UpgradeShop card layout.
## Covers: cost/stock render in the pinned footer (never inside the scrolling
## description), stats render in their own pinned readout (never mixed into
## the flavor text), long flavor keeps stats and footer inside the card
## bounds, and editor-only mock preview cards are stripped before real cards
## appear.
extends Node


func _ready() -> void:
	print("--- RUNNING UPGRADE CARD LAYOUT TEST ---")

	# ---------------------------------------------------------
	# PART 1: Cost lives in the pinned footer, not the description
	# ---------------------------------------------------------
	print("\n>>> PART 1: Cost/footer separation")
	var card_scene: PackedScene = load("res://UserInterface/upgrade_icon.tscn") as PackedScene
	if card_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/upgrade_icon.tscn.")
		get_tree().quit(1)
		return
	var card: UpgradeIcon = card_scene.instantiate() as UpgradeIcon
	add_child(card)

	var test_effect: GameplayEffect = GameplayEffect.new()
	test_effect.effect_name = "test_layout_effect"
	test_effect.target_attribute = AttributeComponent.STAT_ATTACK
	test_effect.operation = 0 # ADD
	test_effect.magnitude = 5.0

	var long_res: GearItemResource = GearItemResource.new()
	long_res.id = &"test_long_card"
	long_res.title = "[wave]Test Sword[/wave]"
	long_res.description = "A humming blade of pure light. Cleaves through armor, notions, and anything else standing in the way. The edge never dulls, the hum never fades, and the weight always feels just right in a practiced hand. " + "The edge never dulls, the hum never fades. "
	long_res.cost = 10
	long_res.max_purchases = 3
	long_res.gameplay_effects.append(test_effect)
	card.set_item_resource(long_res)
	await get_tree().process_frame
	await get_tree().process_frame

	var footer: RichTextLabel = card.get_node_or_null("%CostLabel") as RichTextLabel
	if footer == null:
		printerr("TEST FAILED: UpgradeIcon missing pinned CostLabel footer.")
		get_tree().quit(1)
		return
	var desc: RichTextLabel = card.get_node_or_null("%Description") as RichTextLabel
	if desc == null:
		printerr("TEST FAILED: UpgradeIcon missing Description label.")
		get_tree().quit(1)
		return
	var stats: RichTextLabel = card.get_node_or_null("%StatsLabel") as RichTextLabel
	if stats == null:
		printerr("TEST FAILED: UpgradeIcon missing StatsLabel readout.")
		get_tree().quit(1)
		return
	if not footer.visible:
		printerr("TEST FAILED: CostLabel footer hidden for a priced item.")
		get_tree().quit(1)
		return
	if not footer.text.contains("Cost"):
		printerr("TEST FAILED: CostLabel footer does not show the cost. Got: ", footer.text)
		get_tree().quit(1)
		return
	if desc.text != long_res.description:
		printerr("TEST FAILED: Description must hold flavor text only. Got: ", desc.text)
		get_tree().quit(1)
		return
	if not stats.visible or not stats.text.contains("Attack"):
		printerr("TEST FAILED: Stats readout missing or not showing the stat change. Got: ", stats.text)
		get_tree().quit(1)
		return
	if not desc.scroll_active:
		printerr("TEST FAILED: Description must scroll so long text cannot push the footer out.")
		get_tree().quit(1)
		return
	print("ok: Flavor, stats readout, and cost footer each render in their own label.")

	# ---------------------------------------------------------
	# PART 2: Worst-case text keeps the footer inside the card
	# ---------------------------------------------------------
	print("\n>>> PART 2: Pinned rows stay inside card bounds")
	var card_rect: Rect2 = (card as PanelContainer).get_global_rect()
	var stats_rect: Rect2 = stats.get_global_rect()
	var footer_rect: Rect2 = footer.get_global_rect()
	if stats_rect.end.y > card_rect.end.y + 1.0:
		printerr("TEST FAILED: Stats readout extends below the card. Card end: ", card_rect.end.y, ", stats end: ", stats_rect.end.y)
		get_tree().quit(1)
		return
	if footer_rect.end.y > card_rect.end.y + 1.0:
		printerr("TEST FAILED: Cost footer extends below the card. Card end: ", card_rect.end.y, ", footer end: ", footer_rect.end.y)
		get_tree().quit(1)
		return
	print("ok: Stats bottom (", stats_rect.end.y, ") and footer bottom (", footer_rect.end.y, ") inside card bottom (", card_rect.end.y, ").")
	card.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 3: Editor mock previews never reach the game
	# ---------------------------------------------------------
	print("\n>>> PART 3: Mock previews stripped at runtime")
	var shop_scene: PackedScene = load("res://UserInterface/upgrade_shop.tscn") as PackedScene
	if shop_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/upgrade_shop.tscn.")
		get_tree().quit(1)
		return
	var shop: Control = shop_scene.instantiate() as Control
	add_child(shop)
	await get_tree().process_frame
	await get_tree().process_frame

	var container: HBoxContainer = shop.get_node_or_null("%HBoxContainer") as HBoxContainer
	if container == null:
		printerr("TEST FAILED: UpgradeShop missing upgrade HBoxContainer.")
		get_tree().quit(1)
		return
	if container.get_children().is_empty():
		printerr("TEST FAILED: UpgradeShop dealt no runtime cards.")
		get_tree().quit(1)
		return
	for child: Node in container.get_children():
		if child.has_meta("mock_preview") and bool(child.get_meta("mock_preview")):
			printerr("TEST FAILED: Editor mock preview card leaked into the running shop: ", child.name)
			get_tree().quit(1)
			return
		var runtime_card: UpgradeIcon = child as UpgradeIcon
		if runtime_card == null or runtime_card.item_resource == null:
			printerr("TEST FAILED: Shop child is not a runtime-populated item card: ", child.name)
			get_tree().quit(1)
			return
	print("ok: No mock previews at runtime; every card is a real item card.")
	shop.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 4: Switching resources refreshes the card live
	# ---------------------------------------------------------
	print("\n>>> PART 4: Resource switch and in-place edit refresh")
	var live_card: UpgradeIcon = card_scene.instantiate() as UpgradeIcon
	add_child(live_card)
	var first_res: GearItemResource = GearItemResource.new()
	first_res.id = &"test_first"
	first_res.title = "First Title"
	first_res.description = "First version flavor."
	first_res.cost = 5
	live_card.set_item_resource(first_res)
	await get_tree().process_frame

	var live_title: RichTextLabel = live_card.get_node_or_null("%Title") as RichTextLabel
	var live_footer: RichTextLabel = live_card.get_node_or_null("%CostLabel") as RichTextLabel
	var live_desc: RichTextLabel = live_card.get_node_or_null("%Description") as RichTextLabel
	if live_title.text != first_res.title or not live_footer.text.contains("Cost"):
		printerr("TEST FAILED: Card did not render the first resource. Title: ", live_title.text, ", footer: ", live_footer.text)
		get_tree().quit(1)
		return

	# Same path as switching the resource in the editor inspector.
	var potion_res: ItemResource = load("res://Items/ItemResources/item_potion.tres") as ItemResource
	live_card.set_item_resource(potion_res)
	await get_tree().process_frame
	if live_title.text != potion_res.title or not live_desc.text.contains(potion_res.description):
		printerr("TEST FAILED: Card did not refresh after switching resource. Title: ", live_title.text)
		get_tree().quit(1)
		return
	print("ok: Switching item_resource refreshes title, description, and footer.")

	# Same path as tweaking the .tres in place (resource emits changed).
	var tweak_res: GearItemResource = GearItemResource.new()
	tweak_res.id = &"test_tweak"
	tweak_res.title = "Tweak Title"
	tweak_res.description = "Before tweak."
	tweak_res.cost = 0
	live_card.set_item_resource(tweak_res)
	await get_tree().process_frame
	tweak_res.description = "After tweak."
	tweak_res.emit_changed()
	await get_tree().process_frame
	if not live_desc.text.contains("After tweak."):
		printerr("TEST FAILED: Card did not refresh after in-place resource edit. Got: ", live_desc.text)
		get_tree().quit(1)
		return
	if live_footer.visible:
		printerr("TEST FAILED: Footer should hide for a free item. Got: ", live_footer.text)
		get_tree().quit(1)
		return
	print("ok: In-place resource edits refresh the card; free items hide the footer.")
	live_card.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 5: Extreme flavor cannot push stats or footer out
	# ---------------------------------------------------------
	print("\n>>> PART 5: Extreme flavor keeps pinned rows readable")
	var extreme_card: UpgradeIcon = card_scene.instantiate() as UpgradeIcon
	add_child(extreme_card)
	var extreme_res: GearItemResource = GearItemResource.new()
	extreme_res.id = &"test_extreme_flavor"
	extreme_res.title = "Extreme Flavor"
	extreme_res.description = "The blade hums. ".repeat(60)
	extreme_res.cost = 7
	extreme_res.gameplay_effects.append(test_effect)
	extreme_card.set_item_resource(extreme_res)
	await get_tree().process_frame
	await get_tree().process_frame

	var extreme_stats: RichTextLabel = extreme_card.get_node_or_null("%StatsLabel") as RichTextLabel
	var extreme_footer: RichTextLabel = extreme_card.get_node_or_null("%CostLabel") as RichTextLabel
	var extreme_rect: Rect2 = (extreme_card as PanelContainer).get_global_rect()
	if not extreme_stats.visible or not extreme_stats.text.contains("Attack"):
		printerr("TEST FAILED: Extreme flavor hid the stats readout. Got: ", extreme_stats.text)
		get_tree().quit(1)
		return
	if extreme_stats.get_global_rect().end.y > extreme_rect.end.y + 1.0:
		printerr("TEST FAILED: Extreme flavor pushed stats below the card.")
		get_tree().quit(1)
		return
	if not extreme_footer.visible or extreme_footer.get_global_rect().end.y > extreme_rect.end.y + 1.0:
		printerr("TEST FAILED: Extreme flavor pushed the cost footer below the card.")
		get_tree().quit(1)
		return
	print("ok: Stats and footer stay readable no matter how long the flavor grows.")
	extreme_card.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 6: Maxed-out items are never dealt
	# ---------------------------------------------------------
	print("\n>>> PART 6: Stock-exhausted items leave the pool")
	var player_scene: PackedScene = load("res://Player/player.tscn") as PackedScene
	var shopper: Character = player_scene.instantiate() as Character
	add_child(shopper)
	await get_tree().process_frame
	if shopper.equipment_component == null:
		printerr("TEST FAILED: Player has no EquipmentComponent.")
		get_tree().quit(1)
		return

	var sword_res: ItemResource = load("res://Items/ItemResources/item_damage.tres") as ItemResource
	var potion_stock_res: ItemResource = load("res://Items/ItemResources/item_potion.tres") as ItemResource
	if sword_res.max_purchases <= 0:
		printerr("TEST FAILED: Sword test prerequisite: expected a limited-stock item.")
		get_tree().quit(1)
		return
	while shopper.equipment_component.get_purchase_count(sword_res) < sword_res.max_purchases:
		shopper.equipment_component.record_purchase(sword_res)

	# Deterministic two-item pool: the maxed-out sword must be filtered out,
	# leaving only the potion on offer.
	var stocked_shop: Control = shop_scene.instantiate() as Control
	var forced_pool: Array[ItemResource] = [sword_res, potion_stock_res]
	stocked_shop.set("available_items", forced_pool)
	add_child(stocked_shop)
	await get_tree().process_frame
	await get_tree().process_frame

	var stocked_container: HBoxContainer = stocked_shop.get_node_or_null("%HBoxContainer") as HBoxContainer
	if stocked_container.get_child_count() != 1:
		printerr("TEST FAILED: Only the still-available item should be dealt. Got: ", stocked_container.get_child_count(), " cards.")
		get_tree().quit(1)
		return
	var offered: UpgradeIcon = stocked_container.get_child(0) as UpgradeIcon
	if offered == null or offered.item_resource != potion_stock_res:
		printerr("TEST FAILED: Maxed-out sword was dealt instead of the available potion.")
		get_tree().quit(1)
		return
	print("ok: Maxed-out items never appear as shop options.")
	stocked_shop.queue_free()
	shopper.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 7: Card is thin enough for the pause four-column layout
	# ---------------------------------------------------------
	print("\n>>> PART 7: Thin card fits the pause columns")
	var thin_card: UpgradeIcon = card_scene.instantiate() as UpgradeIcon
	add_child(thin_card)
	await get_tree().process_frame
	var thin_min: Vector2 = (thin_card as PanelContainer).get_combined_minimum_size()
	if thin_min.x > 260.0:
		printerr("TEST FAILED: Upgrade card is too wide for the 4-column pause menu. Min width: ", thin_min.x)
		get_tree().quit(1)
		return
	print("ok: Card minimum width (", thin_min.x, ") fits a pause column.")
	thin_card.queue_free()
	await get_tree().process_frame

	print("\n====================================================")
	print("  ALL UPGRADE CARD LAYOUT TESTS PASSED!              ")
	print("====================================================")
	get_tree().quit(0)
