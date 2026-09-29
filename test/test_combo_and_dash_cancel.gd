## The player's full combo and dash cancels, in the arena against a still
## dummy:
## - pressing attack in every combo attack chains the whole combo (first
##   attack -> combo_next -> ...) and each attack lands at least one hit,
## - attacks without a lunge (dash_speed 0) stay in place; lunging attacks
##   move along their aim with a unit lunge direction,
## - out of combat the jump button dash-cancels attacks with dash_cancel and
##   plays the dash visual; attacks without dash_cancel ignore it,
## - a dash cancel drops a queued combo follow-up,
## - a standing dash goes along the facing,
## - the slash trail shows only while its weapon slot is in its attack mode
##   and follows the slot's vfx_threshold.
## Damage, combo links and lunge settings are read from the live states.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const SLASH_VFX_SCRIPT_PATH: String = "res://Player/slash_vfx.gd"
## Test-owned dummy health, high enough that no attack here can kill it.
const DUMMY_HEALTH: float = 100000.0
## Frame budget for one attack or dash.
const ACTION_FRAMES: int = 600
## Test-owned vfx threshold for the slash trail check.
const TEST_THRESHOLD: float = 0.3
## Horizontal drift (meters) still counted as "in place".
const IN_PLACE_TOLERANCE: float = 0.05

var _arena: Node3D
var _player: Character
var _dummy: Character
var _first_attack: CharacterAttack
var _dash: PlayerDash


func before_each() -> void:
	_arena = load_arena()
	_dummy = spawn(MELEE_SCENE, _arena, Vector3(0.0, 1.0, 0.0)) as Character
	disable_ai(_dummy)
	_dummy.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, DUMMY_HEALTH)
	_dummy.knockback_component.max_knockback = 0.0
	_player = spawn(PLAYER_SCENE, _arena, Vector3(0.0, 1.0, _adjacent_distance())) as Character
	# Out of combat on purpose: without an auto-aim lock the jump button
	# always dashes. Live mouse aim off: attacks aim at the dummy.
	_aim().auto_aim_range = 0.0
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	_player.aim_direction = Vector3.FORWARD
	var run: CharacterState = _player.state_machine.get_node("PlayerRun") as CharacterState
	_first_attack = run.attack_state as CharacterAttack
	_dash = run.dash_state as PlayerDash
	await wait_until(func() -> bool: return _player.is_on_floor() and _dummy.is_on_floor() and _state() == "PlayerRun", "player and dummy should settle")


func test_the_full_combo_chains_and_every_attack_lands() -> void:
	var chain: Array[CharacterAttack] = _combo_chain()
	if not check(chain.size() > 1, "setup: the first attack should chain into a combo"):
		return
	press_action(&"click")
	for attack: CharacterAttack in chain:
		if not await wait_until(func() -> bool: return _state() == attack.name, "the combo should reach %s" % attack.name, ACTION_FRAMES):
			return
		var health_before: float = _health()
		if attack.combo_next != null:
			press_action(&"click")
		await wait_until(func() -> bool: return _state() != attack.name, "%s should finish" % attack.name, ACTION_FRAMES)
		check(health_before - _health() >= _hit(attack) - 0.001, "%s should land at least one hit of its damage" % attack.name)
	check_eq(_state(), "PlayerRun", "the finished combo should return to running")


func test_attacks_without_a_lunge_stay_in_place_and_lunges_move_along_the_aim() -> void:
	# Clear the way so lunges are never blocked by the dummy.
	_dummy.global_position = Vector3(20.0, 1.0, -20.0)
	await wait_physics_frames(1)
	for attack: CharacterAttack in _combo_chain():
		_player.aim_direction = Vector3.FORWARD
		var start: Vector3 = _player.global_position
		_player.state_machine.request_state(attack.name)
		var lunge_seen: Array[bool] = [false]
		await wait_until(func() -> bool:
			if attack.lunging and not lunge_seen[0]:
				lunge_seen[0] = true
				check_approx(attack.lunge_direction.length(), 1.0, "%s should lunge along a unit direction" % attack.name)
			return _state() != attack.name, "%s should finish" % attack.name, ACTION_FRAMES)
		var travel: Vector3 = _player.global_position - start
		travel.y = 0.0
		if attack.dash_speed > 0.0:
			check(lunge_seen[0], "%s has a dash_speed and should lunge" % attack.name)
			check(travel.dot(Vector3.FORWARD) > IN_PLACE_TOLERANCE, "%s should lunge along its aim" % attack.name)
		else:
			check(travel.length() < IN_PLACE_TOLERANCE, "%s has no dash_speed and should stay in place (moved %.3f m)" % [attack.name, travel.length()])
		await wait_until(func() -> bool: return _player.is_on_floor() and _state() == "PlayerRun", "the player should be back in running")


