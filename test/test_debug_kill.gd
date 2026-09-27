## The `debug_kill` action: pressing it makes UI.debug_kill_enemies() damage
## every living enemy through Hurtbox.receive_hit() (so hit reactions fire like
## real combat hits) by UI.DEBUG_KILL_DAMAGE, and never touches the player.
## Expected damage is read from UI.DEBUG_KILL_DAMAGE, and the action is driven
## by name, so rebinding its key or retuning the damage never breaks the suite.
extends "res://test/lib/test_suite.gd"

const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned health, well above the debug damage, so every hit is measurable.
const DUMMY_HEALTH: float = 100000.0

var _arena: Node3D
var _enemies: Array[Character] = []
var _player: Character


func before_each() -> void:
	_arena = load_arena()
	_enemies = [_spawn(MELEE_SCENE, Vector3(-3.0, 1.0, -4.0)), _spawn(MELEE_SCENE, Vector3(3.0, 1.0, -4.0))]
	_player = _spawn(PLAYER_SCENE, (_arena.get_node("PlayerSpawn") as Node3D).global_position)
	await wait_physics_frames(1)


func test_debug_kill_action_is_bound() -> void:
	if check(InputMap.has_action(&"debug_kill"), "the debug_kill action should exist in the InputMap"):
		check(not InputMap.action_get_events(&"debug_kill").is_empty(), "the debug_kill action should have at least one binding")


func test_damages_every_living_enemy_through_its_hurtbox_but_not_the_player() -> void:
	var strikes: Array[int] = [0]
	var enemy_health_before: Array[float] = []
	for enemy: Character in _enemies:
		enemy.hurtbox.struck.connect(func(_damage: float) -> void: strikes[0] += 1)
		enemy_health_before.append(_health(enemy))
	var player_health_before: float = _health(_player)
	UI.debug_kill_enemies()
	for i: int in range(_enemies.size()):
		check_approx(enemy_health_before[i] - _health(_enemies[i]), UI.DEBUG_KILL_DAMAGE, "enemy %d should lose UI.DEBUG_KILL_DAMAGE health" % i)
	check_eq(strikes[0], _enemies.size(), "every enemy should be struck through its Hurtbox exactly once")
	check_approx(_health(_player), player_health_before, "debug kill must not damage the player")


func test_pressing_the_debug_kill_action_triggers_it() -> void:
	var enemy: Character = _enemies[0]
	var health_before: float = _health(enemy)
	press_action(&"debug_kill")
	await wait_until(func() -> bool: return _health(enemy) < health_before, "pressing debug_kill should damage the enemies")


func _spawn(scene: PackedScene, at: Vector3) -> Character:
	var character: Character = spawn(scene, _arena, at) as Character
	disable_ai(character)
	character.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, DUMMY_HEALTH)
	return character


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
