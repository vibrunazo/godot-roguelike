extends Node

## Regression test: dashing (or attacking) into an exit point must not carry
## movement or ability state into the next level. Exercises the real restore
## path (SceneTransition.player_cache adopted by a fresh level_template, which
## calls Character.cancel_movement_and_abilities) for both a mid-dash and a
## mid-attack player with pending intents, knockback momentum, and a live
## weapon hitbox.


func _ready() -> void:
	print("--- RUNNING LEVEL TRANSITION RESET TEST ---")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level_a: Node3D = level_scene.instantiate() as Node3D
	add_child(level_a)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Character = level_a.get_node("Player") as Character
	var sm: StateMachine = player.state_machine
	if sm.state == null or sm.state.name != "PlayerRun":
		# Settle until the machine has entered its home state.
		var settled: bool = false
		for i: int in range(120):
			await get_tree().physics_frame
			if sm.state != null and sm.state.name == "PlayerRun":
				settled = true
				break
		if not settled:
			printerr("TEST FAILED: Player did not settle in PlayerRun.")
			get_tree().quit(1)
			return

	# PART 1: mid-dash carried across a level restore.
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	if not sm.request_state("PlayerDash", {"direction": Vector3(0.0, 0.0, 1.0)}):
		printerr("TEST FAILED: Could not enter PlayerDash.")
		get_tree().quit(1)
		return
	# Raise transient state AFTER entering dash (entry clears stale intents).
	player.attack_requested = true
	player.dash_requested = true
	player.knockback_component.add_knockback(Vector3(5.0, 0.0, 0.0))
	var slots: Array[Node] = player.find_children("*", "WeaponSlot")
	if slots.is_empty():
		printerr("TEST FAILED: No WeaponSlot found on player.")
		get_tree().quit(1)
		return
	(slots[0] as WeaponSlot).enabled = true
	if sm.state.name != "PlayerDash" or player.velocity.length() <= 1.0:
		printerr("TEST FAILED: Player was not really dashing before restore.")
		get_tree().quit(1)
		return
	if not player.knockback_component.is_active():
		printerr("TEST FAILED: Knockback setup did not register as active.")
		get_tree().quit(1)
		return
	print("Dashing into exit with pending intents, knockback, live hitbox...")

	SceneTransition.player_cache = player
	var level_b: Node3D = level_scene.instantiate() as Node3D
	add_child(level_b)

	# NOTE: level_b.get_node("Player") would return the level's own fresh Player,
	# which is only queued for deletion; the adopted cache is LevelTemplate.player.
	var carried: Character = (level_b as LevelTemplate).player
	if carried != player:
		printerr("TEST FAILED: Restored player is not the cached player.")
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	if not _assert_quiet(carried, sm, "dash"):
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	if not await _assert_quiet_over_frames(carried, sm, "dash"):
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	print("Mid-dash restore cancelled: PlayerRun, zero velocity, no intents.")

	# PART 2: mid-attack (queued combo + live hitbox) carried across a restore.
	if not sm.request_state("PlayerAttack", {"direction": Vector3.ZERO}):
		printerr("TEST FAILED: Could not enter PlayerAttack.")
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	(sm.get_node("PlayerAttack") as CharacterAttack).queued_attack = true
	player.dash_requested = true
	player.velocity = Vector3(3.0, 0.0, 3.0)
	(slots[0] as WeaponSlot).enabled = true
	if not player.is_attacking:
		printerr("TEST FAILED: Player was not really attacking before restore.")
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return

	SceneTransition.player_cache = player
	var level_c: Node3D = level_scene.instantiate() as Node3D
	add_child(level_c)

	var carried_attack: Character = (level_c as LevelTemplate).player
	if carried_attack != player:
		printerr("TEST FAILED: Restored attacker is not the cached player.")
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	if (sm.get_node("PlayerAttack") as CharacterAttack).queued_attack:
		printerr("TEST FAILED: Queued combo intent survived the transition.")
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	if not _assert_quiet(carried_attack, sm, "attack"):
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	if not await _assert_quiet_over_frames(carried_attack, sm, "attack"):
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	print("Mid-attack restore cancelled: PlayerRun, zero velocity, hitbox off.")

	SceneTransition.player_cache = null
	level_a.queue_free()
	level_b.queue_free()
	level_c.queue_free()

	print("LEVEL TRANSITION RESET TEST PASSED!")
	get_tree().quit(0)


## Freezes every enemy mind so the multi-frame observation below measures only
## the restored player's own state (no outside knockback or damage).
func _still_enemies() -> void:
	for node: Node in get_tree().get_nodes_in_group("enemy"):
		var enemy: Character = node as Character
		if enemy == null or enemy.ai_state_machine == null:
			continue
		enemy.ai_state_machine.set_physics_process(false)
		enemy.ai_state_machine.set_process_unhandled_input(false)


