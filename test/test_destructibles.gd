## Destructibles, through the explosive barrel (the first one):
## - a hit that leaves health over does not break it; the hit that empties the
##   health pool starts its fuse, and when the fuse ends it releases its
##   payload and frees itself,
## - a destructible with no payload just disappears,
## - both teams can break it: a blast that only hits the player's side and one
##   that only hits the enemies' side each destroy it,
## - its explosion hurts and sets fire to every character in range (enemies and
##   the player), and spares those out of range,
## - an explosion breaks the barrels in range, which explode in turn (a chain
##   reaction), and leaves barrels out of range alone,
## - the player's fireball, fired from where the player casts it, breaks a
##   barrel: the prop's solid collision body does not stop it like a wall,
## - a barrel is solid: a character walking into it is stopped.
## Health, fuse times and blast sizes come from the scenes or are set by the
## test; nothing here asserts tuning.
extends "res://test/lib/test_suite.gd"

const BARREL_SCENE: PackedScene = preload("res://Levels/Decorators/explosive_barrel.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const AOE_SCENE: PackedScene = preload("res://Hazards/ground_damage_aoe.tscn")
const BURN_EFFECT: GameplayEffect = preload("res://Components/effect_fire_burn.tres")
const FIREBALL: AbilityResource = preload("res://Abilities/AbilityResources/ability_fireball.tres")
## Test-owned fuse, long enough to observe between the hit and the break.
const TEST_FUSE: float = 0.3
## Test-owned health for characters, so the blast can never defeat them.
const SURVIVOR_HEALTH: float = 10000.0
## Gap between barrels standing side by side (they are 1 m wide).
const NEIGHBOUR_GAP: float = 1.5
## Distance past the blast radius that counts as out of range.
const SAFE_MARGIN: float = 4.0
## Physics ticks allowed for an area to register a fresh overlap.
const DETECT_FRAMES: int = 20
## Distance from the player at which the test barrel stands.
const SHOT_DISTANCE: float = 5.0
## Frame budget for a projectile's flight to the barrel.
const FLIGHT_FRAMES: int = 300
## Physics ticks the player spends walking into a barrel.
const WALK_FRAMES: int = 90

var _arena: Node3D
var _floor_top: float


func before_each() -> void:
	_arena = load_arena()
	_floor_top = arena_floor_top(_arena)


func test_a_barrel_breaks_after_its_fuse_once_its_health_is_gone() -> void:
	var barrel: Destructible = _spawn_barrel(Vector3(0.0, _floor_top, 0.0))
	barrel.fuse_time = TEST_FUSE
	var events: Array[String] = []
	barrel.destroyed.connect(func() -> void: events.append("destroyed"))
	barrel.broke.connect(func() -> void: events.append("broke"))
	var hurtbox: Hurtbox = barrel.get_node("Hurtbox") as Hurtbox
	var health: float = _barrel_health(barrel)
	hurtbox.receive_hit(health * 0.5, Vector3.ZERO)
	check(events.is_empty() and hurtbox.is_alive(), "a hit that leaves health over should not destroy the barrel")
	hurtbox.receive_hit(health, Vector3.ZERO)
	check_eq(events, ["destroyed"] as Array[String], "emptying the health pool should start the fuse, not break the barrel at once")
	check(not hurtbox.receive_hit(health, Vector3.ZERO), "a burning-down barrel should no longer take hits")
	await wait_until(func() -> bool: return events.size() == 2, "the barrel should break when its fuse ends", _frames_for(TEST_FUSE))
	await wait_physics_frames(2)
	check(not is_instance_valid(barrel), "a broken barrel should free itself")


func test_a_destructible_without_a_payload_just_disappears() -> void:
	var barrel: Destructible = _spawn_barrel(Vector3(0.0, _floor_top, 0.0))
	barrel.break_payload = null
	barrel.fuse_time = 0.0
	(barrel.get_node("Hurtbox") as Hurtbox).receive_hit(_barrel_health(barrel), Vector3.ZERO)
	await wait_signal(barrel.broke, "a destroyed barrel should break", _frames_for(TEST_FUSE))
	await wait_physics_frames(DETECT_FRAMES)
	check(_blasts().is_empty(), "a destructible with no payload should release nothing")


func test_a_blast_that_only_hits_the_players_side_breaks_a_barrel() -> void:
	await _check_blast_breaks_barrel(true)


func test_a_blast_that_only_hits_the_enemies_side_breaks_a_barrel() -> void:
	await _check_blast_breaks_barrel(false)


func test_the_explosion_hurts_and_burns_everyone_in_range_and_spares_the_rest() -> void:
	var barrel: Destructible = _spawn_barrel(Vector3(0.0, _floor_top, 0.0))
	var radius: float = _blast_radius(barrel)
	var near: Vector3 = Vector3(radius * 0.5, _floor_top + 0.1, 0.0)
	var far: Vector3 = Vector3(radius + SAFE_MARGIN, _floor_top + 0.1, 0.0)
	var victims: Array[Character] = [_spawn_enemy(near), _spawn_player(near + Vector3(0.0, 0.0, 1.0))]
	var bystander: Character = _spawn_enemy(far)
	var before: Array[float] = [_health(victims[0]), _health(victims[1]), _health(bystander)]
	var fuse_frames: int = _frames_for(barrel.fuse_time) + DETECT_FRAMES
	(barrel.get_node("Hurtbox") as Hurtbox).receive_hit(_barrel_health(barrel), Vector3.ZERO)
	for victim: Character in victims:
		await wait_until(func() -> bool: return victim.attribute_component.has_effect_instance(StringName(BURN_EFFECT.effect_name)), "a character in range should be set on fire", fuse_frames)
	check(_health(victims[0]) < before[0], "the enemy in range should take blast damage")
	check(_health(victims[1]) < before[1], "the player in range should take blast damage")
	check_approx(_health(bystander), before[2], "a character out of range should be unharmed")
	check(not bystander.attribute_component.has_effect_instance(StringName(BURN_EFFECT.effect_name)), "a character out of range should not burn")


func test_an_explosion_sets_off_the_barrels_in_range_but_not_those_out_of_range() -> void:
	var first: Destructible = _spawn_barrel(Vector3(0.0, _floor_top, 0.0))
	var fuse_frames: int = _frames_for(first.fuse_time) + DETECT_FRAMES
	var isolated: Destructible = _spawn_barrel(Vector3(_blast_radius(first) + SAFE_MARGIN, _floor_top, 0.0))
	var labelled: Dictionary[String, Destructible] = {
		"neighbour": _spawn_barrel(Vector3(NEIGHBOUR_GAP, _floor_top, 0.0)),
		"second neighbour": _spawn_barrel(Vector3(NEIGHBOUR_GAP * 2.0, _floor_top, 0.0)),
		"isolated": isolated,
	}
	var exploded: Array[String] = []
	for label: String in labelled:
		labelled[label].broke.connect(func() -> void: exploded.append(label))
	(first.get_node("Hurtbox") as Hurtbox).receive_hit(_barrel_health(first), Vector3.ZERO)
	await wait_until(func() -> bool: return exploded.size() >= 2, "the blast should chain through the barrels in range", fuse_frames * 3)
	check(exploded.has("neighbour") and exploded.has("second neighbour"), "the barrels beside the first should explode too (exploded: %s)" % [exploded])
	await wait_physics_frames(fuse_frames)
	check(not exploded.has("isolated") and is_instance_valid(isolated) and _barrel_health(isolated) > 0.0, "a barrel out of range should be untouched")


func test_the_players_fireball_breaks_a_barrel() -> void:
	var player: Character = _spawn_player(Vector3(0.0, _floor_top + 1.0, 0.0))
	await wait_until(player.is_on_floor, "the player should land", DETECT_FRAMES * 3)
	var origin: Vector3 = (player.ability_system_component.slots[0] as AbilityCastState).cast_origin.global_position
	var barrel: Destructible = _spawn_barrel(Vector3(origin.x, _floor_top, origin.z + SHOT_DISTANCE))
	barrel.break_payload = null
	var lethal: PayloadPropertyOverride = PayloadPropertyOverride.new()
	lethal.property = &"damage"
	lethal.float_value = _barrel_health(barrel)
	var overrides: Array[PayloadPropertyOverride] = FIREBALL.payload_overrides.duplicate()
	overrides.append(lethal)
	PayloadSpawner.spawn(FIREBALL.payload_scene, player, origin, Vector3.BACK, overrides)
	await wait_signal(barrel.destroyed, "a fireball flying into a barrel should destroy it", FLIGHT_FRAMES)


func test_a_character_walking_into_a_barrel_is_stopped() -> void:
	var player: Character = _spawn_player(Vector3(0.0, _floor_top + 1.0, 0.0))
	await wait_until(player.is_on_floor, "the player should land", DETECT_FRAMES * 3)
	var barrel: Destructible = _spawn_barrel(Vector3(0.0, _floor_top, SHOT_DISTANCE))
	player.move_direction = Vector3.BACK
	await wait_physics_frames(WALK_FRAMES)
	player.move_direction = Vector3.ZERO
	check(player.global_position.z < barrel.global_position.z, "the barrel should block the player (player z %.2f, barrel z %.2f)" % [player.global_position.z, barrel.global_position.z])


## Drops a blast that hits one team's hurtbox layer only onto a fresh barrel
## and checks the barrel is destroyed anyway.
func _check_blast_breaks_barrel(player_side: bool) -> void:
	var barrel: Destructible = _spawn_barrel(Vector3(0.0, _floor_top, 0.0))
	barrel.break_payload = null
	var blast: GroundDamageArea = AOE_SCENE.instantiate() as GroundDamageArea
	autofree(blast)
	blast.hits_all = false
	blast.can_hit_player = player_side
	blast.can_hit_enemies = not player_side
	blast.damage = _barrel_health(barrel)
	blast.position = Vector3(0.0, _floor_top, 0.0)
	_arena.add_child(blast)
	await wait_signal(barrel.destroyed, "a blast that only hits the %s side should still destroy the barrel" % ("player's" if player_side else "enemies'"), DETECT_FRAMES)


func _spawn_barrel(at: Vector3) -> Destructible:
	var barrel: Destructible = spawn(BARREL_SCENE, _arena, at) as Destructible
	return barrel


func _spawn_enemy(at: Vector3) -> Character:
	var enemy: Character = spawn(MELEE_SCENE, _arena, at) as Character
	disable_ai(enemy)
	enemy.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, SURVIVOR_HEALTH)
	return enemy


func _spawn_player(at: Vector3) -> Character:
	var player: Character = spawn(PLAYER_SCENE, _arena, at) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, SURVIVOR_HEALTH)
	return player


## The radius of the blast the barrel releases, read off a throwaway copy.
func _blast_radius(barrel: Destructible) -> float:
	var blast: GroundDamageArea = barrel.break_payload.instantiate() as GroundDamageArea
	var radius: float = blast.radius
	blast.free()
	return radius


## Blasts currently in the world (the suite hosts the payloads it spawns).
func _blasts() -> Array[Node]:
	return get_children().filter(func(child: Node) -> bool: return child is GroundDamageArea)


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


func _barrel_health(barrel: Destructible) -> float:
	return barrel.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## Physics frames covering the given game time, plus a small margin.
func _frames_for(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 5
