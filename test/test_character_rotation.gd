## Focused verification for the rotation speed attribute system.
## - Player exposes 720 deg/sec and the boss 90 deg/sec via get_rotation_speed;
##   untouched enemies fall back to the 360 deg/sec default (proves the new
##   stat seeds through _seed_from_exports instead of reading back zero).
## - look_at_target / look_toward_direction never snap: one call advances
##   facing by at most speed * delta toward the desired direction.
## - Repeated calls converge on the desired facing, the boss turns slower than
##   the player, zero directions are safe no-ops, and long turns preserve the
##   (scaled) mount basis.
extends Node

const PlayerScene: PackedScene = preload("res://Player/player.tscn")
const MeleeEnemyScene: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const BossScene: PackedScene = preload("res://Enemy/akira_boss.tscn")

## Fixed step passed to the look_* calls so expectations stay exact no matter
## which physics tick the headless runner uses.
const STEP_DT: float = 1.0 / 60.0


func _ready() -> void:
	print("====================================================")
	print("  STARTING CHARACTER ROTATION VERIFICATION SUITE")
	print("====================================================")
	var player: Character = PlayerScene.instantiate() as Character
	var melee: Character = MeleeEnemyScene.instantiate() as Character
	var boss: Character = BossScene.instantiate() as Character
	add_child(player)
	add_child(melee)
	add_child(boss)
	# Freeze AI minds before the first physics tick so only this suite's
	# direct look_* calls rotate the characters (deterministic facings).
	if melee.ai_state_machine != null:
		melee.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if boss.ai_state_machine != null:
		boss.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame
	if not _part_speeds_wired(player, melee, boss):
		return
	if not _part_no_snap(player, boss):
		return
	if not _part_clamped_step(player, boss):
		return
	if not _part_convergence(player, boss):
		return
	if not _part_zero_noop(player):
		return
	player.queue_free()
	melee.queue_free()
	boss.queue_free()
	await get_tree().process_frame
	print("ALL CHARACTER ROTATION CHECKS PASSED.")
	get_tree().quit(0)


## Player 720 / boss 90 are the requested wirings; the melee default proves
## the rotation_speed stat seeds for every character (a missed seed reads 0).
func _part_speeds_wired(player: Character, melee: Character, boss: Character) -> bool:
	print("\n>>> PART 1: Rotation speeds wired (player 720, boss 90, default 360)")
	if not is_equal_approx(player.get_rotation_speed(), 720.0):
		return _fail("Player rotation speed should be 720 deg/sec, got %f." % player.get_rotation_speed())
	if not is_equal_approx(boss.get_rotation_speed(), 90.0):
		return _fail("Boss rotation speed should be 90 deg/sec, got %f." % boss.get_rotation_speed())
	if not is_equal_approx(melee.get_rotation_speed(), 360.0):
		return _fail("Default rotation speed should be 360 deg/sec, got %f." % melee.get_rotation_speed())
	print("Rotation speeds verified (player 720, boss 90, default 360).")
	return true


## One facing request must not snap: after a single step toward a target
## directly behind, the character still faces the away hemisphere.
func _part_no_snap(player: Character, boss: Character) -> bool:
	print("\n>>> PART 2: Single call never snaps (desired direction only)")
	for c: Character in [player, boss]:
		var before: Vector3 = _flat_facing(c)
		var behind: Vector3 = c.mesh_mount.global_position - before * 5.0
		c.look_at_target(behind, STEP_DT)
		var desired: Vector3 = (behind - c.mesh_mount.global_position).normalized()
		var alignment: float = _flat_facing(c).dot(desired)
		if alignment >= 0.0:
			return _fail("%s snapped toward target in one call (alignment %f)." % [c.name, alignment])
	print("No-snap verified (player and boss still face away after one step).")
	return true


