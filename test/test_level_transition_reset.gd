## Regression suite: nothing the player was doing crosses into the next level.
## Exercises the real carry-over path (SceneTransition.player_cache adopted by
## a fresh level template, which calls Character.cancel_movement_and_abilities)
## and the transition-start cancel (SceneTransition.load_scene_path cancels up
## front):
## - the transition-start cancel stops character SFX and clears the damage
##   tint at once,
## - a player carried mid-dash, or mid-attack with a queued combo, arrives in
##   running with no motion, intents, knockback, live hitbox, SFX or tint, and
##   nothing reignites over the following frames,
## - the cancel works from inside a physics callback (exit portals run it from
##   body_entered, where direct Area3D writes are locked) and leaves the
##   hitbox fully off,
## - burns (damage and visual), temporary modifiers, camera shake and damage
##   numbers do not cross the transition.
## (TODO.md item 11 plans to recreate the player per level instead; this
## suite is the contract that replacement must keep.)
extends "res://test/lib/test_suite.gd"

const LEVEL_TEMPLATE_SCENE: PackedScene = preload("res://Levels/level_template.tscn")
const BURN_EFFECT: GameplayEffect = preload("res://Components/effect_fire_burn.tres")
## Test-owned transient state raised before the transition.
const TEST_KNOCKBACK: Vector3 = Vector3(5.0, 0.0, 0.0)
const TEST_SLOW: float = -0.5
const TEST_SLOW_DURATION: float = 5.0
const TEST_TRAUMA: float = 0.8
const TEST_WOUND: float = 42.0
## Horizontal speed above which the character is really moving (the
## KnockbackComponent.is_active threshold), not settling on the floor.
const MOVING_SPEED: float = 1.0
## Physics ticks allowed for the carried player to land back in running.
const LANDING_FRAMES: int = 120

var _player: Character
var _input: PlayerInputComponent


func before_each() -> void:
	SceneTransition.player_cache = null
	var level: Node3D = _spawn_level()
	_player = (level as LevelTemplate).player
	_input = _player.get_node("PlayerInputComponent") as PlayerInputComponent
	await wait_until(func() -> bool: return _state() == "PlayerRun", "the player should settle in running")


func after_each() -> void:
	SceneTransition.player_cache = null


func test_a_carried_player_keeps_its_health_and_lands_on_the_new_levels_spawn() -> void:
	var health: float = _player.attribute_component.get_current(AttributeComponent.POOL_HEALTH) - TEST_WOUND
	_player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, health)
	_player.global_position += Vector3(3.0, 0.0, 3.0)
	SceneTransition.player_cache = _player
	# The next level's own spawn point: where its authored Player stands.
	var authored: Node3D = LEVEL_TEMPLATE_SCENE.instantiate() as Node3D
	var spawn_point: Vector3 = (authored.get_node("Player") as Node3D).position
	authored.free()
	var next: LevelTemplate = _spawn_level() as LevelTemplate
	if not check(next.player == _player, "the next level should adopt the carried player"):
		return
	check_approx(_player.attribute_component.get_current(AttributeComponent.POOL_HEALTH), health, "the carried player should keep its health")
	check(_player.global_position.is_equal_approx(next.global_transform * spawn_point), "the carried player should stand on the new level's spawn point")
	check_eq(_player.process_mode, Node.PROCESS_MODE_INHERIT, "the carried player should be running again")


func test_the_transition_start_cancel_silences_sfx_and_the_tint_at_once() -> void:
	if not _start_noisy_dash():
		return
	_player.cancel_movement_and_abilities()
	_check_quiet("after the transition-start cancel")


func test_a_player_carried_mid_dash_arrives_quiet() -> void:
	if not _start_noisy_dash():
		return
	if not _carry_to_next_level():
		return
	_check_quiet("after arriving mid-dash")
	await _check_quiet_until_landed("after arriving mid-dash")


