## Scope Creep (the greatsword backpack boss with thunder mage riders):
## - its greatsword swing hits a player in front of it,
## - its lunge stab carries it toward its target and hits a player beyond
##   where the lunge ends,
## - its ranged riders shoot a player inside their range band (the bolt hits)
##   and hold fire while the player is closer or farther than the band,
## - its ranged riders turn in their seats toward the foe.
## Throwing and summoning riders are test_backpack_bosses. Distances, ranges
## and pacing are set by the test or read from the live nodes; the sword's
## look and the riders' palette are verified with capture.py.
extends "res://test/lib/test_suite.gd"

const BOSS_SCENE: PackedScene = preload("res://Enemy/scope_creep_boss.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned distances (meters from the boss) and rider pacing.
const CLOSE_DISTANCE: float = 2.0
const LUNGE_OVERSHOOT: float = 1.0
const SHOT_DISTANCE: float = 8.0
const TEST_RIDER_COOLDOWN: float = 0.1
## Physics frames a rider band check watches for a shot that must not come.
const HOLD_FIRE_FRAMES: int = 60
## Largest angle, in degrees, between a turned rider and the foe.
const FACING_TOLERANCE: float = 15.0
## Generous budget for attacks, flights and settling.
const LONG_FRAMES: int = 600
## Test-owned health for the test player, so boss attacks never end the run.
const PLAYER_HEALTH: float = 100000.0

var _arena: Node3D
var _floor_top: float


func before_each() -> void:
	_arena = load_arena()
	_floor_top = arena_floor_top(_arena)


func after_each() -> void:
	UI.resume_game()


func test_the_greatsword_swing_hits_a_player_in_front() -> void:
	var boss: Character = await _settled_boss()
	_backpack(boss).unboard_riders()
	var player: Character = await _grounded_player(boss.global_position + _facing(boss) * CLOSE_DISTANCE)
	boss.current_target = player
	var swing: CharacterAttack = boss.state_machine.get_node("EnemySwordSwing") as CharacterAttack
	var hits: Array[int] = [0]
	swing.get_attack_component().hit_landed.connect(func(_target: Node) -> void: hits[0] += 1)
	boss.state_machine.request_state(swing.name)
	await wait_until(func() -> bool: return hits[0] > 0, "the greatsword swing should hit a player in front of the boss", LONG_FRAMES)


func test_the_lunge_stab_carries_the_boss_in_and_hits_beyond_the_lunge() -> void:
	var boss: Character = await _settled_boss()
	_backpack(boss).unboard_riders()
	var stab: CharacterAttack = boss.state_machine.get_node("EnemyLungeStab") as CharacterAttack
	if not check(stab.has_lunge(), "setup: the stab should lunge"):
		return
	var lunge_distance: float = stab.dash_speed * stab.dash_duration
	var facing: Vector3 = _facing(boss)
	var player: Character = await _grounded_player(boss.global_position + facing * (lunge_distance + LUNGE_OVERSHOOT))
	player.knockback_component.max_knockback = 0.0
	boss.current_target = player
	var start: Vector3 = boss.global_position
	var hits: Array[int] = [0]
	stab.get_attack_component().hit_landed.connect(func(_target: Node) -> void: hits[0] += 1)
	boss.state_machine.request_state(stab.name)
	if not await wait_until(func() -> bool: return hits[0] > 0, "the lunge stab should hit a player beyond where its lunge ends", LONG_FRAMES):
		return
	if not await wait_until(func() -> bool: return boss.state_machine.state != stab, "the stab should end", LONG_FRAMES):
		return
	# Landing the hit slows the attacker (self hitstop), so the lunge may
	# fall short of its full distance, but it must carry the boss well in.
	var travelled: float = (boss.global_position - start).dot(facing)
	check(travelled > lunge_distance * 0.5, "the lunge should carry the boss toward its target (moved %.2f m of a %.2f m lunge)" % [travelled, lunge_distance])


func test_ranged_riders_shoot_a_player_in_their_band_and_hold_fire_outside_it() -> void:
	var boss: Character = await _settled_boss()
	var riders: Array[BackpackRider] = _ranged_riders(boss)
	if not check(not riders.is_empty(), "setup: the boss should carry ranged riders"):
		return
	for rider: BackpackRider in riders:
		rider.cooldown = TEST_RIDER_COOLDOWN
		rider.require_clear_shot = false
	# The band is out of reach before the player arrives, so no shot can
	# start while it lands.
	_set_band(riders, 0.0, SHOT_DISTANCE * 0.5)
	var player: Character = await _grounded_player(boss.global_position + _facing(boss) * SHOT_DISTANCE)
	await _check_holding_fire(riders, "riders must not shoot a player farther than their band")
	_set_band(riders, SHOT_DISTANCE * 2.0, SHOT_DISTANCE * 3.0)
	await _check_holding_fire(riders, "riders must not shoot a player closer than their band")
	var shooters: Array[Node] = []
	var watch_projectiles: Callable = func(node: Node) -> void:
		if node is Projectile:
			shooters.append((node as Projectile).shooter)
	get_tree().node_added.connect(watch_projectiles)
	_set_band(riders, 0.0, SHOT_DISTANCE * 2.0)
	var struck: bool = await wait_signal(player.hurtbox.struck, "a rider's bolt should hit a player inside its band", LONG_FRAMES)
	get_tree().node_added.disconnect(watch_projectiles)
	if struck:
		check(shooters.has(boss), "the rider's bolt should be credited to the boss")


func test_ranged_riders_turn_in_their_seats_toward_the_foe() -> void:
	var boss: Character = await _settled_boss()
	var riders: Array[BackpackRider] = _ranged_riders(boss)
	if not check(not riders.is_empty(), "setup: the boss should carry ranged riders"):
		return
	for rider: BackpackRider in riders:
		if not check(rider.turn_speed > 0.0, "setup: %s should turn toward its foe" % rider.name):
			return
	# An out-of-reach band: the riders only turn, they never shoot.
	_set_band(riders, 0.0, 0.0)
	var side: Vector3 = _facing(boss).cross(Vector3.UP)
	var player: Character = await _grounded_player(boss.global_position + side * SHOT_DISTANCE)
	for rider: BackpackRider in riders:
		await wait_until(func() -> bool: return _angle_to(rider.body, player) <= FACING_TOLERANCE, "%s should turn in its seat toward the foe" % rider.name, LONG_FRAMES)


# --- helpers -------------------------------------------------------------------

## The boss standing at the arena centre with its AI stopped.
func _settled_boss() -> Character:
	var boss: Character = spawn(BOSS_SCENE, _arena, Vector3(0.0, _floor_top + 3.0, 0.0)) as Character
	disable_ai(boss)
	await wait_until(func() -> bool: return boss.is_on_floor() and boss.state_machine.state == boss.state_machine.initial_state, "the boss should land and settle", LONG_FRAMES)
	return boss


func _backpack(boss: Character) -> BackpackRiders:
	return boss.get_node("BackpackRiders") as BackpackRiders


## The boss's riders that shoot (with a payload).
func _ranged_riders(boss: Character) -> Array[BackpackRider]:
	var ranged: Array[BackpackRider] = []
	for rider: BackpackRider in _backpack(boss).riders:
		if rider.payload_scene != null:
			ranged.append(rider)
	return ranged


func _set_band(riders: Array[BackpackRider], min_range: float, max_range: float) -> void:
	for rider: BackpackRider in riders:
		rider.min_range = min_range
		rider.max_range = max_range


## Watches HOLD_FIRE_FRAMES physics frames and fails if any rider attacks.
func _check_holding_fire(riders: Array[BackpackRider], message: String) -> void:
	var attacked: bool = false
	for frame: int in HOLD_FIRE_FRAMES:
		await get_tree().physics_frame
		for rider: BackpackRider in riders:
			attacked = attacked or rider.is_attacking() or not rider.is_ready()
	check(not attacked, message)


## The boss's horizontal facing.
func _facing(boss: Character) -> Vector3:
	var front: Vector3 = boss.mesh_mount.global_basis.z
	front.y = 0.0
	return front.normalized()


## Degrees between node's horizontal front (+Z) and the direction to target.
func _angle_to(node: Node3D, target: Node3D) -> float:
	var front: Vector3 = node.global_basis.z
	front.y = 0.0
	var to_target: Vector3 = target.global_position - node.global_position
	to_target.y = 0.0
	return rad_to_deg(front.normalized().angle_to(to_target.normalized()))


## A player standing at the given point with live input off and test-owned
## health high enough to survive the boss.
func _grounded_player(at: Vector3) -> Character:
	var player: Character = spawn(PLAYER_SCENE, _arena, at) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, PLAYER_HEALTH)
	await wait_until(func() -> bool: return player.is_on_floor(), "the player should land")
	return player
