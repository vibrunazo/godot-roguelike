## Thunder mage and its lightning bolt:
## - The mage is registered in GlobalVars.enemies and lands in the wave's
##   difficulty pool at its own difficulty level.
## - Its AI casts lightning at a player in the arena: a bolt spawns from its
##   weapon slot with the mage as shooter.
## - A bolt flies along its forward axis at its speed.
## - A bolt that hits the player deals its damage once and spawns its hit
##   effect at the impact.
## Values (difficulty, speed, damage) are read from the live resources, so
## retuning the mage never breaks the suite. Its colors, meshes and sounds
## are art and are verified visually (capture.py), not here.
extends "res://test/lib/test_suite.gd"

const MAGE_SCENE: PackedScene = preload("res://Enemy/enemy_thunder_mage.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const BOLT_SCENE: PackedScene = preload("res://Enemy/lightning_bolt_projectile.tscn")
## Frame budget for the AI to decide to cast (wait, meander, aim, cast).
const CAST_FRAMES: int = 1200
## Physics frames a free-flying bolt is observed for.
const FLIGHT_FRAMES: int = 5

var _arena: Node3D


func before_each() -> void:
	_arena = load_arena()


func test_mage_is_registered_as_a_spawnable_enemy() -> void:
	var resource: EnemyResource = GlobalVars.get_enemy_resource(MAGE_SCENE)
	if not check(resource != null, "GlobalVars.enemies should register the thunder mage"):
		return
	var pool: Dictionary = ProgressionState.build_difficulty_pool(GlobalVars.enemies)
	var tier: Array = pool.get(resource.difficulty_level, [])
	check(tier.has(resource), "the wave's difficulty pool should offer the mage at its own difficulty level")
	var instance: Character = autofree(resource.scene.instantiate()) as Character
	check(instance != null and instance.is_in_group("enemy"), "the registered scene should instantiate an enemy Character")


func test_mage_ai_casts_lightning_at_a_nearby_player() -> void:
	var mage: Character = spawn(MAGE_SCENE, _arena, (_arena.get_node("EnemySpawn") as Node3D).global_position) as Character
	mage.alert()
	spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position)
	if not await wait_until(func() -> bool: return not _bolts().is_empty(), "the mage's AI should cast a lightning bolt at the player", CAST_FRAMES):
		return
	var bolt: LightningBoltProjectile = _bolts()[0]
	check(bolt.shooter == mage, "the bolt's shooter should be the mage that cast it")


func test_bolt_spawns_at_the_weapon_slot() -> void:
	var mage: Character = spawn(MAGE_SCENE, _arena, (_arena.get_node("EnemySpawn") as Node3D).global_position) as Character
	disable_ai(mage)
	await wait_physics_frames(1)
	var spawner: ProjectileSpawnerComponent = mage.get_node("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	var slot_position: Vector3 = spawner.spawn_point.global_position
	spawner.spawn_projectile()
	if not check(not _bolts().is_empty(), "spawn_projectile() should spawn a lightning bolt"):
		return
	check(_bolts()[0].global_position.distance_to(slot_position) < 0.1, "the bolt should spawn at the spawner's spawn point")


func test_bolt_flies_forward_at_its_speed() -> void:
	var bolt: LightningBoltProjectile = spawn(BOLT_SCENE, _arena, Vector3(0.0, 3.0, 0.0)) as LightningBoltProjectile
	# Measure whole ticks only: start once the bolt has had its first tick.
	await wait_physics_frames(1)
	var start: Vector3 = bolt.global_position
	var forward: Vector3 = bolt.global_basis.z
	await wait_physics_frames(FLIGHT_FRAMES)
	var travelled: float = (bolt.global_position - start).dot(forward)
	var expected: float = bolt.speed * FLIGHT_FRAMES / Engine.physics_ticks_per_second
	check_approx(travelled, expected, "a bolt should travel speed * elapsed time along its forward axis", expected * 0.05)


func test_bolt_hitting_the_player_deals_its_damage_once_and_spawns_its_hit_effect() -> void:
	var player: Character = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	await wait_until(func() -> bool: return player.is_on_floor(), "player should land")
	var health_before: float = _health(player)
	var bolt: LightningBoltProjectile = spawn(BOLT_SCENE, _arena, player.global_position) as LightningBoltProjectile
	var damage: float = bolt.damage
	var effect_path: String = bolt.hit_effect_scene.resource_path
	if not await wait_signal(player.hurtbox.struck, "a bolt overlapping the player should hit them"):
		return
	await wait_physics_frames(2)
	check_approx(health_before - _health(player), damage, "the player should take the bolt's damage exactly once")
	var effects: int = 0
	for child: Node in get_children():
		if child.scene_file_path == effect_path:
			effects += 1
	check_eq(effects, 1, "the impact should spawn one hit effect")


## Lightning bolts currently in the world (spawned under the suite).
func _bolts() -> Array[LightningBoltProjectile]:
	var found: Array[LightningBoltProjectile] = []
	for child: Node in get_children():
		if child is LightningBoltProjectile and not child.is_queued_for_deletion():
			found.append(child as LightningBoltProjectile)
	return found


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
