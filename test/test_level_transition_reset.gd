## Every level spawns its own fresh player; only the run state crosses
## (ProgressionState.player_state, a PlayerRunState: gear, pools, and items
## bought while no player existed):
## - the next level's player is a new node that keeps the outgoing player's
##   health and stands on the new level's spawn point, running,
## - gear crosses once per equip (stacks included) without re-running its
##   instant effects, and an item bought with no player around (the shop) is
##   applied to the next player,
## - nothing transient crosses: a player leaving mid-dash or mid-attack,
##   burning, slowed or shaking hands over a quiet, fresh player,
## - the transition-start cancel silences the outgoing player at once (SFX,
##   damage tint), also from inside a physics callback (exit portals run it
##   from body_entered, where direct Area3D writes are locked),
## - SceneTransition.load_scene_path() captures the outgoing player's run
##   state. That changes the scene, so it runs last.
extends "res://test/lib/test_suite.gd"

const LEVEL_TEMPLATE_SCENE: PackedScene = preload("res://Levels/level_template.tscn")
const BURN_EFFECT: GameplayEffect = preload("res://Components/effect_fire_burn.tres")
## Test-owned transient state raised before the transition.
const TEST_KNOCKBACK: Vector3 = Vector3(5.0, 0.0, 0.0)
const TEST_SLOW: float = -0.5
const TEST_SLOW_DURATION: float = 5.0
const TEST_TRAUMA: float = 0.8
const TEST_WOUND: float = 42.0
## Test-owned gear: its lasting attack bonus and its instant heal.
const TEST_ATTACK_BONUS: float = 7.0
const TEST_HEAL: float = 30.0
## Horizontal speed above which the character is really moving (the
## KnockbackComponent.is_active threshold), not settling on the floor.
const MOVING_SPEED: float = 1.0
## Physics ticks allowed for a player to land back in running.
const LANDING_FRAMES: int = 120

var _player: Character


func before_each() -> void:
	ProgressionState.reset_run()
	_player = (_spawn_level() as LevelTemplate).player
	await wait_until(func() -> bool: return _state(_player) == "PlayerRun", "the player should settle in running")


func after_each() -> void:
	ProgressionState.reset_run()


func test_the_next_levels_player_is_new_keeps_its_health_and_stands_on_the_spawn() -> void:
	var health: float = _player.attribute_component.get_current(AttributeComponent.POOL_HEALTH) - TEST_WOUND
	_player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, health)
	_player.global_position += Vector3(3.0, 0.0, 3.0)
	var next: LevelTemplate = _leave_level()
	if not check(next.player != _player and is_instance_valid(next.player), "the next level should have its own, new player"):
		return
	check_approx(next.player.attribute_component.get_current(AttributeComponent.POOL_HEALTH), health, "the next player should keep the outgoing player's health")
	check(next.player == next.get_node("Player"), "the next player should be the level's own authored Player, on its spawn point")
	check_eq(next.player.process_mode, Node.PROCESS_MODE_INHERIT, "the next player should be running")


func test_gear_crosses_once_per_equip_without_rerunning_its_instant_effects() -> void:
	var gear: GearItemResource = _stacking_gear(&"test_carried_blade")
	var attack_before: float = _attack(_player)
	_player.equipment_component.equip_gear(gear)
	_player.equipment_component.equip_gear(gear)
	var carried_attack: float = _attack(_player)
	if not check_approx(carried_attack, attack_before + TEST_ATTACK_BONUS * 2.0, "setup: both equips should stack"):
		return
	var wounded: float = _player.attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH) - TEST_WOUND
	_player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, wounded)
	var next: LevelTemplate = _leave_level()
	check_approx(_attack(next.player), carried_attack, "the next player should wear the gear once per equip")
	check_eq(next.player.equipment_component.gear_history.size(), 2, "the next player should carry both equips")
	check_approx(next.player.attribute_component.get_current(AttributeComponent.POOL_HEALTH), wounded, "re-attaching gear must not run its instant heal again")


