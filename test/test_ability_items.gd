## Abilities granted by items, and the run keeping them:
## - a plain item (a spell book) teaches its abilities for good through
##   apply_item(), including as a pending item reaching the next player, and
##   cannot be applied when it would teach nothing or has no free slot,
## - gear grants its abilities only while equipped: unequipping revokes them,
##   equipping never teaches them for good, and a learned ability survives,
## - a book teaching an ability the player's gear grants is still worth
##   taking (and offered): it makes the ability learned for good in its slot,
##   so it stays when the gear comes off,
## - a fresh player bound to the run gets the run's learned abilities back in
##   their slots, and gear abilities fill the free slots,
## - an item whose abilities the run has all learned is no longer available
##   (the shop and level spawns deal only available items),
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


func test_a_book_teaches_its_abilities_for_good() -> void:
	var ability: AbilityResource = _ability()
	var book: ItemResource = _book(ability)
	check(book.can_apply(_player), "a book teaching something new should apply")
	check(_player.equipment_component.apply_item(book), "applying the book should succeed")
	var slot: int = _asc.find_slot(ability)
	if not check(slot >= 0, "the book should teach its ability"):
		return
	check(_asc.get_source(slot) == null, "a book's ability should be learned for good (no source)")
	check(not book.can_apply(_player), "a book whose abilities are all known should not apply again")


func test_a_book_needs_a_free_slot() -> void:
	for slot: int in _asc.get_slot_count():
		_asc.grant_ability(_ability())
	var book: ItemResource = _book(_ability())
	check(not book.can_apply(_player), "a book should not apply when every slot is full")
	check(not _player.equipment_component.apply_item(book), "applying it should fail")


func test_gear_grants_its_ability_only_while_equipped() -> void:
	var ability: AbilityResource = _ability()
	var gear: GearItemResource = _gear(ability)
	var learned: AbilityResource = _ability()
	_asc.grant_ability(learned)
	_player.equipment_component.equip_gear(gear)
	var slot: int = _asc.find_slot(ability)
	if not check(slot >= 0, "equipping the gear should grant its ability"):
		return
	check(_asc.get_source(slot) == gear, "the gear should be the ability's source")
	check(not ProgressionState.player_abilities.has(ability), "the run should not learn a gear ability for good")
	_player.equipment_component.unequip_gear(gear)
	check(not _asc.has_ability(ability), "unequipping the gear should revoke its ability")
	check(_asc.has_ability(learned), "an ability learned for good should survive the unequip")


func test_a_book_makes_an_ability_granted_by_gear_permanent() -> void:
	var ability: AbilityResource = _ability()
	var gear: GearItemResource = _gear(ability)
	var book: ItemResource = _book(ability)
	ProgressionState.bind_player(_player)
	_player.equipment_component.equip_gear(gear)
	var slot: int = _asc.find_slot(ability)
	# Every other slot taken: the book can only teach by making the gear's
	# ability permanent, never by needing a slot of its own.
	while _asc.has_free_slot():
		_asc.grant_ability(_ability())
	check(ProgressionState.is_item_available(book), "a book for an ability only the gear grants should be offered")
	check(book.can_apply(_player), "a book for an ability only the gear grants should apply")
	if not check(_player.equipment_component.apply_item(book), "applying the book should succeed"):
		return
	check_eq(_asc.find_slot(ability), slot, "the ability should stay in its slot")
	check(_asc.get_source(slot) == null, "the book should make the ability learned for good")
	_player.equipment_component.unequip_gear(gear)
	check(_asc.has_ability(ability), "a learned ability should stay when the gear comes off")
	check(not ProgressionState.is_item_available(book), "the book should no longer be offered once the ability is learned")


func test_a_fresh_player_gets_the_runs_abilities_back() -> void:
	var learned: AbilityResource = _ability()
	var gear_ability: AbilityResource = _ability()
	ProgressionState.bind_player(_player)
	_asc.grant_ability(learned, null, 2)
	_player.equipment_component.equip_gear(_gear(gear_ability))
	var next: Character = _spawn_player()
	ProgressionState.bind_player(next)
	var next_asc: AbilitySystemComponent = next.ability_system_component
	check(next_asc.get_ability(2) == learned, "a learned ability should come back in the same slot")
	var gear_slot: int = next_asc.find_slot(gear_ability)
	check(gear_slot >= 0 and gear_slot != 2, "a gear ability should come back in a free slot")


func test_a_book_bought_between_levels_teaches_the_next_player() -> void:
	var ability: AbilityResource = _ability()
	ProgressionState.bind_player(_player)
	ProgressionState.pending_items.append(_book(ability))
	var next: Character = _spawn_player()
	ProgressionState.bind_player(next)
	check(next.ability_system_component.has_ability(ability), "a pending book should teach the next player")


func test_an_item_teaching_only_learned_abilities_is_no_longer_available() -> void:
	var ability: AbilityResource = _ability()
	var book: ItemResource = _book(ability)
	ProgressionState.bind_player(_player)
	check(ProgressionState.is_item_available(book), "a book teaching something new should be available")
	_player.equipment_component.apply_item(book)
	check(not ProgressionState.is_item_available(book), "a book whose ability the run knows should not be offered")


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


func _book(ability: AbilityResource) -> ItemResource:
	var book: ItemResource = ItemResource.new()
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
