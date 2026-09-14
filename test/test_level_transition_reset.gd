extends Node

## Regression test: dashing (or attacking) into an exit point must not carry
## movement or ability state into the next level. Exercises the real restore
## path (SceneTransition.player_cache adopted by a fresh level_template, which
## calls Character.cancel_movement_and_abilities) for both a mid-dash and a
## mid-attack player with pending intents, knockback momentum, a live weapon
## hitbox, in-flight character SFX (dash, damage), and a mid-flash damage tint.
## Also covers the transition-start path (SceneTransition.load_scene_path
## cancels upfront): cancel_movement_and_abilities must stop SFX and clear the
## tint synchronously, including when invoked from inside a physics callback
## (exit portal body_entered runs during the physics flush, where direct
## Area3D.monitorable writes are locked).


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

	# PART 0: transition-start cancel stops SFX and clears the tint synchronously
	# (what SceneTransition.load_scene_path does before the fade begins).
	if not _setup_noisy_dash(player, sm):
		get_tree().quit(1)
		return
	print("Noisy mid-dash setup (dash SFX, damage SFX, red tint)...")
	player.cancel_movement_and_abilities()
	if not _assert_quiet(player, sm, "transition-start cancel"):
		get_tree().quit(1)
		return
	print("Transition-start cancel verified: quiet, SFX stopped, tint cleared.")

	# PART 1: mid-dash carried across a level restore.
	if not _setup_noisy_dash(player, sm):
		get_tree().quit(1)
		return
	print("Dashing into exit with pending intents, knockback, live hitbox, SFX, tint...")

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
	var attack_slots: Array[Node] = player.find_children("*", "WeaponSlot")
	if attack_slots.is_empty():
		printerr("TEST FAILED: No WeaponSlot found on player.")
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	(attack_slots[0] as WeaponSlot).enabled = true
	# Simulate an in-flight slash SFX leaking across the transition.
	var attack_audio: AudioStreamPlayer3D = player.get_node_or_null("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot/AttackAudio") as AudioStreamPlayer3D
	if attack_audio != null:
		attack_audio.play()
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

	# PART 3: cancel from inside a physics callback. Exit portals invoke
	# SceneTransition.load_scene_path from body_entered, i.e. while the physics
	# server flushes queries, where direct Area3D.monitorable writes are locked
	# and raise errors. The cancel path must survive that context and still
	# leave the hitbox fully disabled (monitoring + monitorable).
	if not _setup_noisy_dash(player, sm):
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	var probe: Area3D = Area3D.new()
	probe.collision_mask = 17
	var probe_shape: CollisionShape3D = CollisionShape3D.new()
	var probe_sphere: SphereShape3D = SphereShape3D.new()
	probe_sphere.radius = 3.0
	probe_shape.shape = probe_sphere
	probe.add_child(probe_shape)
	_flush_cancel_done = false
	_flush_write_split = false
	probe.body_entered.connect(_on_probe_body_entered.bind(player))
	level_c.add_child(probe)
	probe.global_position = player.global_position
	var flush_waited: int = 0
	while not _flush_cancel_done and flush_waited < 60:
		await get_tree().physics_frame
		flush_waited += 1
	if not _flush_cancel_done:
		printerr("TEST FAILED: Physics callback never fired for flush-context cancel.")
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	if _flush_write_split:
		printerr("TEST FAILED: Flush-context hitbox write left monitoring/monitorable split (locked write skipped).")
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	for i: int in range(5):
		await get_tree().physics_frame
	if not _assert_quiet(player, sm, "physics-flush cancel"):
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	var flush_slots: Array[Node] = player.find_children("*", "WeaponSlot")
	if flush_slots.is_empty():
		printerr("TEST FAILED: No WeaponSlot found on player.")
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	var flush_hitbox: Area3D = (flush_slots[0] as WeaponSlot).hitbox
	if flush_hitbox != null and (flush_hitbox.monitoring or flush_hitbox.monitorable):
		printerr("TEST FAILED: Post-physics-flush hitbox still active: monitoring=", flush_hitbox.monitoring, " monitorable=", flush_hitbox.monitorable)
		SceneTransition.player_cache = null
		get_tree().quit(1)
		return
	print("Physics-flush cancel verified: quiet, hitbox fully disabled.")

	SceneTransition.player_cache = null
	level_a.queue_free()
	level_b.queue_free()
	level_c.queue_free()

	print("LEVEL TRANSITION RESET TEST PASSED!")
	get_tree().quit(0)


