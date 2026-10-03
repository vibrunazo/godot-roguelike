## Abilities granted by items, and the run keeping them:
## - a spell book is gear: applying it equips it (the inventory's list) and
##   grants its abilities with the book as their source; it cannot be applied
##   when it would teach nothing new or has no free slot, and unequipping it
##   takes its abilities away,
## - plain gear grants its abilities only while equipped,
## - a fresh player bound to the run gets the run's books back, each ability
##   in the slot it held, and an ability granted again returns to its slot,
## - a book bought between levels (pending) teaches the next player,
## - a book whose abilities the run holds is no longer available (the shop and
##   level spawns deal only available items),
## - walking over an item pickup takes the item (a book teaches its ability)
##   and removes the pickup; a pickup the player cannot take stays.
## Every ability and item here is built by the test.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const PICKUP_SCENE: PackedScene = preload("res://Items/Pickups/item_pickup.tscn")
const BOOK_VISUAL: PackedScene = preload("res://Items/Books/book_dummies.tscn")
const CAST_ANIMATION: String = "CastSpell"
## Test-owned distance of a pickup from the player before it walks over it.
const PICKUP_DISTANCE: float = 3.0
## Frame budget for walking onto a pickup.
const WALK_FRAMES: int = 120

var _arena: Node3D
var _player: Character
var _asc: AbilitySystemComponent


func before_each() -> void:
	ProgressionState.reset_run()
	_arena = load_arena()
	_player = _spawn_player()
	_asc = _player.ability_system_component
	await wait_until(func() -> bool: return _player.is_on_floor(), "the player should settle")


func after_each() -> void:
	ProgressionState.reset_run()


func test_a_book_is_equipped_like_gear_and_grants_its_abilities() -> void:
	var ability: AbilityResource = _ability()
	var book: BookItemResource = _book(ability)
	check(book.can_apply(_player), "a book teaching something new should apply")
	check(_player.equipment_component.apply_item(book), "applying the book should succeed")
	check(_player.equipment_component.is_equipped(book), "a book should be equipped like gear")
	var slot: int = _asc.find_slot(ability)
	if not check(slot >= 0, "the book should grant its ability"):
		return
	check(_asc.get_source(slot) == book, "the book should be its ability's source")
	check(not book.can_apply(_player), "a book whose abilities are all held should not apply again")
	check(not _player.equipment_component.apply_item(book), "applying it again should fail")
	_player.equipment_component.unequip_gear(book)
	check(not _asc.has_ability(ability), "unequipping the book should take its ability away")


func test_a_book_needs_a_free_slot() -> void:
	for slot: int in _asc.get_slot_count():
		_asc.grant_ability(_ability())
	var book: BookItemResource = _book(_ability())
	check(not book.can_apply(_player), "a book should not apply when every slot is full")
	check(not _player.equipment_component.apply_item(book), "applying it should fail")
	check(not _player.equipment_component.is_equipped(book), "a book that cannot teach should not be equipped")


func test_gear_grants_its_ability_only_while_equipped() -> void:
	var ability: AbilityResource = _ability()
	var gear: GearItemResource = _gear(ability)
	var own: AbilityResource = _ability()
	_asc.grant_ability(own)
	_player.equipment_component.equip_gear(gear)
	var slot: int = _asc.find_slot(ability)
	if not check(slot >= 0, "equipping the gear should grant its ability"):
		return
	check(_asc.get_source(slot) == gear, "the gear should be the ability's source")
	_player.equipment_component.unequip_gear(gear)
	check(not _asc.has_ability(ability), "unequipping the gear should revoke its ability")
	check(_asc.has_ability(own), "an ability from another source should survive the unequip")


func test_a_fresh_player_gets_the_runs_books_back_in_their_slots() -> void:
	var first: BookItemResource = _book(_ability())
	var kept: AbilityResource = _ability()
	var second: BookItemResource = _book(kept)
	ProgressionState.bind_player(_player)
	_player.equipment_component.apply_item(first)
	_player.equipment_component.apply_item(second)
	var kept_slot: int = _asc.find_slot(kept)
	# Freeing the first slot: a plain refill would move the kept ability into it.
	_player.equipment_component.unequip_gear(first)
	var next: Character = _spawn_player()
	ProgressionState.bind_player(next)
	var next_asc: AbilitySystemComponent = next.ability_system_component
	check(next.equipment_component.is_equipped(second), "the run's book should be equipped on the fresh player")
	check_eq(next_asc.find_slot(kept), kept_slot, "its ability should come back in the slot it held")
	check(not next.equipment_component.is_equipped(first), "an unequipped book should stay unequipped")


