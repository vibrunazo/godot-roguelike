## The inventory screen (InventoryMenu) and the inspect-mode card:
## - a card shows what an item gives (flat stats), never a projected preview,
## - an INSPECT card never charges gold, never emits a purchase, and hides
##   the cost,
## - the inventory list mirrors equipped gear with plain titles and an owned
##   count on stacked gear; selecting a row shows that gear in an INSPECT
##   details card; unequipping shrinks the list and keeps a valid selection,
## - a spell book taken by the player is listed like gear, with its
##   ability's icon,
## - the inventory screen hosts the list, details and stats panels, and the
##   list drives the details,
## - with an item selected, the stats panel previews without -> with that
##   item on the stats it changes (HP clamped to each side's max) and keeps
##   the other rows plain; clearing the selection clears the arrows.
## All gear is test-owned.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const CARD_SCENE: PackedScene = preload("res://UserInterface/upgrade_icon.tscn")
const INVENTORY_SCENE: PackedScene = preload("res://UserInterface/inventory_menu.tscn")
## GameplayEffect.operation value for a flat addition ("ADD").
const OPERATION_ADD: int = 0
## Test-owned magnitudes and gold.
const TEST_ATTACK: float = 7.0
const TEST_MAX_HEALTH: float = 20.0
const TEST_GOLD: int = 50
## The stat preview's arrow between "without" and "with".
const ARROW: String = "->"

var _player: Character
var _saved_gold: int = 0


func before_each() -> void:
	_saved_gold = ProgressionState.currency_gold
	_player = spawn(PLAYER_SCENE) as Character
	await get_tree().process_frame


func after_each() -> void:
	# Purchases are run state: forget this test's, then restore the gold.
	ProgressionState.reset_run()
	ProgressionState.currency_gold = _saved_gold
	ProgressionState.currency_gold_changed.emit(_saved_gold)


func test_a_card_shows_what_the_item_gives_not_a_projection() -> void:
	var gear: GearItemResource = _gear(&"test_flat", "Flat Blade", AttributeComponent.STAT_ATTACK, TEST_ATTACK)
	var card: UpgradeIcon = spawn(CARD_SCENE) as UpgradeIcon
	card.set_item_resource(gear)
	await get_tree().process_frame
	check_eq(card.stats_label.text, gear.get_stat_summary(null), "the card should show the item's flat stat summary, even with a player present")
	check(not card.stats_label.text.contains(ARROW), "the card must not show a projected preview")


func test_an_inspect_card_never_charges_or_purchases() -> void:
	var gear: GearItemResource = _gear(&"test_inspect", "Inspect Blade", AttributeComponent.STAT_ATTACK, TEST_ATTACK)
	gear.cost = 5
	var card: UpgradeIcon = CARD_SCENE.instantiate() as UpgradeIcon
	card.card_mode = UpgradeIcon.CardMode.INSPECT
	autofree(card)
	add_child(card)
	card.set_item_resource(gear)
	await get_tree().process_frame
	ProgressionState.add_gold(TEST_GOLD)
	var gold_before: int = ProgressionState.currency_gold
	var taken: Array[bool] = [false]
	card.upgrade_taken.connect(func(_card: UpgradeIcon) -> void: taken[0] = true)
	card.take_upgrade()
	check(not taken[0], "an INSPECT card must not emit a purchase")
	check_eq(ProgressionState.currency_gold, gold_before, "an INSPECT card must not charge gold")
	check(not card.cost_label.visible, "an INSPECT card should hide the cost")


func test_the_inventory_lists_equipped_gear_and_shows_the_selection() -> void:
	var alpha: GearItemResource = _gear(&"test_alpha", "[wave]Alpha Gear[/wave]", AttributeComponent.STAT_ATTACK, 0.0)
	var beta: GearItemResource = _gear(&"test_beta", "Beta Gear", AttributeComponent.STAT_ATTACK, 0.0)
	_equip(alpha)
	_equip(beta)
	# Owned twice, so its row carries a count.
	ProgressionState.record_purchase(alpha)
	ProgressionState.record_purchase(alpha)
	var inventory: InventoryMenu = spawn(INVENTORY_SCENE) as InventoryMenu
	await get_tree().process_frame
	if not check_eq(inventory.list_panel.gear_list.item_count, 2, "the list should show both equipped items"):
		return
	var stacked: String = inventory.list_panel.gear_list.get_item_text(0)
	check(stacked.begins_with("Alpha Gear") and not stacked.contains("[") and stacked.contains("2"), "a stacked row should show the plain title and its count (got %s)" % stacked)
	check_eq(inventory.list_panel.gear_list.get_item_text(1), "Beta Gear", "a single row should show just the plain title")
	inventory.list_panel.select_row(1)
	check(inventory.get_selected_gear() == beta and inventory.detail_panel.details_card.item_resource == beta, "selecting a row should show that gear in the details card")
	check_eq(inventory.detail_panel.details_card.card_mode, UpgradeIcon.CardMode.INSPECT, "the details card should be display-only")
	_player.equipment_component.unequip_gear(alpha)
	inventory.refresh()
	check(inventory.list_panel.gear_list.item_count == 1 and inventory.get_selected_gear() == beta, "unequipping should shrink the list and keep a valid selection")


