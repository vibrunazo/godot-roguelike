## Rotation speed limit: Character.look_at_target / look_toward_direction turn
## the mesh mount by at most get_rotation_speed() * delta per call, never snap,
## converge over repeated calls, preserve the mount's scale, and treat zero
## directions as no-ops. get_rotation_speed() reads the AttributeComponent's
## rotation_speed stat, so every character must seed it from its exports.
##
## Reference migration for the TestSuite harness: every expected value is
## either read from the live node or set by the test itself, so designers can
## retune any character's rotation speed without breaking this suite.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const BOSS_SCENE: PackedScene = preload("res://Enemy/akira_boss.tscn")

## Step passed to the look_* calls, so expectations are exact regardless of
## the physics tick the runner uses.
const STEP_DT: float = 1.0 / 60.0
## Test-owned speeds (deg/sec) for the relative comparisons; deliberately not
## the characters' configured values.
const FAST_SPEED: float = 600.0
const SLOW_SPEED: float = 120.0

var _arena: Node3D


func before_each() -> void:
	_arena = load_arena()


## Spawns a character in the arena with its AI mind stopped, so only this
## suite's direct look_* calls rotate it.
func _spawn_character(scene: PackedScene, marker: String) -> Character:
	var at: Vector3 = (_arena.get_node(marker) as Node3D).global_position
	var character: Character = spawn(scene, _arena, at) as Character
	disable_ai(character)
	return character


func test_rotation_speed_is_seeded_from_attributes() -> void:
	var characters: Array[Character] = [
		_spawn_character(PLAYER_SCENE, "PlayerSpawn"),
		_spawn_character(MELEE_SCENE, "EnemySpawn"),
		_spawn_character(BOSS_SCENE, "EnemySpawn"),
	]
	await wait_physics_frames(1)
	for c: Character in characters:
		var configured: float = c.attribute_component.get_base(AttributeComponent.STAT_ROTATION_SPEED)
		check(configured > 0.0, "%s rotation_speed base must be seeded above zero (a missed seed reads 0)" % c.name)
		check_approx(c.get_rotation_speed(), configured, "%s get_rotation_speed() should read the rotation_speed stat" % c.name)


func test_single_call_never_snaps() -> void:
	var characters: Array[Character] = [
		_spawn_character(PLAYER_SCENE, "PlayerSpawn"),
		_spawn_character(BOSS_SCENE, "EnemySpawn"),
	]
	await wait_physics_frames(1)
	for c: Character in characters:
		var before: Vector3 = _flat_facing(c)
		var behind: Vector3 = c.mesh_mount.global_position - before * 5.0
		c.look_at_target(behind, STEP_DT)
		var desired: Vector3 = (behind - c.mesh_mount.global_position).normalized()
		check(_flat_facing(c).dot(desired) < 0.0, "%s must not snap toward a target behind it in one call" % c.name)


func test_single_step_advances_speed_times_delta() -> void:
	var characters: Array[Character] = [
		_spawn_character(PLAYER_SCENE, "PlayerSpawn"),
		_spawn_character(BOSS_SCENE, "EnemySpawn"),
	]
	await wait_physics_frames(1)
	for c: Character in characters:
		var expected_step: float = c.get_rotation_speed() * STEP_DT
		check_approx(_side_step(c), expected_step, "%s one step toward a perpendicular direction should turn speed * delta degrees" % c.name, 0.5)


func test_slower_character_needs_more_steps_to_converge() -> void:
	var fast: Character = _spawn_character(PLAYER_SCENE, "PlayerSpawn")
	var slow: Character = _spawn_character(BOSS_SCENE, "EnemySpawn")
	await wait_physics_frames(1)
	fast.attribute_component.set_base(AttributeComponent.STAT_ROTATION_SPEED, FAST_SPEED)
	slow.attribute_component.set_base(AttributeComponent.STAT_ROTATION_SPEED, SLOW_SPEED)
	# A half turn needs 180 / (speed * dt) steps; allow a couple extra for the
	# final partial step and the alignment threshold.
	var fast_steps: int = _converge_behind(fast, ceili(180.0 / (FAST_SPEED * STEP_DT)) + 2)
	var slow_steps: int = _converge_behind(slow, ceili(180.0 / (SLOW_SPEED * STEP_DT)) + 2)
	if not check(fast_steps > 0, "fast character should converge on the opposite facing within its step budget"):
		return
	if not check(slow_steps > 0, "slow character should converge on the opposite facing within its step budget"):
		return
	check(slow_steps > fast_steps, "slower rotation speed should need more steps (slow %d, fast %d)" % [slow_steps, fast_steps])


func test_long_turn_preserves_mount_scale() -> void:
	# The boss mount is scaled; rebuilding the basis would reset that scale.
	var boss: Character = _spawn_character(BOSS_SCENE, "EnemySpawn")
	await wait_physics_frames(1)
	var scale_before: Vector3 = boss.mesh_mount.global_transform.basis.get_scale()
	var budget: int = ceili(180.0 / (boss.get_rotation_speed() * STEP_DT)) + 2
	check(_converge_behind(boss, budget) > 0, "boss should converge on the opposite facing")
	var scale_after: Vector3 = boss.mesh_mount.global_transform.basis.get_scale()
	check(scale_after.is_equal_approx(scale_before), "mount scale must survive a long turn (%s -> %s)" % [scale_before, scale_after])


func test_zero_direction_is_noop() -> void:
	var player: Character = _spawn_character(PLAYER_SCENE, "PlayerSpawn")
	await wait_physics_frames(1)
	var before: Vector3 = _flat_facing(player)
	player.look_toward_direction(Vector3.ZERO, STEP_DT)
	player.look_at_target(player.mesh_mount.global_position, STEP_DT)
	check(_flat_facing(player).is_equal_approx(before), "zero / degenerate directions must leave facing untouched")


## Turns the character toward the direction 90 degrees to its side with one
## speed-limited step and returns how far it actually turned, in degrees.
func _side_step(c: Character) -> float:
	var before: Vector3 = _flat_facing(c)
	c.look_toward_direction(Vector3(-before.z, 0.0, before.x), STEP_DT)
	return rad_to_deg(acos(clampf(before.dot(_flat_facing(c)), -1.0, 1.0)))


## Turns the character toward a point directly behind it until aligned
## (dot >= 0.999) or max_steps run out. Returns the steps used, or -1.
func _converge_behind(c: Character, max_steps: int) -> int:
	var behind: Vector3 = c.mesh_mount.global_position - _flat_facing(c) * 5.0
	for i: int in range(max_steps):
		c.look_at_target(behind, STEP_DT)
		if _flat_facing(c).dot((behind - c.mesh_mount.global_position).normalized()) >= 0.999:
			return i + 1
	return -1


## Current mount facing (+Z model front) flattened to a unit XZ vector.
func _flat_facing(c: Character) -> Vector3:
	var forward: Vector3 = c.mesh_mount.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()
