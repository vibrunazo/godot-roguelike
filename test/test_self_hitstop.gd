## Self hitstop: landing a hit briefly slows the attacker itself (animation
## speed and attack movement scaled by self_hitstop_scale for
## self_hitstop_duration), per attack state, for players and enemies alike.
## Leaving the attack early clears it, and a zero duration disables it.
##
## Each test sets the hitstop scale and duration on the attack it exercises,
## so designers can retune the real values (or turn hitstop off for an
## attack) without breaking the suite.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
## Test-owned hitstop configuration.
const TEST_SCALE: float = 0.2
const TEST_DURATION: float = 0.1
## Test-owned health so no hit in this suite can kill.
const DUMMY_HEALTH: float = 100000.0
## Frame budget for one attack animation.
const ATTACK_FRAMES: int = 600

var _arena: Node3D
var _player: Character
var _dummy: Character


func before_each() -> void:
	_arena = load_arena()
	_dummy = _spawn_dummy(MELEE_SCENE, Vector3(0.0, 1.0, 0.0))
	_player = _spawn_dummy(PLAYER_SCENE, Vector3(0.0, 1.0, _adjacent_distance(_dummy, PLAYER_SCENE)))
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	await wait_until(func() -> bool: return _player.is_on_floor() and _dummy.is_on_floor() and _player.state_machine.state.name == "PlayerRun", "player and dummy should settle")


func test_landing_a_hit_slows_the_attacker() -> void:
	var slash: CharacterAttack = _configured_attack(_player, "PlayerAttack")
	var health_before: float = _health(_dummy)
	if not await _attack_and_wait_for_hit(_player, slash, _dummy):
		return
	check_approx(health_before - _health(_dummy), slash.damage * _player.get_damage_modifier(), "the hit should deal the attack's damage")
	check(slash.is_in_hitstop(), "landing a hit should put the attacker in hitstop")
	var speed: Variant = _player.animation_tree.get(_timescale_param(slash))
	if speed is float:
		check_approx(speed as float, TEST_SCALE, "the attack animation should slow to self_hitstop_scale")


func test_hitstop_expires_after_its_duration_and_restores_speed() -> void:
	var slash: CharacterAttack = _configured_attack(_player, "PlayerAttack")
	var base_speed: Variant = _player.animation_tree.get(_timescale_param(slash))
	if not await _attack_and_wait_for_hit(_player, slash, _dummy):
		return
	var budget: int = ceili(TEST_DURATION * Engine.physics_ticks_per_second) + 2
	await wait_until(func() -> bool: return not slash.is_in_hitstop(), "hitstop should end once self_hitstop_duration has elapsed", budget)
	if base_speed is float:
		check_approx(_player.animation_tree.get(_timescale_param(slash)) as float, base_speed as float, "animation speed should be restored after hitstop")


func test_hitstop_scales_attack_movement() -> void:
	# The stab lunges; while in hitstop its lunge velocity is scaled.
	var stab: CharacterAttack = _configured_attack(_player, "PlayerAttack2")
	_player.state_machine.request_state("PlayerAttack2")
	stab.lunging = true
	stab.lunge_direction = Vector3.FORWARD
	stab.hitstop_time_remaining = TEST_DURATION
	stab.physics_update(1.0 / Engine.physics_ticks_per_second)
	var slowed_speed: float = _player.velocity.length()
	stab.hitstop_time_remaining = 0.0
	stab.physics_update(1.0 / Engine.physics_ticks_per_second)
	var full_speed: float = _player.velocity.length()
	if check(full_speed > 0.0, "the lunge should move the attacker"):
		check_approx(slowed_speed, full_speed * TEST_SCALE, "lunge velocity during hitstop should be scaled by self_hitstop_scale")


func test_leaving_the_attack_clears_hitstop() -> void:
	var slash: CharacterAttack = _configured_attack(_player, "PlayerAttack")
	var base_speed: Variant = _player.animation_tree.get(_timescale_param(slash))
	if not await _attack_and_wait_for_hit(_player, slash, _dummy):
		return
	if not check(slash.is_in_hitstop(), "setup: the attacker should be in hitstop"):
		return
	# Any forced exit (dash cancel, stun, scene change) runs the same exit().
	_player.state_machine.request_state("PlayerRun")
	check(not slash.is_in_hitstop(), "hitstop must not outlive the attack state")
	if base_speed is float:
		check_approx(_player.animation_tree.get(_timescale_param(slash)) as float, base_speed as float, "a slowed animation speed must not leak past the attack")
	# A hit landed by the same weapon after the attack must not restart it.
	var component: AttackComponent = slash.get_attack_component()
	if component != null:
		component.reset_exceptions()
		component.deal_damage_to(_dummy.hurtbox, component.damage, component.knockback)
		check(not slash.is_in_hitstop(), "a hit landed after the attack ended must not put that attack back into hitstop")


func test_zero_duration_disables_hitstop() -> void:
	var slash: CharacterAttack = _configured_attack(_player, "PlayerAttack")
	slash.self_hitstop_duration = 0.0
	slash.apply_self_hitstop()
	check(not slash.is_in_hitstop(), "a zero self_hitstop_duration should disable hitstop")


func test_enemy_attacks_hitstop_on_hit() -> void:
	var attack: CharacterAttack = _configured_attack(_dummy, "EnemyAttack")
	var target_z: float = _player.global_position.z
	_dummy.aim_direction = Vector3(0.0, 0.0, signf(target_z - _dummy.global_position.z))
	if not await _attack_and_wait_for_hit(_dummy, attack, _player):
		return
	check(attack.is_in_hitstop(), "an enemy attack landing a hit should put the enemy in hitstop")


# --- helpers -----------------------------------------------------------------

func _configured_attack(character: Character, state_name: String) -> CharacterAttack:
	var attack: CharacterAttack = character.state_machine.get_node(state_name) as CharacterAttack
	attack.self_hitstop_scale = TEST_SCALE
	attack.self_hitstop_duration = TEST_DURATION
	return attack


## Starts the attack aimed at the victim and waits for its first hit.
func _attack_and_wait_for_hit(attacker: Character, attack: CharacterAttack, victim: Character) -> bool:
	var to_victim: Vector3 = victim.global_position - attacker.global_position
	to_victim.y = 0.0
	attacker.aim_direction = to_victim.normalized()
	attacker.state_machine.request_state(attack.name, {"aim": to_victim.normalized()})
	return await wait_signal(victim.hurtbox.struck, "%s should land on the adjacent target" % attack.name, ATTACK_FRAMES)


func _timescale_param(attack: CharacterAttack) -> String:
	return "parameters/%s/TimeScale/scale" % attack.animation_name


func _spawn_dummy(scene: PackedScene, at: Vector3) -> Character:
	var character: Character = spawn(scene, _arena, at) as Character
	disable_ai(character)
	character.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, DUMMY_HEALTH)
	if character.knockback_component != null:
		character.knockback_component.max_knockback = 0.0
	return character


## Distance between origins that leaves a small gap between the capsules.
func _adjacent_distance(first: Character, second_scene: PackedScene) -> float:
	var second: Character = second_scene.instantiate() as Character
	var second_radius: float = float((second.get_node("CollisionShape3D") as CollisionShape3D).shape.get("radius"))
	second.free()
	return float(first.collision_shape_3d.shape.get("radius")) + second_radius + 0.3


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