func test_a_player_carried_mid_attack_arrives_quiet() -> void:
	var attack: CharacterAttack = _player.state_machine.get_node("PlayerRun").get("attack_state") as CharacterAttack
	if not check(_player.state_machine.request_state(attack.name, {"direction": Vector3.ZERO}), "setup: the attack should start"):
		return
	attack.queued_attack = true
	_player.dash_requested = true
	_player.velocity = Vector3(3.0, 0.0, 3.0)
	var slot: WeaponSlot = attack.get_weapon_slot()
	slot.enabled = true
	var swing: AudioStreamPlayer3D = _slash_audio(slot)
	if swing != null:
		swing.play()
	if not check(_player.is_attacking, "setup: the player should be attacking"):
		return
	if not _carry_to_next_level():
		return
	check(not attack.queued_attack, "a queued combo must not cross the transition")
	_check_quiet("after arriving mid-attack")
	await _check_quiet_until_landed("after arriving mid-attack")


func test_cancelling_inside_a_physics_callback_fully_disables_the_hitbox() -> void:
	if not _start_noisy_dash():
		return
	var slot: WeaponSlot = _player.find_children("*", "WeaponSlot")[0] as WeaponSlot
	var probe: Area3D = autofree(Area3D.new()) as Area3D
	probe.collision_mask = _player.collision_layer
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 3.0
	shape.shape = sphere
	probe.add_child(shape)
	var ran: Array[bool] = [false]
	var split: Array[bool] = [false]
	probe.body_entered.connect(func(body: Node3D) -> void:
		if body != _player or ran[0]:
			return
		ran[0] = true
		# Re-enable inside the callback: the attack track may already have
		# switched the slot off before this fires.
		slot.enabled = true
		split[0] = slot.hitbox != null and slot.hitbox.monitoring != slot.hitbox.monitorable
		_player.cancel_movement_and_abilities())
	_player.get_parent().add_child(probe)
	probe.global_position = _player.global_position
	if not await wait_until(func() -> bool: return ran[0], "the physics callback should fire"):
		return
	check(not split[0], "a hitbox write inside the callback must not leave monitoring and monitorable split")
	await wait_physics_frames(5)
	_check_quiet("after a cancel inside a physics callback")
	check(not slot.hitbox.monitoring and not slot.hitbox.monitorable, "the hitbox should be fully off after the cancel")


func test_burns_modifiers_shake_and_damage_numbers_do_not_cross_the_transition() -> void:
	var attributes: AttributeComponent = _player.attribute_component
	if not check(attributes.apply_effect(BURN_EFFECT) != &"", "setup: the burn should apply"):
		return
	var base_speed: float = attributes.get_current(AttributeComponent.STAT_SPEED)
	attributes.apply_modifier(AttributeComponent.STAT_SPEED, &"test_slow", Attribute.Op.MULT_ADD, TEST_SLOW, TEST_SLOW_DURATION)
	if not check(not is_equal_approx(attributes.get_current(AttributeComponent.STAT_SPEED), base_speed), "setup: the slow should apply"):
		return
	var camera: ShakeCamera3D = _player.get_node("CameraRoot/ShakeCamera3D") as ShakeCamera3D
	camera.trauma = TEST_TRAUMA
	VfxManager.spawn_damage_number(_player, 10.0)
	await get_tree().process_frame
	if not check(_player.find_children("*", "StatusBurning", true, false).size() > 0, "setup: the burn should show its visual"):
		return
	VfxManager.clear_temporary_effects()
	if not _carry_to_next_level():
		return
	await get_tree().process_frame
	for visual: Node in _player.find_children("*", "StatusBurning", true, false):
		check(visual.is_queued_for_deletion(), "the burn visual must not cross the transition")
	check_approx(attributes.get_current(AttributeComponent.STAT_SPEED), base_speed, "temporary modifiers must not cross the transition")
	check(is_zero_approx(camera.trauma), "camera shake must not cross the transition")
	for child: Node in VfxManager.get_children():
		check(not (child is DamageNumber) or child.is_queued_for_deletion(), "damage numbers must not cross the transition")
	var health: float = attributes.get_current(AttributeComponent.POOL_HEALTH)
	await wait_physics_frames(ceili(BURN_EFFECT.duration * 0.5 * Engine.physics_ticks_per_second))
	check_approx(attributes.get_current(AttributeComponent.POOL_HEALTH), health, "the burn must stop hurting after the transition")


