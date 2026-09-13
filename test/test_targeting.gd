extends Node

## Targeting system test: auto-aim acquisition, range gating, retarget
## cooldown, attack target freeze, attack facing, player-only reticle,
## and target clearing on death.


func _ready() -> void:
	print("--- RUNNING TARGETING TEST ---")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	# Remove the wave spawner so no randomly placed enemies disturb distances.
	var wave: Node = level.get_node_or_null("WaveObjective")
	if wave != null:
		wave.queue_free()

	var player: Character = level.get_node("Player") as Character
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	var camera: Camera3D = player.get_viewport().get_camera_3d()

	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break
	if sm.state.name != "PlayerRun":
		await _fail(level, "Player did not enter PlayerRun.")
		return
	if camera == null:
		await _fail(level, "No active 3D camera found.")
		return

	var home: Vector3 = player.global_position
	# Spawned sequentially (never two add+teleport pairs in the same frame):
	# same-frame double spawns displace the second body in this project setup.
	var enemy_a: Character = await _spawn_enemy(level, home + Vector3(3.0, 0.0, 0.0))
	var enemy_b: Character = await _spawn_enemy(level, home + Vector3(-4.0, 0.0, 0.0))

	# =====================================================================
	# PART 1: Acquire nearest enemy in range + player-only reticle
	# =====================================================================
	print("\n>>> PART 1: Nearest acquisition and reticle")
	player.target_retarget_cooldown = 10.0
	await _wait_frames(40)
	if player.current_target != enemy_a:
		await _fail(level, "Player did not acquire nearest enemy A.")
		return
	if enemy_b.current_target != null:
		await _fail(level, "Enemy B unexpectedly acquired an auto-aim target (auto-aim should be disabled by default on enemies).")
		return
	var reticle: TargetReticle = VfxManager.target_reticle
	if reticle == null:
		await _fail(level, "VfxManager spawned no target reticle.")
		return
	if reticle.target != enemy_a:
		await _fail(level, "Reticle does not follow the player target.")
		return
	if not reticle.visible:
		await _fail(level, "Reticle not visible while a target is acquired.")
		return
	var all_reticles: Array[Node] = get_tree().root.find_children("*", "TargetReticle", true, false)
	if all_reticles.size() != 1:
		await _fail(level, "Expected exactly 1 player-only reticle, found %d." % all_reticles.size())
		return
	print("Acquired nearest enemy; single player-only reticle follows it.")

	# =====================================================================
	# PART 2: Retarget cooldown blocks flicker, force re-evaluates
	# =====================================================================
	print("\n>>> PART 2: Retarget cooldown")
	enemy_b.global_position = home + Vector3(2.0, 0.0, 0.0)
	await _wait_frames(30)
	if player.current_target != enemy_a:
		await _fail(level, "Target switched before the retarget cooldown expired.")
		return
	player.force_retarget()
	await _wait_frames(5)
	if player.current_target != enemy_b:
		await _fail(level, "Target did not switch to nearer enemy B after re-evaluation.")
		return
	player.target_retarget_cooldown = 0.3
	print("Cooldown held the target; re-evaluation switched to nearer enemy.")

	# =====================================================================
	# PART 3: Out-of-range targets clear immediately (no cooldown)
	# =====================================================================
	print("\n>>> PART 3: Range gating")
	var out_of_range_dist: float = maxf(player.auto_aim_range + 5.0, 10.0)
	enemy_a.global_position = home + Vector3(out_of_range_dist, 0.0, 0.0)
	enemy_b.global_position = home + Vector3(-out_of_range_dist, 0.0, 0.0)
	await _wait_frames(5)
	if player.current_target != null:
		await _fail(level, "Out-of-range targets were not cleared.")
		return
	if reticle.target != null or reticle.visible:
		await _fail(level, "Reticle did not hide after the target cleared.")
		return
	print("Out-of-range targets cleared and reticle hid.")

	# =====================================================================
	# PART 4: Attack rotates toward target instead of mouse aim
	# =====================================================================
	print("\n>>> PART 4: Attack aims at current_target")
	enemy_a.global_position = home + Vector3(3.0, 0.0, 0.0)
	player.force_retarget()
	await _wait_frames(40)
	if player.current_target != enemy_a:
		await _fail(level, "Player did not re-acquire enemy A.")
		return
	# Face the player away (+Z) while the enemy sits at +X.
	var away: Transform3D = player.mesh_mount.global_transform.looking_at(
		player.mesh_mount.global_position + Vector3(0, 0, 1), Vector3.UP, true
	)
	player.mesh_mount.global_transform = away
	# Point the mouse at the mirrored (wrong) side of the screen.
	var enemy_screen: Vector2 = camera.unproject_position(enemy_a.global_position)
	var player_screen: Vector2 = camera.unproject_position(player.global_position)
	var wrong_mouse: Vector2 = player_screen + (player_screen - enemy_screen)
	var mm := InputEventMouseMotion.new()
	mm.position = wrong_mouse
	mm.global_position = wrong_mouse
	Input.parse_input_event(mm)
	player.get_viewport().warp_mouse(wrong_mouse)
	await get_tree().process_frame
	var click := InputEventAction.new()
	click.action = "click"
	click.pressed = true
	sm._unhandled_input(click)
	if sm.state.name != "PlayerAttack":
		await _fail(level, "Did not enter PlayerAttack. State: " + sm.state.name)
		return
	if not player.is_attacking:
		await _fail(level, "is_attacking flag not set on attack enter.")
		return
	await _wait_frames(2)
	var facing_dir: Vector3 = player.mesh_mount.global_transform.basis.z.normalized()
	var dir_to_enemy: Vector3 = (enemy_a.global_position - player.global_position).normalized()
	var alignment: float = facing_dir.dot(dir_to_enemy)
	print("Attack facing alignment with target: ", alignment)
	if alignment < 0.85:
		await _fail(level, "Attack did not rotate toward target. Alignment: %f." % alignment)
		return
	print("Attack rotated toward the target despite opposing mouse aim.")

	# =====================================================================
	# PART 5: Target frozen during the attack, cleared after recovery
	# =====================================================================
	print("\n>>> PART 5: Attack target freeze, death-clear, no-switch")
	# Park a living alternative in range so "no mid-attack switch" is meaningful.
	var enemy_b2: Character = await _spawn_enemy(level, home + Vector3(0.0, 0.0, 4.0))
	# Exile A to measured safe floor 6 m out (x = -2 survives; x >= +10 is pit).
	enemy_a.global_position = home + Vector3(-6.0, 0.0, 0.0)
	if not enemy_a.is_alive():
		await _fail(level, "Enemy A died before the freeze check.")
		return
	var held_frames: int = 0
	var nulled_frames: int = 0
	var killed_mid_attack: bool = false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name != "PlayerAttack":
			break
		if not killed_mid_attack and held_frames >= 3:
			var health_a: HealthComponent = enemy_a.get_node("HealthComponent") as HealthComponent
			health_a.take_damage(9999.0)
			killed_mid_attack = true
			if player.current_target != null:
				await _fail(level, "Killed target lingered mid-attack.")
				return
		if not killed_mid_attack:
			if player.current_target != enemy_a:
				await _fail(level, "Target changed mid-attack.")
				return
			held_frames += 1
		else:
			if player.current_target != null:
				await _fail(level, "New target acquired mid-attack.")
				return
			nulled_frames += 1
	if not killed_mid_attack:
		await _fail(level, "Attack ended before the mid-attack kill.")
		return
	if held_frames < 3 or nulled_frames < 3:
		await _fail(level, "Attack ended too fast to verify freeze and no-switch.")
		return
	print("Held living target %d frames, corpse cleared at once, no switch for %d frames."
		% [held_frames, nulled_frames])
	for i: int in range(120):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			break
	if sm.state.name != "PlayerRun":
		await _fail(level, "Player did not recover to PlayerRun.")
		return
	await _wait_frames(40)
	if player.current_target != enemy_b2:
		await _fail(level, "Living enemy B2 not acquired after the attack.")
		return
	if player.is_attacking:
		await _fail(level, "is_attacking flag stuck true after the attack.")
		return
	print("Living replacement acquired after attack recovery.")

	# =====================================================================
	# PART 6: Dead targets clear on both sides
	# =====================================================================
	print("\n>>> PART 6: Death clears targets")
	# Fresh enemy: earlier exiles may have dropped A/B into pits by now.
	var enemy_c: Character = await _spawn_enemy(level, home + Vector3(3.0, 0.0, 0.0))
	player.force_retarget()
	await _wait_frames(40)
	if player.current_target != enemy_c:
		await _fail(level, "Player did not acquire fresh enemy C before the death check.")
		return
	var health_c: HealthComponent = enemy_c.get_node("HealthComponent") as HealthComponent
	health_c.take_damage(9999.0)
	if player.current_target != null:
		await _fail(level, "Killed target lingered instead of clearing on death.")
		return
	await _wait_frames(3)
	if player.current_target != enemy_b2:
		await _fail(level, "Did not switch to living enemy B2 right after the kill.")
		return
	if enemy_c.current_target != null:
		await _fail(level, "Defeated enemy kept its own target.")
		return
	print("Death cleared targets on both sides and switched to B2.")

	# =====================================================================
	# PART 7: Killing the target switches immediately (no linger, no
	# cooldown wait) and dead enemies are never targeted again.
	# =====================================================================
	print("\n>>> PART 7: Instant switch on target death")
	var enemy_d: Character = await _spawn_enemy(level, home + Vector3(3.0, 0.0, 0.0))
	# 3.5 m: strictly nearer than B2 at 4 m so the post-kill switch is deterministic.
	var enemy_e: Character = await _spawn_enemy(level, home + Vector3(-3.5, 0.0, 0.0))
	player.force_retarget()
	await _wait_frames(40)
	if player.current_target != enemy_d:
		await _fail(level, "Player did not acquire nearest enemy D.")
		return
	var health_d: HealthComponent = enemy_d.get_node("HealthComponent") as HealthComponent
	health_d.take_damage(9999.0)
	# Death must clear synchronously: no frame may observe the corpse targeted.
	if player.current_target != null:
		await _fail(level, "Killed target lingered instead of clearing on death.")
		return
	# Replacement must arrive far sooner than the 0.3 s retarget cooldown.
	await _wait_frames(3)
	if player.current_target != enemy_e:
		await _fail(level, "Did not switch to living enemy E right after the kill.")
		return
	# The dead enemy stays a valid node in the level but must never be targeted.
	await _wait_frames(40)
	if player.current_target != enemy_e:
		await _fail(level, "Dead enemy D was targeted again after death.")
		return
	print("Kill cleared instantly and switched to the living enemy.")

	print("\n====================================================================")
	print("  TARGETING TEST PASSED!                                             ")
	print("  1. Nearest-in-range acquisition (+enemy-side auto-aim)             ")
	print("  2. Single player-only reticle follows/hides with the target       ")
	print("  3. Retarget cooldown blocks flicker; re-evaluation switches       ")
	print("  4. Out-of-range targets clear immediately                         ")
	print("  5. Attacks rotate toward the target over mouse aim                ")
	print("  6. Freeze holds living target; death clears; no mid-attack switch ")
	print("  7. Kill clears at once and switches to living B2                 ")
	print("  8. Kill switches instantly; dead enemies never targeted again     ")
	print("====================================================================")
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().quit(0)


## Instantiates a melee enemy at the given position with its AI frozen, so it
## holds still for deterministic distance checks while staying alive and
## damageable.
func _spawn_enemy(level: Node3D, pos: Vector3) -> Character:
	var enemy: Character = (GlobalVars.enemy_melee_scene as PackedScene).instantiate() as Character
	level.add_child(enemy)
	enemy.global_position = pos
	if enemy.ai_state_machine != null:
		enemy.ai_state_machine.set_physics_process(false)
		enemy.ai_state_machine.command_stop()
	# Let the body simulate one frame before the next spawn so same-frame
	# double add+teleport pairs never displace a fresh body (see above).
	await get_tree().physics_frame
	await get_tree().physics_frame
	return enemy


func _wait_frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().physics_frame


func _fail(level: Node3D, msg: String) -> void:
	printerr("TEST FAILED: ", msg)
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().quit(1)