func test_the_jump_button_dash_cancels_a_dash_cancellable_attack() -> void:
	_first_attack.dash_cancel = true
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == _first_attack.name, "setup: the attack should start", 10):
		return
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() == _dash.name, "out of combat the jump button should dash-cancel the attack", 10):
		return
	check(_dash.dash_animation_player != null and _dash.dash_animation_player.current_animation == "dash", "the dash should play its visual")
	await wait_until(func() -> bool: return _state() == "PlayerRun", "the dash should end in running", ACTION_FRAMES)


func test_an_attack_without_dash_cancel_cannot_be_dashed_out_of() -> void:
	_first_attack.dash_cancel = false
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == _first_attack.name, "setup: the attack should start", 10):
		return
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() != _first_attack.name, "the attack should finish", ACTION_FRAMES):
		return
	check_eq(_state(), "PlayerRun", "the attack should finish into running, ignoring the dash press")


func test_a_dash_cancel_drops_the_queued_combo_attack() -> void:
	var next_attack: State = _first_attack.combo_next
	if not check(next_attack != null, "setup: the first attack should chain into a combo_next"):
		return
	_first_attack.dash_cancel = true
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == _first_attack.name, "setup: the attack should start", 10):
		return
	press_action(&"click")
	if not await wait_until(func() -> bool: return _first_attack.queued_attack, "setup: a second press should queue the combo follow-up", 10):
		return
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() == _dash.name, "the dash should cancel the attack despite the queued follow-up", 10):
		return
	# Watch past the queue window after the dash: the follow-up must never fire.
	var chained: Array[bool] = [false]
	var watch: int = ceili(_first_attack.queued_attack_time * Engine.physics_ticks_per_second)
	await wait_until(func() -> bool:
		chained[0] = chained[0] or _state() == next_attack.name
		return _state() == "PlayerRun", "the dash should end in running", ACTION_FRAMES)
	for tick: int in range(watch):
		await get_tree().physics_frame
		chained[0] = chained[0] or _state() == next_attack.name
	check(not chained[0], "the queued follow-up must be dropped by the dash cancel")


func test_a_standing_dash_goes_along_the_facing() -> void:
	var facing: Vector3 = _player.mesh_mount.global_basis.z.normalized()
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() == _dash.name, "the jump button should dash with no input held", 10):
		return
	check(_dash.direction.dot(facing) > 0.99, "a standing dash should go along the facing")


func test_the_slash_trail_follows_its_weapon_slot() -> void:
	var trail: MeshInstance3D = _find_slash_trail()
	if not check(trail != null, "setup: the player should carry a slash trail"):
		return
	var slot: WeaponSlot = trail.get("weapon_slot") as WeaponSlot
	var trail_mode: int = trail.get("attack_type") as int
	if not check(slot != null and trail_mode != WeaponSlot.mode.NONE, "setup: the trail should watch a weapon slot for an attack mode"):
		return
	# The attack animations drive the slot; hold them still in running.
	slot.attack_mode = WeaponSlot.mode.NONE
	await get_tree().process_frame
	check(not trail.visible, "the trail should hide while the slot is not attacking")
	slot.attack_mode = trail_mode
	slot.vfx_threshold = TEST_THRESHOLD
	await get_tree().process_frame
	check(trail.visible, "the trail should show while the slot is in its attack mode")
	check_approx((trail.material_override as ShaderMaterial).get_shader_parameter("Threshold") as float, TEST_THRESHOLD, "the trail shader should follow the slot's vfx_threshold")


## The combo from the first attack, following combo_next links.
func _combo_chain() -> Array[CharacterAttack]:
	var chain: Array[CharacterAttack] = []
	var attack: CharacterAttack = _first_attack
	while attack != null and not chain.has(attack):
		chain.append(attack)
		attack = attack.combo_next as CharacterAttack
	return chain


func _find_slash_trail() -> MeshInstance3D:
	for node: Node in _player.find_children("*", "MeshInstance3D", true, false):
		var script: Script = node.get_script() as Script
		if script != null and script.resource_path == SLASH_VFX_SCRIPT_PATH:
			return node as MeshInstance3D
	return null


func _state() -> String:
	return str(_player.state_machine.state.name)


func _health() -> float:
	return _dummy.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## Damage one hit of the attack deals.
func _hit(attack: CharacterAttack) -> float:
	return attack.damage * _player.get_damage_modifier()


## Distance between origins that leaves a small gap between the capsules.
func _adjacent_distance() -> float:
	var player: Character = PLAYER_SCENE.instantiate() as Character
	var player_radius: float = float((player.get_node("CollisionShape3D") as CollisionShape3D).shape.get("radius"))
	player.free()
	return float(_dummy.collision_shape_3d.shape.get("radius")) + player_radius + 0.3


## The player's auto-aim (TargetingComponent).
func _aim() -> TargetingComponent:
	return _player.get_node("TargetingComponent") as TargetingComponent