## A level template with its wave stopped; it adopts SceneTransition's
## carried player when one is set.
func _spawn_level() -> Node3D:
	var level: Node3D = spawn(LEVEL_TEMPLATE_SCENE) as Node3D
	(level.get_node("WaveObjective") as WaveObjective).stop_spawning()
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		disable_ai(enemy as Character)
	return level


## Carries the player into a fresh level the way SceneTransition does.
func _carry_to_next_level() -> bool:
	SceneTransition.player_cache = _player
	var next: LevelTemplate = _spawn_level() as LevelTemplate
	return check(next.player == _player, "the next level should adopt the carried player")


## Puts the player mid-dash with every kind of transient state raised:
## pending intents, knockback, a live hitbox, playing dash and hit SFX and a
## mid-flash damage tint (set directly, so no stun ends the dash early).
func _start_noisy_dash() -> bool:
	_player.move_direction = Vector3.BACK
	if not check(_player.state_machine.request_state("PlayerDash", {"direction": Vector3.BACK}), "setup: the dash should start"):
		return false
	# Raised after entering the dash, because entering clears stale intents.
	_player.attack_requested = true
	_player.dash_requested = true
	_player.knockback_component.add_knockback(TEST_KNOCKBACK)
	(_player.find_children("*", "WeaponSlot")[0] as WeaponSlot).enabled = true
	_player.hurtbox.hit_audio.play()
	_input.damage_tint.color = Color(Color.RED, 0.5)
	return check(_state() == "PlayerDash" and _input.dash_audio.playing and _player.knockback_component.is_active(), "setup: the player should be dashing noisily")


## Everything a transition must leave behind is gone right now.
func _check_quiet(when: String) -> void:
	check_eq(_state(), "PlayerRun", "the player should be running %s" % when)
	check(_player.velocity.is_zero_approx() and _player.move_direction.is_zero_approx(), "no motion should remain %s" % when)
	_check_no_residue(when)


## Watches the player until it lands back in running: no dash or attack may
## restart and no momentum may return on any frame (a spawn fall is allowed).
func _check_quiet_until_landed(when: String) -> void:
	var leak: Array[String] = []
	var landed: bool = await wait_until(func() -> bool:
		var state: String = _state()
		if leak.is_empty() and state != "PlayerRun" and state != "PlayerFall":
			leak.append("entered %s" % state)
		if leak.is_empty() and Vector2(_player.velocity.x, _player.velocity.z).length() > MOVING_SPEED:
			leak.append("moved at %s" % _player.velocity)
		return state == "PlayerRun" and _player.is_on_floor(), "the player should land back in running %s" % when, LANDING_FRAMES)
	check(leak.is_empty(), "nothing should reignite %s (%s)" % [when, leak])
	if landed:
		_check_no_residue("once landed " + when)


func _check_no_residue(when: String) -> void:
	check(not _player.attack_requested and not _player.dash_requested, "no pending intents %s" % when)
	check(not _player.knockback_component.is_active(), "no knockback %s" % when)
	check(not _player.is_attacking, "not attacking %s" % when)
	for slot: Node in _player.find_children("*", "WeaponSlot"):
		check(not (slot as WeaponSlot).enabled, "no live hitbox %s (%s)" % [when, slot.name])
	for audio: Node in _player.find_children("*", "AudioStreamPlayer3D"):
		check(not (audio as AudioStreamPlayer3D).playing, "no character SFX %s (%s)" % [when, audio.name])
	check(is_zero_approx(_input.damage_tint.color.a), "no damage tint %s" % when)


## The sound player wired to the weapon slot's slash signal, if any.
func _slash_audio(slot: WeaponSlot) -> AudioStreamPlayer3D:
	for connection: Dictionary in slot.slash.get_connections():
		var audio: AudioStreamPlayer3D = (connection["callable"] as Callable).get_object() as AudioStreamPlayer3D
		if audio != null:
			return audio
	return null


func _state() -> String:
	return str(_player.state_machine.state.name)
