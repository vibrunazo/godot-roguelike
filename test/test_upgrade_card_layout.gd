## Regression suite for the UpgradeShop card layout:
## - flavor text, the stat readout and the cost footer each render in their
##   own label (cost never inside the scrolling description, stats never mixed
##   into the flavor), and the description scrolls,
## - however long the flavor grows, the stats and footer stay inside the card,
## - the running shop deals real item cards, never the editor-only previews,
## - switching the card's resource, or editing it in place, refreshes the
##   card; a free item hides the footer,
## - items bought up to their stock limit are never dealt again,
## - a card is narrow enough for a four-column layout across the screen,
## - only a card's button takes the mouse; its labels never block it,
## - taking a card charges it, applies the item once and disables every card
##   on offer; taking again does nothing,
## - buying a card exits the shop. That changes the scene, so it runs last.
## Every item here is test-owned.
extends "res://test/lib/test_suite.gd"

const CARD_SCENE: PackedScene = preload("res://UserInterface/upgrade_icon.tscn")
const SHOP_SCENE: PackedScene = preload("res://UserInterface/upgrade_shop.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned flavor that overflows any card.
const EXTREME_FLAVOR_REPEATS: int = 60
const TEST_GOLD: int = 100

var _saved_gold: int = 0


func before_each() -> void:
	_saved_gold = ProgressionState.currency_gold


func after_each() -> void:
	ProgressionState.currency_gold = _saved_gold
	ProgressionState.currency_gold_changed.emit(_saved_gold)


func test_flavor_stats_and_cost_each_render_in_their_own_label() -> void:
	var item: GearItemResource = _gear(&"test_card", "A humming blade of pure light. ".repeat(8), 10)
	var card: UpgradeIcon = await _card_for(item)
	check_eq(card.description.text, item.description, "the description should hold the flavor text only")
	check(card.description.scroll_active, "the description should scroll, so long flavor cannot push the rows below it out")
	check(card.stats_label.visible and card.stats_label.text == item.get_stat_summary(null), "the stat readout should show the item's stat summary")
	check(card.cost_label.visible and card.cost_label.text.contains(str(item.cost)), "the footer should show the cost")


func test_long_flavor_never_pushes_the_stats_or_the_cost_out_of_the_card() -> void:
	var card: UpgradeIcon = await _card_for(_gear(&"test_extreme", "The blade hums. ".repeat(EXTREME_FLAVOR_REPEATS), 7))
	var bottom: float = card.get_global_rect().end.y + 1.0
	check(card.stats_label.visible and card.stats_label.get_global_rect().end.y <= bottom, "the stat readout should stay inside the card")
	check(card.cost_label.visible and card.cost_label.get_global_rect().end.y <= bottom, "the cost footer should stay inside the card")


func test_the_running_shop_deals_real_cards_not_editor_previews() -> void:
	var shop: Control = spawn(SHOP_SCENE) as Control
	await get_tree().process_frame
	var cards: Array[Node] = (shop.get_node("%HBoxContainer") as HBoxContainer).get_children()
	check(not cards.is_empty(), "the shop should deal cards")
	for card: Node in cards:
		check(not (card.has_meta("mock_preview") and bool(card.get_meta("mock_preview"))), "an editor preview card leaked into the running shop (%s)" % card.name)
		check(card is UpgradeIcon and (card as UpgradeIcon).item_resource != null, "every dealt card should show a real item (%s)" % card.name)


func test_switching_or_editing_the_resource_refreshes_the_card() -> void:
	var first: GearItemResource = _gear(&"test_first", "First flavor.", 5)
	var card: UpgradeIcon = await _card_for(first)
	check_eq(card.title.text, first.title, "the card should show the first item")
	var second: GearItemResource = _gear(&"test_second", "Second flavor.", 0)
	card.set_item_resource(second)
	await get_tree().process_frame
	check(card.title.text == second.title and card.description.text == second.description, "switching the resource should refresh the card")
	check(not card.cost_label.visible, "a free item should hide the cost footer")
	second.description = "Edited flavor."
	second.emit_changed()
	await get_tree().process_frame
	check_eq(card.description.text, second.description, "editing the resource in place should refresh the card")


func test_items_bought_up_to_their_stock_limit_are_never_dealt() -> void:
	var shopper: Character = spawn(PLAYER_SCENE) as Character
	await get_tree().process_frame
	var limited: GearItemResource = _gear(&"test_limited", "Limited.", 1)
	limited.max_purchases = 1
	var unlimited: GearItemResource = _gear(&"test_unlimited", "Unlimited.", 1)
	shopper.equipment_component.record_purchase(limited)
	var shop: Control = SHOP_SCENE.instantiate() as Control
	var pool: Array[ItemResource] = [limited, unlimited]
	shop.set("available_items", pool)
	autofree(shop)
	add_child(shop)
	await get_tree().process_frame
	var cards: Array[Node] = (shop.get_node("%HBoxContainer") as HBoxContainer).get_children()
	if check_eq(cards.size(), 1, "only the item still in stock should be dealt"):
		check((cards[0] as UpgradeIcon).item_resource == unlimited, "the sold-out item must not be dealt")


func test_a_card_fits_a_four_column_layout() -> void:
	var card: UpgradeIcon = spawn(CARD_SCENE) as UpgradeIcon
	await get_tree().process_frame
	var column: float = float(ProjectSettings.get_setting("display/window/size/viewport_width")) / 4.0
	check(card.get_combined_minimum_size().x <= column, "a card (%.0f px) should fit a quarter of the screen width (%.0f px)" % [card.get_combined_minimum_size().x, column])


func test_only_the_cards_button_takes_the_mouse() -> void:
	var card: UpgradeIcon = await _card_for(_gear(&"test_mouse", "Flavor.", 1))
	for node: Node in card.find_children("*", "Control", true, false):
		if node is BaseButton or node is ScrollBar:
			continue
		check_eq((node as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s must not block the mouse" % node.name)
	check_eq(card.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the card itself must not block the mouse")


func test_taking_a_card_applies_it_once_and_disables_every_card() -> void:
	var player: Character = spawn(PLAYER_SCENE) as Character
	var item: GearItemResource = _gear(&"test_take", "Flavor.", 10)
	var card: UpgradeIcon = await _card_for(item)
	var other: UpgradeIcon = await _card_for(_gear(&"test_other", "Flavor.", 10))
	ProgressionState.add_gold(TEST_GOLD)
	var gold: int = ProgressionState.currency_gold
	var attack: float = player.attribute_component.get_current(AttributeComponent.STAT_ATTACK)
	var taken: Array[UpgradeIcon] = []
	card.upgrade_taken.connect(func(which: UpgradeIcon) -> void: taken.append(which))
	card.take_upgrade()
	check(taken.size() == 1 and taken[0] == card, "taking a card should report that card")
	check_eq(ProgressionState.currency_gold, gold - item.cost, "taking a card should charge its cost")
	var boosted: float = player.attribute_component.get_current(AttributeComponent.STAT_ATTACK)
	check(boosted != attack, "taking a card should apply its item")
	check(card.texture_button.disabled and other.texture_button.disabled, "taking a card should disable every card on offer")
	card.texture_button.pressed.emit()
	card.take_upgrade()
	check_approx(player.attribute_component.get_current(AttributeComponent.STAT_ATTACK), boosted, "taking the card again must not apply it twice")
	check_eq(taken.size(), 1, "taking the card again must not report it again")


## Changes the scene: keep it the last test.
func test_buying_a_card_exits_the_shop() -> void:
	var shop: Control = spawn(SHOP_SCENE) as Control
	await get_tree().process_frame
	var card: UpgradeIcon = (shop.get_node("%HBoxContainer") as HBoxContainer).get_child(0) as UpgradeIcon
	check(shop.get("exiting_shop") == false, "setup: the shop should start open")
	card.upgrade_taken.emit(card)
	check(shop.get("exiting_shop") == true, "buying a card should exit the shop")


func _card_for(item: ItemResource) -> UpgradeIcon:
	var card: UpgradeIcon = spawn(CARD_SCENE) as UpgradeIcon
	card.set_item_resource(item)
	await get_tree().process_frame
	await get_tree().process_frame
	return card


## A test-owned gear item with one stat effect, so it has a stat readout.
func _gear(id: StringName, flavor: String, cost: int) -> GearItemResource:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.effect_name = "test_card_effect"
	effect.target_attribute = AttributeComponent.STAT_ATTACK
	effect.magnitude = 5.0
	var gear: GearItemResource = GearItemResource.new()
	gear.id = id
	gear.title = String(id).capitalize()
	gear.description = flavor
	gear.cost = cost
	gear.gameplay_effects.append(effect)
	return gear