## One step toward a perpendicular desired direction must advance facing by
## exactly speed * delta, and the boss step must be smaller than the player's.
func _part_clamped_step(player: Character, boss: Character) -> bool:
	print("\n>>> PART 3: Single step advances exactly speed * delta")
	var player_step: float = _side_step(player)
	var boss_step: float = _side_step(boss)
	if player_step < 0.0 or boss_step < 0.0:
		return _fail("Side-step setup produced a degenerate facing.")
	var want_player: float = 720.0 / 60.0
	var want_boss: float = 90.0 / 60.0
	if absf(player_step - want_player) > 0.5:
		return _fail("Player step should be ~%f deg, got %f." % [want_player, player_step])
	if absf(boss_step - want_boss) > 0.5:
		return _fail("Boss step should be ~%f deg, got %f." % [want_boss, boss_step])
	if not boss_step < player_step:
		return _fail("Boss step (%f) should be smaller than player step (%f)." % [boss_step, player_step])
	print("Clamped steps verified (player ~%f deg, boss ~%f deg)." % [player_step, boss_step])
	return true


## Repeated requests converge on an opposite facing; the boss needs more steps
## than the player. Also proves long turns keep the scaled mount basis intact.
func _part_convergence(player: Character, boss: Character) -> bool:
	print("\n>>> PART 4: Repeated calls converge; boss turns slower")
	var boss_scale_before: Vector3 = boss.mesh_mount.global_transform.basis.get_scale()
	var player_steps: int = _converge_behind(player, 40)
	var boss_steps: int = _converge_behind(boss, 160)
	if player_steps < 0:
		return _fail("Player never converged on the opposite facing.")
	if boss_steps < 0:
		return _fail("Boss never converged on the opposite facing.")
	if not boss_steps > player_steps:
		return _fail("Boss (%d steps) should converge slower than player (%d steps)." % [boss_steps, player_steps])
	var boss_scale_after: Vector3 = boss.mesh_mount.global_transform.basis.get_scale()
	if not boss_scale_after.is_equal_approx(boss_scale_before):
		return _fail("Boss mount scale drifted while turning (%s -> %s)." % [str(boss_scale_before), str(boss_scale_after)])
	print("Convergence verified (player %d steps, boss %d steps); boss scale held %s." % [player_steps, boss_steps, str(boss_scale_after)])
	return true


## Zero / degenerate directions must leave the mount basis exactly untouched.
func _part_zero_noop(player: Character) -> bool:
	print("\n>>> PART 5: Zero direction is a safe no-op")
	var before: Vector3 = _flat_facing(player)
	player.look_toward_direction(Vector3.ZERO, STEP_DT)
	player.look_at_target(player.mesh_mount.global_position, STEP_DT)
	var after: Vector3 = _flat_facing(player)
	if not after.is_equal_approx(before):
		return _fail("Zero direction changed facing (%s -> %s)." % [str(before), str(after)])
	print("Zero-direction no-op verified.")
	return true


## Turns the character 90 degrees to the side of its current facing with one
## speed-limited step and returns how far it actually turned, in degrees.
func _side_step(c: Character) -> float:
	var before: Vector3 = _flat_facing(c)
	var side: Vector3 = Vector3(-before.z, 0.0, before.x)
	c.look_toward_direction(side, STEP_DT)
	var after: Vector3 = _flat_facing(c)
	return rad_to_deg(acos(clampf(before.dot(after), -1.0, 1.0)))


## Turns the character toward a target directly behind it until aligned
## (dot >= 0.999) or the frame budget runs out. Returns steps used, or -1.
func _converge_behind(c: Character, max_steps: int) -> int:
	var behind: Vector3 = c.mesh_mount.global_position - _flat_facing(c) * 5.0
	for i: int in range(max_steps):
		c.look_at_target(behind, STEP_DT)
		var desired: Vector3 = (behind - c.mesh_mount.global_position).normalized()
		if _flat_facing(c).dot(desired) >= 0.999:
			return i + 1
	return -1


## Current mount facing (+Z model front) flattened to a unit XZ vector.
func _flat_facing(c: Character) -> Vector3:
	var fwd: Vector3 = c.mesh_mount.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized()


func _fail(message: String) -> bool:
	printerr("TEST FAILED: ", message)
	get_tree().quit(1)
	return false
