## Hit feedback on the player, plus the pieces it relies on:
## - Being struck flashes the red damage tint and shakes the camera; both
##   fade back out within their configured durations. The tint never blocks
##   mouse input.
## - Landing a hit with a weapon whose AttackComponent has shake_on_damage
##   shakes the camera; hits without it, and swings that hit nothing, do not.
## - Only the player's own hits and hurts shake the camera: a trap or an enemy
##   weapon hitting an enemy never does, even with shake_on_damage forced on,
##   while a trap hitting the player does.
## - Every landed hit spawns a damage number showing the damage, anchored to
##   the victim and projected to the screen.
## - KnockbackComponent clamps to max_knockback, decays over time, and
##   overrides movement while active.
## - AttackComponent.reset_exceptions() tolerates exceptions that were freed.
## Magnitudes and durations are read from the live components, so retuning
## any of them never breaks the suite.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const SPIKES_SCENE: PackedScene = preload("res://Hazards/spikes_hazard.tscn")
## Test-owned damage for direct hits.
const TEST_DAMAGE: float = 5.0

var _arena: Node3D
var _player: Character
var _camera: ShakeCamera3D
var _input: PlayerInputComponent


func before_each() -> void:
	_arena = load_arena()
	_player = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	_input = _player.get_node("PlayerInputComponent") as PlayerInputComponent
	_input.set_physics_process(false)
	_camera = _player.get_node("CameraRoot/ShakeCamera3D") as ShakeCamera3D
	_camera.make_current()
	await wait_until(func() -> bool: return _player.is_on_floor(), "player should land")
	_camera.trauma = 0.0


