## Regression suite for the UpgradeShop card layout.
## Covers: cost/stock render in the pinned footer (never inside the scrolling
## description), long descriptions keep the footer inside the card bounds,
## and editor-only mock preview cards are stripped before real cards appear.
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
	if not footer.visible:
		printerr("TEST FAILED: CostLabel footer hidden for a priced item.")
		get_tree().quit(1)
		return
	if not footer.text.contains("Cost"):
		printerr("TEST FAILED: CostLabel footer does not show the cost. Got: ", footer.text)
		get_tree().quit(1)
		return
	if desc.text.contains("Cost"):
		printerr("TEST FAILED: Cost text leaked into the scrolling description.")
		get_tree().quit(1)
		return
	if not desc.scroll_active:
		printerr("TEST FAILED: Description must scroll so long text cannot push the footer out.")
		get_tree().quit(1)
		return
	print("ok: Cost renders in the pinned footer; description carries no cost text and scrolls.")

	# ---------------------------------------------------------
	# PART 2: Worst-case text keeps the footer inside the card
	# ---------------------------------------------------------
	print("\n>>> PART 2: Footer stays inside card bounds")
	var card_rect: Rect2 = (card as PanelContainer).get_global_rect()
	var footer_rect: Rect2 = footer.get_global_rect()
	if footer_rect.end.y > card_rect.end.y + 1.0:
		printerr("TEST FAILED: Cost footer extends below the card. Card end: ", card_rect.end.y, ", footer end: ", footer_rect.end.y)
		get_tree().quit(1)
		return
	print("ok: Cost footer bottom (", footer_rect.end.y, ") inside card bottom (", card_rect.end.y, ").")
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

	print("\n====================================================")
	print("  ALL UPGRADE CARD LAYOUT TESTS PASSED!              ")
	print("====================================================")
	get_tree().quit(0)
