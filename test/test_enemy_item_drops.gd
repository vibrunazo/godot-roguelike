## Enemies dropping items (ability books) and books teaching passives:
## - a defeated enemy drops each LootDrop of its archetype that wins its roll,
##   as a pickup lying on the floor where the enemy fell; a drop with no
##   chance never drops,
## - an item never drops while the player holds what it teaches (learned or
##   from gear), while a pickup of it already lies in the level, or before a
##   player is bound to the run,
## - a book teaching a passive is equipped like gear: the run remembers it, a
##   fresh player gets it back, and the book is no longer offered,
## - a HitEffectPassive applies its effects to what the owner's melee attacks
##   hit.
## Every ability, item, effect and archetype here is built by the test.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const BOOK_VISUAL: PackedScene = preload("res://Items/Books/book_dummies.tscn")
## A passive scene for passive books (any PassiveAbility scene works).
const PASSIVE_SCENE: PackedScene = preload("res://Passives/passive_lag_spike.tscn")
const CAST_ANIMATION: String = "CastSpell"
## Test-owned damage that kills any enemy here in one hit.
const LETHAL_DAMAGE: float = 100000.0
## Test-owned dummy health, high enough that no attack here can kill it.
const DUMMY_HEALTH: float = 100000.0
## Test-owned distance between the player and the enemy.
const ENEMY_DISTANCE: float = 4.0
## How far a drop may lie from where the enemy fell, horizontally, in meters.
const DROP_TOLERANCE: float = 0.5
## Frame budget for one attack animation.
const ATTACK_FRAMES: int = 600

var _arena: Node3D
var _player: Character
var _asc: AbilitySystemComponent


func before_each() -> void:
	ProgressionState.reset_run()
	_arena = load_arena()
	_player = _spawn_player()
	_asc = _player.ability_system_component
	await wait_until(func() -> bool: return _player.is_on_floor(), "the player should settle")
	await wait_for_navigation(_arena)


func after_each() -> void:
	ProgressionState.reset_run()


func test_a_defeated_enemy_drops_its_item_where_it_fell() -> void:
	ProgressionState.bind_player(_player)
	var book: BookItemResource = _book(_ability())
	var enemy: Character = await _spawn_enemy(_archetype(book, 1.0))
	var fell_at: Vector3 = enemy.global_position
	_kill(enemy)
	var pickups: Array[ItemPickup] = _pickups_of(book)
	if not check_eq(pickups.size(), 1, "a won drop should place one pickup of its item"):
		return
	var at: Vector3 = pickups[0].global_position
	check(Vector2(at.x - fell_at.x, at.z - fell_at.z).length() < DROP_TOLERANCE, "the drop should lie where the enemy fell")
	check_approx(at.y, arena_floor_top(_arena), "the drop should lie on the floor", 0.05)


func test_a_drop_with_no_chance_never_drops() -> void:
	ProgressionState.bind_player(_player)
	var book: BookItemResource = _book(_ability())
	_kill(await _spawn_enemy(_archetype(book, 0.0)))
	check(_pickups_of(book).is_empty(), "a drop with no chance should never drop")


func test_no_drop_while_the_player_holds_the_ability() -> void:
	ProgressionState.bind_player(_player)
	var learned: AbilityResource = _ability()
	_asc.grant_ability(learned)
	var learned_book: BookItemResource = _book(learned)
	_kill(await _spawn_enemy(_archetype(learned_book, 1.0)))
	check(_pickups_of(learned_book).is_empty(), "a book for a learned ability should not drop")
	var from_gear: AbilityResource = _ability()
	var gear: GearItemResource = GearItemResource.new()
	gear.granted_abilities = [from_gear]
	_player.equipment_component.equip_gear(gear)
	var gear_book: BookItemResource = _book(from_gear)
	_kill(await _spawn_enemy(_archetype(gear_book, 1.0)))
	check(_pickups_of(gear_book).is_empty(), "a book for an ability the player's gear grants should not drop")


func test_no_drop_while_the_player_holds_the_passive() -> void:
	ProgressionState.bind_player(_player)
	_asc.add_passive(PASSIVE_SCENE)
	var book: BookItemResource = _passive_book()
	_kill(await _spawn_enemy(_archetype(book, 1.0)))
	check(_pickups_of(book).is_empty(), "a book for a learned passive should not drop")


func test_no_drop_while_the_item_lies_in_the_level() -> void:
	ProgressionState.bind_player(_player)
	var book: BookItemResource = _book(_ability())
	var archetype: EnemyResource = _archetype(book, 1.0)
	_kill(await _spawn_enemy(archetype))
	if not check_eq(_pickups_of(book).size(), 1, "setup: the first enemy should drop the book"):
		return
	_kill(await _spawn_enemy(archetype))
	check_eq(_pickups_of(book).size(), 1, "a book already lying in the level should not drop again")