func test_a_book_is_listed_like_gear() -> void:
	var ability: AbilityResource = AbilityResource.new()
	ability.id = &"test_inventory_ability"
	ability.display_name = "Test Spell"
	ability.icon = PlaceholderTexture2D.new()
	var book: BookItemResource = BookItemResource.new()
	book.id = &"test_inventory_book"
	book.title = "Test Spell for Dummies"
	book.granted_abilities = [ability]
	check(_player.equipment_component.apply_item(book), "setup: the book should be taken")
	var inventory: InventoryMenu = spawn(INVENTORY_SCENE) as InventoryMenu
	await get_tree().process_frame
	if not check_eq(inventory.list_panel.gear_list.item_count, 1, "the list should show the book"):
		return
	check_eq(inventory.list_panel.gear_list.get_item_text(0), "Test Spell for Dummies", "the book's row should show its title")
	check(inventory.list_panel.gear_list.get_item_icon(0) == ability.icon, "the book's row should show its ability's icon")
	check(inventory.detail_panel.details_card.item_resource == book, "the details card should show the book")


func test_the_inventory_hosts_its_panels_and_the_list_drives_the_details() -> void:
	var alpha: GearItemResource = _gear(&"test_alpha", "Alpha Gear", AttributeComponent.STAT_ATTACK, 0.0)
	var beta: GearItemResource = _gear(&"test_beta", "Beta Gear", AttributeComponent.STAT_ATTACK, 0.0)
	_equip(alpha)
	_equip(beta)
	var inventory: InventoryMenu = await _inventory()
	check(inventory.list_panel != null and inventory.detail_panel != null and inventory.stats_panel != null and inventory.back_button != null, "the inventory should host the list, details and stats panels and a back button")
	if not check_eq(inventory.list_panel.gear_list.item_count, 2, "the inventory should list the equipped gear"):
		return
	inventory.list_panel.select_row(1)
	var selected: GearItemResource = inventory.get_selected_gear()
	check(selected != null and inventory.detail_panel.details_card.item_resource == selected, "selecting a row should show that gear in the details")
	for row: int in range(inventory.list_panel.gear_list.item_count):
		var text: String = inventory.list_panel.gear_list.get_item_text(row)
		check(text == "Alpha Gear" or text == "Beta Gear", "rows should read plain, selected or not (got %s)" % text)


func test_the_stats_panel_previews_the_selected_item() -> void:
	var blade: GearItemResource = _gear(&"test_blade", "Blade", AttributeComponent.STAT_ATTACK, TEST_ATTACK)
	var sigil: GearItemResource = _gear(&"test_sigil", "Sigil", AttributeComponent.STAT_MAX_HEALTH, TEST_MAX_HEALTH)
	_equip(blade)
	_equip(sigil)
	var inventory: InventoryMenu = await _inventory()
	var stats: CharacterStatsPanel = inventory.stats_panel
	await _select(inventory, blade)
	var attack: float = _player.attribute_component.get_current(AttributeComponent.STAT_ATTACK)
	var attack_row: String = stats.attack_row.text
	check(attack_row.contains(ARROW) and attack_row.contains(str(roundi(attack - TEST_ATTACK))) and attack_row.contains(str(roundi(attack))), "the attack row should preview without -> with the blade (got %s)" % attack_row)
	check(not stats.defense_row.text.contains(ARROW) and not stats.speed_row.text.contains(ARROW) and not stats.hp_row.text.contains(ARROW), "rows the blade does not change should stay plain")
	await _select(inventory, sigil)
	check(not stats.attack_row.text.contains(ARROW), "the attack row should be plain with the sigil selected")
	var health: float = _player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var max_health: float = _player.attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH)
	check_approx(health, max_health, "equipping max-health gear at full health should top the pool up to the new max")
	var without: String = "%d/%d" % [roundi(minf(health, max_health - TEST_MAX_HEALTH)), roundi(max_health - TEST_MAX_HEALTH)]
	var with: String = "%d/%d" % [roundi(minf(health, max_health)), roundi(max_health)]
	check(stats.hp_row.text.contains(ARROW) and stats.hp_row.text.contains(without) and stats.hp_row.text.contains(with), "the HP row should preview %s -> %s, each side clamped to its own max (got %s)" % [without, with, stats.hp_row.text])
	stats.set_selected_item(null)
	await get_tree().process_frame
	check(not stats.attack_row.text.contains(ARROW) and not stats.hp_row.text.contains(ARROW), "clearing the selection should clear the arrows")


func _inventory() -> InventoryMenu:
	var inventory: InventoryMenu = spawn(INVENTORY_SCENE) as InventoryMenu
	await get_tree().process_frame
	return inventory


## Selects the gear's row in the inventory list and lets the stats panel redraw.
func _select(inventory: InventoryMenu, gear: GearItemResource) -> void:
	for row: int in range(inventory.list_panel.gear_list.item_count):
		inventory.list_panel.select_row(row)
		if inventory.get_selected_gear() == gear:
			break
	await get_tree().process_frame


func _equip(gear: GearItemResource) -> void:
	check(_player.equipment_component.equip_gear(gear), "setup: %s should equip" % gear.id)


func _gear(id: StringName, title: String, attribute: StringName, magnitude: float) -> GearItemResource:
	var gear: GearItemResource = GearItemResource.new()
	gear.id = id
	gear.title = title
	gear.description = "Flavor."
	if magnitude != 0.0:
		var effect: GameplayEffect = GameplayEffect.new()
		effect.effect_name = String(id) + "_effect"
		effect.target_attribute = attribute
		effect.operation = OPERATION_ADD
		effect.magnitude = magnitude
		gear.gameplay_effects.append(effect)
	return gear