func test_an_item_bought_with_no_player_reaches_the_next_player() -> void:
	var gear: GearItemResource = _stacking_gear(&"test_shop_blade")
	var wounded: float = _player.attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH) - TEST_WOUND
	_player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, wounded)
	var attack_before: float = _attack(_player)
	ProgressionState.player_state.capture(_player)
	# Bought in the shop between levels, where no player exists.
	ProgressionState.player_state.pending_items.append(gear)
	var next: LevelTemplate = _spawn_level() as LevelTemplate
	check_approx(_attack(next.player), attack_before + TEST_ATTACK_BONUS, "the item bought in between should be equipped on the next player")
	check_approx(next.player.attribute_component.get_current(AttributeComponent.POOL_HEALTH), wounded + TEST_HEAL, "its instant heal should run once, on the next player")
	check(ProgressionState.player_state.pending_items.is_empty(), "a pending item should be applied only once")


func test_the_transition_start_cancel_silences_sfx_and_the_tint_at_once() -> void:
	if not _start_noisy_dash():
		return
	_player.cancel_movement_and_abilities()
	_check_quiet(_player, "after the transition-start cancel")


func test_a_player_leaving_mid_dash_or_mid_attack_hands_over_a_quiet_player() -> void:
	if not _start_noisy_dash():
		return
	var after_dash: Character = _leave_level().player
	_check_quiet(after_dash, "after leaving mid-dash")
	await _check_quiet_until_landed(after_dash, "after leaving mid-dash")
	var attack: CharacterAttack = after_dash.state_machine.get_node("PlayerRun").get("attack_state") as CharacterAttack
	if not check(after_dash.state_machine.request_state(attack.name, {"direction": Vector3.ZERO}), "setup: the attack should start"):
		return
	attack.queued_attack = true
	after_dash.dash_requested = true
	attack.get_weapon_slot().enabled = true
	_player = after_dash
	var after_attack: Character = _leave_level().player
	_check_quiet(after_attack, "after leaving mid-attack")
	await _check_quiet_until_landed(after_attack, "after leaving mid-attack")


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
	_check_quiet(_player, "after a cancel inside a physics callback")
	check(not slot.hitbox.monitoring and not slot.hitbox.monitorable, "the hitbox should be fully off after the cancel")


func test_burns_modifiers_shake_and_damage_numbers_do_not_cross_the_transition() -> void:
	var attributes: AttributeComponent = _player.attribute_component
	if not check(attributes.apply_effect(BURN_EFFECT) != &"", "setup: the burn should apply"):
		return
	var base_speed: float = attributes.get_current(AttributeComponent.STAT_SPEED)
	attributes.apply_modifier(AttributeComponent.STAT_SPEED, &"test_slow", Attribute.Op.MULT_ADD, TEST_SLOW, TEST_SLOW_DURATION)
	if not check(not is_equal_approx(attributes.get_current(AttributeComponent.STAT_SPEED), base_speed), "setup: the slow should apply"):
		return
	(_player.get_node("CameraRoot/ShakeCamera3D") as ShakeCamera3D).trauma = TEST_TRAUMA
	VfxManager.spawn_damage_number(_player, 10.0)
	await get_tree().process_frame
	if not check(_player.find_children("*", "StatusBurning", true, false).size() > 0, "setup: the burn should show its visual"):
		return
	var next: Character = _leave_level().player
	await get_tree().process_frame
	check(next.find_children("*", "StatusBurning", true, false).is_empty(), "the burn visual must not cross the transition")
	check_approx(next.attribute_component.get_current(AttributeComponent.STAT_SPEED), base_speed, "temporary modifiers must not cross the transition")
	check(is_zero_approx((next.get_node("CameraRoot/ShakeCamera3D") as ShakeCamera3D).trauma), "camera shake must not cross the transition")
	for child: Node in VfxManager.get_children():
		check(not (child is DamageNumber) or child.is_queued_for_deletion(), "damage numbers must not cross the transition")
	var health: float = next.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	await wait_physics_frames(ceili(BURN_EFFECT.duration * 0.5 * Engine.physics_ticks_per_second))
	check_approx(next.attribute_component.get_current(AttributeComponent.POOL_HEALTH), health, "the burn must not hurt the next player")


## Changes the scene: keep it the last test.
func test_leaving_through_the_scene_transition_captures_the_run_state() -> void:
	_player.equipment_component.equip_gear(_stacking_gear(&"test_transition_blade"))
	var wounded: float = _player.attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH) - TEST_WOUND
	_player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, wounded)
	SceneTransition.load_scene_path(LEVEL_TEMPLATE_SCENE.resource_path)
	var state: PlayerRunState = ProgressionState.player_state
	if check(state.pools.has(AttributeComponent.POOL_HEALTH), "the transition should capture the player's pools"):
		check_approx(state.pools[AttributeComponent.POOL_HEALTH], wounded, "the transition should capture the player's health")
	check_eq(state.gear.size(), 1, "the transition should capture the player's gear")