## Observes the restored player across frames so stale timers (dash duration,
## queued-combo windows, lunge timers) cannot reignite motion or abilities
## after the restore. The adopted spawn may be marginally airborne, so the
## normal spawn-fall (PlayerFall, like every fresh spawn) is allowed — but the
## player must land back in PlayerRun with no dash/attack leak on any frame.
## Returns false on the first frame that leaks state.
func _assert_quiet_over_frames(carried: Character, sm: StateMachine, label: String) -> bool:
	_still_enemies()
	var landed: bool = false
	for f: int in range(120):
		await get_tree().physics_frame
		if not _assert_no_leak_frame(carried, sm, label + " frame " + str(f)):
			return false
		if sm.state != null and sm.state.name == "PlayerRun" and carried.is_on_floor():
			landed = true
			break
	if not landed:
		printerr("TEST FAILED: Post-", label, " player never landed in PlayerRun.")
		return false
	_still_enemies()
	return _assert_landed_quiet(carried, sm, label)


## Per-frame leak check: never in a dash/attack state, no meaningful horizontal
## motion (1.0 is the KnockbackComponent.is_active threshold: anything above
## it is real momentum, not floor slide), no pending intents, no knockback,
## not attacking, hitboxes disabled. Vertical fall speed is gravity, allowed.
func _assert_no_leak_frame(carried: Character, sm: StateMachine, label: String) -> bool:
	if sm.state == null or (sm.state.name != "PlayerRun" and sm.state.name != "PlayerFall"):
		var got: String = str(sm.state.name) if sm.state != null else "<null>"
		printerr("TEST FAILED: Post-", label, " state is ", got, ", expected PlayerRun/PlayerFall.")
		return false
	if Vector2(carried.velocity.x, carried.velocity.z).length() > 1.0:
		printerr("TEST FAILED: Post-", label, " horizontal velocity leaked: ", carried.velocity)
		return false
	return _assert_no_ability_leak(carried, label)


## Landed check: home state, quiet horizontal motion, no ability residue.
func _assert_landed_quiet(carried: Character, sm: StateMachine, label: String) -> bool:
	if sm.state == null or sm.state.name != "PlayerRun":
		var got: String = str(sm.state.name) if sm.state != null else "<null>"
		printerr("TEST FAILED: Post-", label, " landed state is ", got, ", expected PlayerRun.")
		return false
	if Vector2(carried.velocity.x, carried.velocity.z).length() > 1.0:
		printerr("TEST FAILED: Post-", label, " landed horizontal velocity: ", carried.velocity)
		return false
	return _assert_no_ability_leak(carried, label)


## Ability residue shared by the frame and landed checks: no pending intents,
## no knockback momentum, not attacking, weapon hitboxes disabled.
func _assert_no_ability_leak(carried: Character, label: String) -> bool:
	if carried.attack_requested or carried.dash_requested:
		printerr("TEST FAILED: Post-", label, " edge intent survived the transition.")
		return false
	if carried.knockback_component != null and carried.knockback_component.is_active():
		printerr("TEST FAILED: Post-", label, " knockback momentum survived the transition.")
		return false
	if carried.is_attacking:
		printerr("TEST FAILED: Post-", label, " is_attacking still set.")
		return false
	for slot: Node in carried.find_children("*", "WeaponSlot"):
		if slot is WeaponSlot and (slot as WeaponSlot).enabled:
			printerr("TEST FAILED: Post-", label, " weapon hitbox still enabled.")
			return false
	return true


## Shared behavioral assertions after a restore: home state, no motion, no
## pending intents, no knockback, not attacking, hitboxes disabled.
func _assert_quiet(carried: Character, sm: StateMachine, label: String) -> bool:
	if sm.state == null or sm.state.name != "PlayerRun":
		var got: String = str(sm.state.name) if sm.state != null else "<null>"
		printerr("TEST FAILED: Post-", label, " state is ", got, ", expected PlayerRun.")
		return false
	if not carried.velocity.is_zero_approx():
		printerr("TEST FAILED: Post-", label, " velocity leaked: ", carried.velocity)
		return false
	if not carried.move_direction.is_zero_approx():
		printerr("TEST FAILED: Post-", label, " move_direction leaked: ", carried.move_direction)
		return false
	if carried.attack_requested or carried.dash_requested:
		printerr("TEST FAILED: Post-", label, " edge intent survived the transition.")
		return false
	if carried.knockback_component != null and carried.knockback_component.is_active():
		printerr("TEST FAILED: Post-", label, " knockback momentum survived the transition.")
		return false
	if carried.is_attacking:
		printerr("TEST FAILED: Post-", label, " is_attacking still set.")
		return false
	for slot: Node in carried.find_children("*", "WeaponSlot"):
		if slot is WeaponSlot and (slot as WeaponSlot).enabled:
			printerr("TEST FAILED: Post-", label, " weapon hitbox still enabled.")
			return false
	return true
