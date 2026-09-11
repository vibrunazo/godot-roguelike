extends Node

## Focused regression suite for self hitstop: landing an attack briefly slows
## the attacker itself (near-pause), with scale and duration configured per
## attack state.

const TestUtils = preload("res://test/test_utils.gd")


func _fail(message: String) -> void:
	printerr("TEST FAILED: ", message)
	get_tree().quit(1)


func _click() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = "click"
	ev.pressed = true
	return ev


func _ready() -> void:
	print("--- RUNNING SELF HITSTOP TEST ---")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)

	var player: Character = level.get_node("Player") as Character
	var dummy: CollisionObject3D = TestUtils.find_dummy(level, player)
	var health_comp: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	var slash: CharacterAttack = sm.get_node("PlayerAttack") as CharacterAttack
	var stab: CharacterAttack = sm.get_node("PlayerAttack2") as CharacterAttack
	var spin: CharacterAttack = sm.get_node("PlayerAttack3") as CharacterAttack

	# Wait for player to land on floor in PlayerRun state.
	var landed: bool = false
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			landed = true
			break
	if not landed:
		_fail("Player did not settle on floor.")
		return

	# =====================================================================
	# PART 1: Per-attack configuration exists and stays under 0.1 seconds.
	# =====================================================================
	print(">>> PART 1: Per-attack hitstop configuration")
	for state: CharacterAttack in [slash, stab, spin]:
		var scale: float = state.get("self_hitstop_scale") as float
		var duration: float = state.get("self_hitstop_duration") as float
		if scale < 0.0 or scale >= 1.0:
			_fail(state.name + " self_hitstop_scale expected in [0, 1), got: " + str(scale))
			return
		if duration <= 0.0 or duration > 0.3:
			_fail(state.name + " self_hitstop_duration expected in (0, 0.3], got: " + str(duration))
			return
	print("All three combo states carry hitstop config.")

	# Per-state storage: writing one state must not affect the others.
	var orig_slash_scale: float = slash.self_hitstop_scale
	var orig_stab_scale: float = stab.self_hitstop_scale
	stab.self_hitstop_scale = 0.33
	stab.self_hitstop_duration = 0.09
	if not is_equal_approx(stab.self_hitstop_scale, 0.33):
		_fail("Could not configure stab hitstop scale per attack state.")
		return
	if is_equal_approx(slash.self_hitstop_scale, 0.33):
		_fail("Hitstop config leaked between attack states.")
		return
	stab.self_hitstop_scale = orig_stab_scale
	slash.self_hitstop_scale = orig_slash_scale
	print("Per-attack state configuration verified (no cross-state leakage).")

	# =====================================================================
	# PART 2: Landing a hit slows the attacker itself.
	# =====================================================================
	print(">>> PART 2: Hit triggers attacker slowmo")
	player.global_position = Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z - 1.3)
	var dir: Vector3 = Vector3(0, 0, 1)
	player.mesh_mount.global_transform = player.mesh_mount.global_transform.looking_at(player.mesh_mount.global_position + dir, Vector3.UP, true)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var initial_health: float = health_comp.current_health
	sm._unhandled_input(_click())
	if sm.state.name != "PlayerAttack":
		_fail("Did not enter PlayerAttack. State: " + sm.state.name)
		return
	var base_timescale: Variant = player.animation_tree.get("parameters/SlashAttack/TimeScale/scale")
	if not (base_timescale is float):
		_fail("SlashAttack exposes no TimeScale node for hitstop slowdown.")
		return

	var hit: bool = false
	for i: int in range(80):
		await get_tree().physics_frame
		if health_comp.current_health < initial_health:
			hit = true
			break
	if not hit:
		_fail("Attack never damaged the dummy.")
		return
	if health_comp.current_health != initial_health - 8.0:
		_fail("Slash damage mismatch. Health: " + str(health_comp.current_health))
		return
	if not slash.is_in_hitstop():
		_fail("Attacker did not enter hitstop after landing a hit.")
		return
	if slash.hitstop_time_remaining <= 0.0 or slash.hitstop_time_remaining > slash.self_hitstop_duration:
		_fail("Hitstop timer out of range: " + str(slash.hitstop_time_remaining))
		return
	var slowed: Variant = player.animation_tree.get("parameters/SlashAttack/TimeScale/scale")
	if not (slowed is float) or not is_equal_approx(slowed as float, slash.self_hitstop_scale):
		_fail("Attack animation was not slowed to hitstop scale. Got: " + str(slowed))
		return
	print("Hitstop entered: animation slowed to ", str(slowed), " for ", str(slash.self_hitstop_duration), "s.")

	# =====================================================================
	# PART 3: Hitstop expires and restores full animation speed.
	# =====================================================================
	print(">>> PART 3: Hitstop expiry restores speed")
	for i: int in range(12):
		await get_tree().physics_frame
	if slash.is_in_hitstop():
		_fail("Hitstop did not expire within 12 physics frames (>0.1s budget).")
		return
	var restored: Variant = player.animation_tree.get("parameters/SlashAttack/TimeScale/scale")
	if not (restored is float) or not is_equal_approx(restored as float, base_timescale as float):
		_fail("Attack animation speed not restored after hitstop. Got: " + str(restored))
		return
	print("Hitstop expired and animation speed restored to ", str(restored), ".")

	# Movement slowdown applies while hitstop is active (white-box probe on the
	# shared stab state: lunging at scale must scale velocity, full speed after).
	print(">>> PART 4: Movement scales with hitstop")
	var lunged_speed: float = 0.0
	stab.lunging = true
	stab.lunge_direction = Vector3.FORWARD
	stab.self_hitstop_scale = 0.1
	stab.hitstop_time_remaining = 0.06
	stab.physics_update(1.0 / 60.0)
	lunged_speed = player.velocity.length()
	stab.hitstop_time_remaining = 0.0
	stab.lunging = true
	stab.physics_update(1.0 / 60.0)
	var full_speed: float = player.velocity.length()
	stab.lunging = false
	stab.self_hitstop_scale = orig_stab_scale
	if full_speed <= 0.0 or not is_equal_approx(lunged_speed, full_speed * 0.1):
		_fail("Lunge velocity not scaled by hitstop. Slowed: " + str(lunged_speed) + ", full: " + str(full_speed))
		return
	print("Movement slowdown verified (", snappedf(lunged_speed, 0.01), " vs ", snappedf(full_speed, 0.01), " m/s).")

	# Wait for the slash to finish cleanly before the cancel test.
	var back_to_run: bool = false
	for i: int in range(120):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			back_to_run = true
			break
	if not back_to_run:
		_fail("Did not return to PlayerRun after slash.")
		return

	# =====================================================================
	# PART 5: Interrupting the attack clears hitstop (no leaked slowdown).
	# =====================================================================
	print(">>> PART 5: Dash-cancel clears hitstop")
	player.global_position = Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z - 1.3)
	player.mesh_mount.global_transform = player.mesh_mount.global_transform.looking_at(player.mesh_mount.global_position + dir, Vector3.UP, true)
	await get_tree().physics_frame
	initial_health = health_comp.current_health
	sm._unhandled_input(_click())
	var hit_again: bool = false
	for i: int in range(80):
		await get_tree().physics_frame
		if health_comp.current_health < initial_health:
			hit_again = true
			break
	if not hit_again or not slash.is_in_hitstop():
		_fail("Second attack did not reach hitstop for the cancel test.")
		return
	Input.action_press("move_forward")
	await get_tree().physics_frame
	var dash_event := InputEventAction.new()
	dash_event.action = "dash"
	dash_event.pressed = true
	sm._unhandled_input(dash_event)
	Input.action_release("move_forward")
	if sm.state.name != "PlayerDash":
		_fail("Dash cancel did not interrupt the slowed attack. State: " + sm.state.name)
		return
	if slash.is_in_hitstop():
		_fail("Hitstop leaked past state exit.")
		return
	var after_cancel: Variant = player.animation_tree.get("parameters/SlashAttack/TimeScale/scale")
	if not (after_cancel is float) or not is_equal_approx(after_cancel as float, base_timescale as float):
		_fail("Slowed animation speed leaked past state exit. Got: " + str(after_cancel))
		return
	if slash.attack_component != null and slash.attack_component.hit_landed.is_connected(slash._on_hit_landed):
		_fail("hit_landed wiring leaked past state exit.")
		return
	print("Dash-cancel cleared hitstop, restored speed, and unwired hit_landed.")
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			break

	# =====================================================================
	# PART 6: Zero duration disables the effect.
	# =====================================================================
	print(">>> PART 6: Zero duration disables hitstop")
	var saved_duration: float = slash.self_hitstop_duration
	slash.self_hitstop_duration = 0.0
	slash.apply_self_hitstop()
	if slash.is_in_hitstop():
		_fail("Hitstop activated with zero duration.")
		slash.self_hitstop_duration = saved_duration
		return
	slash.self_hitstop_duration = saved_duration
	print("Zero-duration hitstop correctly disabled.")

	# =====================================================================
	# PART 7: Enemy attacks expose the same per-state slowmo hooks.
	# =====================================================================
	print(">>> PART 7: Enemy attack support")
	var melee_scene: PackedScene = load("res://Enemy/melee_enemy.tscn") as PackedScene
	var melee_enemy: Node = melee_scene.instantiate()
	var enemy_attack: CharacterAttack = melee_enemy.get_node("StateMachine/EnemyAttack") as CharacterAttack
	var enemy_duration: float = enemy_attack.get("self_hitstop_duration") as float
	var enemy_scale: float = enemy_attack.get("self_hitstop_scale") as float
	melee_enemy.queue_free()
	if enemy_duration <= 0.0 or enemy_duration > 0.3 or enemy_scale < 0.0 or enemy_scale >= 1.0:
		_fail("Melee EnemyAttack hitstop config out of range: scale=" + str(enemy_scale) + " duration=" + str(enemy_duration))
		return
	var anim_scene: PackedScene = load("res://Enemy/animated_enemy.tscn") as PackedScene
	var animated: Node3D = anim_scene.instantiate() as Node3D
	add_child(animated)
	await get_tree().process_frame
	await get_tree().process_frame
	var enemy_tree: AnimationTree = animated.find_child("AnimationTree", true, false) as AnimationTree
	var melee_scale: Variant = enemy_tree.get("parameters/MeleeAttack/TimeScale/scale")
	var ranged_scale: Variant = enemy_tree.get("parameters/RangedAttack/TimeScale/scale")
	animated.queue_free()
	if not (melee_scale is float) or not (ranged_scale is float):
		_fail("Enemy attack animations expose no TimeScale nodes for hitstop.")
		return
	print("Enemy attacks configured (scale=", str(enemy_scale), ", duration=", str(enemy_duration), ") with TimeScale support.")

	print("================================")
	print("  SELF HITSTOP TESTS PASSED     ")
	print("================================")
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