## A level template with its wave stopped. Its own player takes over the run
## state (LevelTemplate._ready).
func _spawn_level() -> Node3D:
	var level: Node3D = spawn(LEVEL_TEMPLATE_SCENE) as Node3D
	(level.get_node("WaveObjective") as WaveObjective).stop_spawning()
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		disable_ai(enemy as Character)
	return level


## Leaves the current level the way SceneTransition.load_scene_path() does
## (captures the run state, silences the outgoing player, clears world VFX)
## and spawns the next level, whose own player takes over.
func _leave_level() -> LevelTemplate:
	ProgressionState.player_state.capture(_player)
	_player.cancel_movement_and_abilities()
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	VfxManager.clear_temporary_effects()
	return _spawn_level() as LevelTemplate


## Test-owned gear: a lasting attack bonus that stacks per equip, and an
## instant heal.
func _stacking_gear(id: StringName) -> GearItemResource:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.effect_name = String(id) + "_effect"
	effect.target_attribute = AttributeComponent.STAT_ATTACK
	effect.operation = Attribute.Op.ADD
	effect.magnitude = TEST_ATTACK_BONUS
	effect.stacking = GameplayEffect.Stacking.STACK
	var gear: GearItemResource = GearItemResource.new()
	gear.id = id
	gear.gameplay_effects.append(effect)
	gear.instant_heal = TEST_HEAL
	return gear


func _attack(player: Character) -> float:
	return player.attribute_component.get_current(AttributeComponent.STAT_ATTACK)


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
	_tint(_player).color = Color(Color.RED, 0.5)
	return check(_state(_player) == "PlayerDash" and (_player.state_machine.get_node("PlayerDash") as PlayerDash).dash_audio.playing and _player.knockback_component.is_active(), "setup: the player should be dashing noisily")


## Everything a transition must leave behind is gone from player right now.
func _check_quiet(player: Character, when: String) -> void:
	check_eq(_state(player), "PlayerRun", "the player should be running %s" % when)
	check(player.velocity.is_zero_approx() and player.move_direction.is_zero_approx(), "no motion should remain %s" % when)
	_check_no_residue(player, when)


## Watches player until it lands back in running: no dash or attack may start
## and no momentum may appear on any frame (a spawn fall is allowed).
func _check_quiet_until_landed(player: Character, when: String) -> void:
	var leak: Array[String] = []
	var landed: bool = await wait_until(func() -> bool:
		var state: String = _state(player)
		if leak.is_empty() and state != "PlayerRun" and state != "PlayerFall":
			leak.append("entered %s" % state)
		if leak.is_empty() and Vector2(player.velocity.x, player.velocity.z).length() > MOVING_SPEED:
			leak.append("moved at %s" % player.velocity)
		return state == "PlayerRun" and player.is_on_floor(), "the player should land back in running %s" % when, LANDING_FRAMES)
	check(leak.is_empty(), "nothing should reignite %s (%s)" % [when, leak])
	if landed:
		_check_no_residue(player, "once landed " + when)


func _check_no_residue(player: Character, when: String) -> void:
	check(not player.attack_requested and not player.dash_requested, "no pending intents %s" % when)
	check(not player.knockback_component.is_active(), "no knockback %s" % when)
	check(not player.is_attacking, "not attacking %s" % when)
	for slot: Node in player.find_children("*", "WeaponSlot"):
		check(not (slot as WeaponSlot).enabled, "no live hitbox %s (%s)" % [when, slot.name])
	for audio: Node in player.find_children("*", "AudioStreamPlayer3D"):
		check(not (audio as AudioStreamPlayer3D).playing, "no character SFX %s (%s)" % [when, audio.name])
	check(is_zero_approx(_tint(player).color.a), "no damage tint %s" % when)


func _tint(player: Character) -> ColorRect:
	return (player.get_node("PlayerInputComponent") as PlayerInputComponent).damage_tint


func _state(player: Character) -> String:
	return str(player.state_machine.state.name)