func test_no_drop_before_a_player_is_bound() -> void:
	var book: BookItemResource = _book(_ability())
	_kill(await _spawn_enemy(_archetype(book, 1.0)))
	check(_pickups_of(book).is_empty(), "nothing should drop before the run knows its player")


func test_a_passive_book_is_equipped_and_kept_by_the_run() -> void:
	ProgressionState.bind_player(_player)
	var book: BookItemResource = _passive_book()
	check(ProgressionState.is_item_available(book), "a passive book teaching something new should be offered")
	if not check(_player.equipment_component.apply_item(book), "applying the passive book should succeed"):
		return
	check(_player.equipment_component.is_equipped(book), "a passive book should be equipped like gear")
	check(_asc.has_passive_scene(PASSIVE_SCENE), "the book should grant its passive")
	check(not book.can_apply(_player), "a passive book whose passive is held should not apply again")
	check(not ProgressionState.is_item_available(book), "a passive book whose passive the run holds should not be offered")
	var next: Character = _spawn_player()
	ProgressionState.bind_player(next)
	check(next.ability_system_component.has_passive_scene(PASSIVE_SCENE), "a fresh player should get the run's learned passive back")


func test_a_hit_effect_passive_applies_its_effects_to_melee_hits() -> void:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.effect_name = "test_hit_effect"
	effect.target_attribute = AttributeComponent.STAT_SPEED
	effect.magnitude = -0.5
	effect.duration = 30.0
	var passive: HitEffectPassive = HitEffectPassive.new()
	passive.trigger_tags = [&"ability.attack"]
	passive.effects_to_apply = [effect]
	_asc.add_passive_instance(passive)
	var dummy: Character = MELEE_SCENE.instantiate() as Character
	dummy.position = _player.global_position + Vector3(0.0, 0.0, -_adjacent_distance(dummy))
	autofree(dummy)
	_arena.add_child(dummy)
	disable_ai(dummy)
	dummy.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, DUMMY_HEALTH)
	dummy.knockback_component.max_knockback = 0.0
	_player.aim_direction = Vector3(0.0, 0.0, -1.0)
	await wait_until(func() -> bool: return dummy.is_on_floor(), "the dummy should settle")
	var struck: Array[bool] = [false]
	dummy.hurtbox.struck.connect(func(_damage: float) -> void: struck[0] = true)
	press_action(&"click")
	if not await wait_until(func() -> bool: return struck[0], "the player's attack should hit the dummy", ATTACK_FRAMES):
		return
	check(dummy.attribute_component.has_effect_instance(StringName(effect.effect_name)), "a melee hit should apply the passive's effect to the target")


# --- Helpers -----------------------------------------------------------------

func _spawn_player() -> Character:
	var player: Character = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	return player


## A melee enemy of archetype, settled on the floor ENEMY_DISTANCE from the player.
func _spawn_enemy(archetype: EnemyResource) -> Character:
	var enemy: Character = spawn(MELEE_SCENE, _arena, _player.global_position + Vector3(ENEMY_DISTANCE, 0.0, 0.0)) as Character
	disable_ai(enemy)
	enemy.enemy_resource = archetype
	await wait_until(func() -> bool: return enemy.is_on_floor(), "the enemy should settle")
	return enemy


func _kill(enemy: Character) -> void:
	enemy.hurtbox.receive_hit(LETHAL_DAMAGE, Vector3.ZERO)


## The pickups of item lying in the tree.
func _pickups_of(item: ItemResource) -> Array[ItemPickup]:
	var found: Array[ItemPickup] = []
	for node: Node in get_tree().get_nodes_in_group(ItemPickup.GROUP):
		var pickup: ItemPickup = node as ItemPickup
		if pickup != null and pickup.item == item and not pickup.is_queued_for_deletion():
			found.append(pickup)
	return found


## An enemy archetype for the melee scene dropping item at chance.
func _archetype(item: ItemResource, chance: float) -> EnemyResource:
	var drop: LootDrop = LootDrop.new()
	drop.item = item
	drop.chance = chance
	var archetype: EnemyResource = EnemyResource.new()
	archetype.scene = MELEE_SCENE
	archetype.item_drops = [drop]
	return archetype


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
	book.title = "Test Spell for Dummies"
	book.world_visual = BOOK_VISUAL
	return book


func _passive_book() -> BookItemResource:
	var book: BookItemResource = BookItemResource.new()
	book.id = StringName("test_passive_book_%d" % randi())
	book.max_purchases = 1
	book.granted_passives = [PASSIVE_SCENE]
	book.title = "Test Passive for Dummies"
	book.world_visual = BOOK_VISUAL
	return book


## Distance between the player and enemy standing just inside sword reach.
func _adjacent_distance(enemy: Character) -> float:
	var player_radius: float = float(_player.collision_shape_3d.shape.get("radius"))
	return float(enemy.collision_shape_3d.shape.get("radius")) + player_radius + 0.3