## Set by _on_probe_body_entered once the flush-context cancel has run.
var _flush_cancel_done: bool = false
## Set when a flush-context hitbox write leaves monitoring/monitorable split
## (the locked write was skipped): the regression signature of this bug.
var _flush_write_split: bool = false


## Physics-flush entry point for PART 3: runs cancel_movement_and_abilities
## from inside an Area3D.body_entered callback, the same locked context the
## exit portal's SceneTransition.load_scene_path call runs in.
func _on_probe_body_entered(body: Node3D, target: Character) -> void:
	if body == target and not _flush_cancel_done:
		_flush_cancel_done = true
		var slot: WeaponSlot = target.find_children("*", "WeaponSlot")[0] as WeaponSlot
		# Deterministic flush-context write: re-enable first, because the
		# setup's enable may already have been stomped back to false by the
		# attack animation track's WeaponSlot:enabled key before this fires.
		slot.enabled = true
		if slot.hitbox != null and slot.hitbox.monitoring != slot.hitbox.monitorable:
			_flush_write_split = true
		target.cancel_movement_and_abilities()


## Drives the player into a noisy mid-dash: real dash state (PlayerDash.enter
## plays the dash SFX), pending intents, knockback momentum, a live weapon
## hitbox, in-flight damage SFX, and a mid-flash damage tint. Returns false on
## setup failure. Damage SFX/tint are started directly (rather than via
## take_damage) so the setup never stuns the player out of the dash it must hold.
func _setup_noisy_dash(player: Character, sm: StateMachine) -> bool:
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	if not sm.request_state("PlayerDash", {"direction": Vector3(0.0, 0.0, 1.0)}):
		printerr("TEST FAILED: Could not enter PlayerDash.")
		return false
	# Raise transient state AFTER entering dash (entry clears stale intents).
	player.attack_requested = true
	player.dash_requested = true
	player.knockback_component.add_knockback(Vector3(5.0, 0.0, 0.0))
	var slots: Array[Node] = player.find_children("*", "WeaponSlot")
	if slots.is_empty():
		printerr("TEST FAILED: No WeaponSlot found on player.")
		return false
	(slots[0] as WeaponSlot).enabled = true
	var hit_audio: AudioStreamPlayer3D = player.health_component.hit_audio
	if hit_audio != null:
		hit_audio.play()
	var tint: ColorRect = player.get_node_or_null("DamageTint") as ColorRect
	if tint != null:
		tint.color = Color(Color.RED, 0.5)
	if sm.state.name != "PlayerDash" or player.velocity.length() <= 1.0:
		printerr("TEST FAILED: Player was not really dashing before transition.")
		return false
	if not player.knockback_component.is_active():
		printerr("TEST FAILED: Knockback setup did not register as active.")
		return false
	var dash_audio: AudioStreamPlayer3D = player.get_node_or_null("DashAudio") as AudioStreamPlayer3D
	if dash_audio == null or not dash_audio.playing:
		printerr("TEST FAILED: Dash SFX is not playing mid-dash.")
		return false
	return true


## Asserts no character SFX is still playing and the damage tint is fully
## transparent: no dash/damage/attack sound or red flash may leak across the
## transition (a tween frozen mid-flash would otherwise resume red later).
func _assert_no_sfx_or_tint_leak(carried: Character, label: String) -> bool:
	for audio_3d: Node in carried.find_children("*", "AudioStreamPlayer3D"):
		if (audio_3d as AudioStreamPlayer3D).playing:
			printerr("TEST FAILED: Post-", label, " character SFX still playing: ", audio_3d.name)
			return false
	for audio_2d: Node in carried.find_children("*", "AudioStreamPlayer"):
		if (audio_2d as AudioStreamPlayer).playing:
			printerr("TEST FAILED: Post-", label, " character SFX still playing: ", audio_2d.name)
			return false
	var tint: ColorRect = carried.get_node_or_null("DamageTint") as ColorRect
	if tint != null and not is_zero_approx(tint.color.a):
		printerr("TEST FAILED: Post-", label, " damage tint still visible, alpha: ", tint.color.a)
		return false
	return true


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
## no knockback momentum, not attacking, weapon hitboxes disabled, no SFX
## still playing, damage tint transparent.
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
	return _assert_no_sfx_or_tint_leak(carried, label)


## Shared behavioral assertions after a restore: home state, no motion, no
## pending intents, no knockback, not attacking, hitboxes disabled, no SFX
## still playing, damage tint transparent.
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
	return _assert_no_sfx_or_tint_leak(carried, label)