func test_being_struck_flashes_the_tint_and_shakes_the_camera() -> void:
	var tint: ColorRect = _input.damage_tint
	check(is_zero_approx(tint.color.a), "the damage tint should start transparent")
	check_eq(tint.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the full-screen damage tint must never block mouse input")
	var health_before: float = _health(_player)
	check(_player.hurtbox.receive_hit(TEST_DAMAGE, Vector3.ZERO), "the hit should land")
	check_approx(health_before - _health(_player), TEST_DAMAGE, "the hit should deal its damage")
	# Flash and shake are visual tweens on the render clock: wait for them
	# rather than assuming how many physics ticks pass before a render frame.
	await wait_until(func() -> bool: return tint.color.a > 0.0, "being struck should flash the damage tint", _frames_for(_input.damage_tint_duration))
	await wait_until(func() -> bool: return _camera.trauma > 0.0, "being struck should shake the camera", _frames_for(_camera.shake_duration))
	await wait_until(func() -> bool: return is_zero_approx(tint.color.a), "the tint should fade out within damage_tint_duration", _frames_for(_input.damage_tint_duration))
	await wait_until(func() -> bool: return is_zero_approx(_camera.trauma), "the shake should decay within shake_duration", _frames_for(_camera.shake_duration))


func test_landing_a_hit_with_shake_on_damage_shakes_the_camera() -> void:
	var attack: AttackComponent = _player_weapon()
	attack.shake_on_damage = true
	var dummy: Character = spawn(MELEE_SCENE, _arena, (_arena.get_node("EnemySpawn") as Node3D).global_position) as Character
	disable_ai(dummy)
	await wait_physics_frames(1)
	check(attack.deal_damage_to(dummy.hurtbox, TEST_DAMAGE, Vector3.ZERO), "the weapon hit should land")
	await wait_until(func() -> bool: return _camera.trauma > 0.0, "a landed hit with shake_on_damage should shake the camera", _frames_for(_camera.shake_duration))
	await wait_until(func() -> bool: return is_zero_approx(_camera.trauma), "the shake should decay within shake_duration", _frames_for(_camera.shake_duration))


func test_a_landed_hit_without_shake_on_damage_does_not_shake() -> void:
	var attack: AttackComponent = _player_weapon()
	attack.shake_on_damage = false
	var dummy: Character = spawn(MELEE_SCENE, _arena, (_arena.get_node("EnemySpawn") as Node3D).global_position) as Character
	disable_ai(dummy)
	await wait_physics_frames(1)
	check(attack.deal_damage_to(dummy.hurtbox, TEST_DAMAGE, Vector3.ZERO), "the weapon hit should land")
	check(is_zero_approx(await _peak_trauma(_frames_for(_camera.shake_duration))), "a hit from a weapon without shake_on_damage must not shake the camera")


func test_a_swing_that_hits_nothing_does_not_shake() -> void:
	var attack: AttackComponent = _player_weapon()
	attack.shake_on_damage = true
	var hitbox: Area3D = attack.get_parent() as Area3D
	hitbox.monitoring = true
	var peak: float = await _peak_trauma(_frames_for(_camera.shake_duration))
	hitbox.monitoring = false
	check(is_zero_approx(peak), "a swing that hits nothing must not shake the camera")


func test_a_trap_hitting_an_enemy_never_shakes_the_camera() -> void:
	var trap: AttackComponent = await _spawn_trap_weapon()
	var enemy: Character = await _spawn_enemy()
	trap.shake_on_damage = true
	check(trap.deal_damage_to(enemy.hurtbox, TEST_DAMAGE, Vector3.ZERO), "the trap hit should land")
	check(is_zero_approx(await _peak_trauma(_frames_for(_camera.shake_duration))), "a trap hitting an enemy must not shake the camera, even with shake_on_damage")


func test_a_trap_hitting_the_player_shakes_the_camera() -> void:
	var trap: AttackComponent = await _spawn_trap_weapon()
	check(trap.deal_damage_to(_player.hurtbox, TEST_DAMAGE, Vector3.ZERO), "the trap hit should land")
	await wait_until(func() -> bool: return _camera.trauma > 0.0, "a trap hitting the player should shake the camera", _frames_for(_camera.shake_duration))


func test_an_enemy_weapon_hitting_an_enemy_never_shakes_the_camera() -> void:
	var attacker: Character = await _spawn_enemy()
	var victim: Character = await _spawn_enemy(Vector3(3.0, 0.0, 0.0))
	var weapon: AttackComponent = (attacker.state_machine.get_node("EnemyAttack") as CharacterAttack).get_attack_component()
	weapon.shake_on_damage = true
	check(weapon.deal_damage_to(victim.hurtbox, TEST_DAMAGE, Vector3.ZERO), "the enemy weapon hit should land")
	check(is_zero_approx(await _peak_trauma(_frames_for(_camera.shake_duration))), "an enemy hitting an enemy must not shake the camera, even with shake_on_damage")


func test_a_landed_hit_spawns_a_damage_number_at_the_victim() -> void:
	var dummy: Character = spawn(MELEE_SCENE, _arena, (_arena.get_node("EnemySpawn") as Node3D).global_position) as Character
	disable_ai(dummy)
	await wait_physics_frames(1)
	var existing: Array[Node] = VfxManager.get_children()
	dummy.hurtbox.receive_hit(TEST_DAMAGE, Vector3.ZERO)
	var number: DamageNumber = null
	for child: Node in VfxManager.get_children():
		if child is DamageNumber and not existing.has(child):
			number = child as DamageNumber
	if not check(number != null, "a landed hit should spawn a damage number"):
		return
	autofree(number)
	check(number.target_position.is_equal_approx(dummy.global_position), "the damage number should be anchored to the victim")
	check_eq(number.label.text, "%d" % TEST_DAMAGE, "the damage number should show the damage dealt")
	await wait_physics_frames(1)
	check(number.position.is_equal_approx(_camera.unproject_position(number.target_position)), "the damage number should follow its anchor on screen")


func test_knockback_clamps_decays_and_overrides_movement() -> void:
	var knockback: KnockbackComponent = _player.knockback_component
	check(not knockback.is_active(), "knockback should start inactive")
	knockback.add_knockback(Vector3(0.0, 0.0, knockback.max_knockback * 2.0))
	check_approx(knockback.magnitude.length(), knockback.max_knockback, "knockback should be clamped to max_knockback")
	var before_decay: float = knockback.magnitude.length()
	await wait_physics_frames(2)
	check(knockback.magnitude.length() < before_decay, "knockback should decay over time")
	# While knockback is active it overrides the movement the state wants.
	await wait_until(func() -> bool: return _player.is_on_floor(), "player should be grounded for the movement check")
	var push: Vector3 = Vector3(knockback.max_knockback * 0.5, 0.0, 0.0)
	knockback.magnitude = push
	var run_state: CharacterState = _player.state_machine.get_node("PlayerRun") as CharacterState
	run_state.core_movement(1.0 / Engine.physics_ticks_per_second, _player.attribute_component.get_current(AttributeComponent.STAT_SPEED), Vector3(0.0, 0.0, 1.0))
	check(_player.velocity.is_equal_approx(push), "active knockback should override the movement velocity")
	knockback.magnitude = Vector3.ZERO


func test_reset_exceptions_tolerates_freed_exceptions() -> void:
	var attack: AttackComponent = _player_weapon()
	var doomed: StaticBody3D = StaticBody3D.new()
	add_child(doomed)
	attack.add_exception(doomed)
	doomed.free()
	attack.reset_exceptions()
	check(attack.temporary_exceptions.is_empty(), "reset_exceptions() should clear every exception, freed ones included")


## Highest camera trauma seen over the next frames. Negative checks must
## watch the whole window: a shake that already decayed reads as zero.
func _peak_trauma(frames: int) -> float:
	var peak: float = _camera.trauma
	for i: int in range(frames):
		await get_tree().physics_frame
		peak = maxf(peak, _camera.trauma)
	return peak


## A still melee enemy near the arena's enemy spawn.
func _spawn_enemy(offset: Vector3 = Vector3.ZERO) -> Character:
	var enemy: Character = spawn(MELEE_SCENE, _arena, (_arena.get_node("EnemySpawn") as Node3D).global_position + offset) as Character
	disable_ai(enemy)
	await wait_physics_frames(1)
	return enemy


## The AttackComponent of a spikes trap parked far from everyone.
func _spawn_trap_weapon() -> AttackComponent:
	var spikes: SpikesHazard = spawn(SPIKES_SCENE, _arena, Vector3(15.0, 0.0, -15.0)) as SpikesHazard
	await wait_physics_frames(1)
	return spikes.attack_component


## The AttackComponent of the player's first combo attack (its weapon).
func _player_weapon() -> AttackComponent:
	return (_player.state_machine.get_node("PlayerAttack") as CharacterAttack).get_attack_component()


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## Physics frames covering the given game time, plus a small margin.
func _frames_for(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 5