func test_an_ability_granted_again_returns_to_its_slot() -> void:
	var ability: AbilityResource = _ability()
	var book: BookItemResource = _book(ability)
	_asc.grant_ability(_ability())
	_player.equipment_component.apply_item(book)
	var slot: int = _asc.find_slot(ability)
	_player.equipment_component.unequip_gear(book)
	_asc.revoke_ability(0)
	_player.equipment_component.equip_gear(book)
	check_eq(_asc.find_slot(ability), slot, "a re-equipped book's ability should return to its slot while it is free")


func test_a_book_bought_between_levels_teaches_the_next_player() -> void:
	var ability: AbilityResource = _ability()
	ProgressionState.bind_player(_player)
	ProgressionState.pending_items.append(_book(ability))
	var next: Character = _spawn_player()
	ProgressionState.bind_player(next)
	check(next.ability_system_component.has_ability(ability), "a pending book should teach the next player")


func test_a_book_whose_abilities_are_held_is_no_longer_available() -> void:
	var ability: AbilityResource = _ability()
	var book: BookItemResource = _book(ability)
	ProgressionState.bind_player(_player)
	check(ProgressionState.is_item_available(book), "a book teaching something new should be available")
	_player.equipment_component.apply_item(book)
	check(not ProgressionState.is_item_available(book), "a book whose ability the run holds should not be offered")


func test_walking_over_a_book_pickup_teaches_it_and_removes_the_pickup() -> void:
	var ability: AbilityResource = _ability()
	var pickup: ItemPickup = _spawn_pickup(_book(ability))
	var shown: BookModel = pickup.get_display() as BookModel
	check(shown != null and shown.title_label.text == pickup.item.get_plain_title(), "the pickup should show the book with its title on the cover")
	_walk_onto(pickup)
	if not await wait_until(func() -> bool: return _asc.has_ability(ability), "walking over the book should teach its ability", WALK_FRAMES):
		return
	await wait_until(func() -> bool: return not is_instance_valid(pickup), "a taken pickup should go away", WALK_FRAMES)


func test_a_pickup_the_player_cannot_take_stays() -> void:
	for slot: int in _asc.get_slot_count():
		_asc.grant_ability(_ability())
	var ability: AbilityResource = _ability()
	var pickup: ItemPickup = _spawn_pickup(_book(ability))
	_walk_onto(pickup)
	var taken: Array[bool] = [false]
	pickup.picked_up.connect(func(_item: ItemResource, _by: Character) -> void: taken[0] = true)
	await wait_until(func() -> bool: return pickup.overlaps_body(_player), "the player should reach the pickup", WALK_FRAMES)
	await wait_physics_frames(5)
	check(not taken[0] and is_instance_valid(pickup) and not pickup.is_queued_for_deletion(), "a book with no free slot should stay on the floor")
	check(not _asc.has_ability(ability), "a book with no free slot should teach nothing")


# --- Helpers -----------------------------------------------------------------

func _spawn_pickup(item: ItemResource) -> ItemPickup:
	var pickup: ItemPickup = PICKUP_SCENE.instantiate() as ItemPickup
	pickup.item = item
	pickup.position = _player.global_position + Vector3.BACK * PICKUP_DISTANCE + Vector3.DOWN * _player.get_origin_height()
	_arena.add_child(pickup)
	return pickup


func _walk_onto(pickup: ItemPickup) -> void:
	_player.move_direction = (pickup.global_position - _player.global_position).slide(Vector3.UP).normalized()

func _spawn_player() -> Character:
	var player: Character = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	return player


func _ability() -> AbilityResource:
	var ability: AbilityResource = AbilityResource.new()
	ability.id = StringName("test_ability_%d" % randi())
	ability.display_name = "Test Spell"
	ability.cast_animation = CAST_ANIMATION
	return ability


func _book(ability: AbilityResource) -> BookItemResource:
	var book: BookItemResource = BookItemResource.new()
	book.id = StringName("test_book_%d" % randi())
	book.max_purchases = 1
	book.granted_abilities = [ability]
	book.title = "[wave]Test Spell for Dummies[/wave]"
	book.world_visual = BOOK_VISUAL
	return book


func _gear(ability: AbilityResource) -> GearItemResource:
	var gear: GearItemResource = GearItemResource.new()
	gear.id = StringName("test_gear_%d" % randi())
	gear.granted_abilities = [ability]
	return gear
