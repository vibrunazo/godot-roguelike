## The melee enemy (split from the old test_enemy_base):
## - its pursue AI attacks a player that comes within its attack range,
## - its weapon hurts the player but never another enemy (no friendly fire),
## - each swing can hit the same target again (hit exceptions reset per
##   attack),
## - its weapon slot switches the hitbox on and off.
## Ranges and damage are read from the enemy.
extends "res://test/lib/test_suite.gd"

const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned health, so no hit here can kill.
const TOUGH: float = 100000.0
## Frame budget for one attack.
const ATTACK_FRAMES: int = 600

var _arena: Node3D
var _melee: Character
var _attack: CharacterAttack


func before_each() -> void:
	_arena = load_arena()
	_melee = await _spawn_melee(Vector3(0.0, 1.0, -4.0))
	_attack = _melee.state_machine.get_node("EnemyAttack") as CharacterAttack


func test_the_pursue_ai_attacks_a_player_in_range() -> void:
	var pursue: AIPursue = _melee.ai_state_machine.get_node("AIPursue") as AIPursue
	await _spawn_player(_melee.global_position + Vector3(pursue.attack_range * 0.5, 0.0, 0.0))
	_melee.ai_state_machine.process_mode = Node.PROCESS_MODE_INHERIT
	_melee.ai_state_machine.request_state(pursue.name)
	await wait_until(func() -> bool: return _melee.state_machine.state.name == pursue.body_state.name, "the pursue AI should attack a player in range", ATTACK_FRAMES)


func test_the_weapon_hurts_the_player_but_never_another_enemy() -> void:
	var weapon: AttackComponent = _attack.get_attack_component()
	var slot: WeaponSlot = _attack.get_weapon_slot()
	var ally: Character = await _spawn_melee(Vector3(6.0, 1.0, -4.0))
	var player: Character = await _spawn_player(Vector3(-6.0, 1.0, -4.0))
	# Stack both targets on the hitbox: only the team filter can tell them apart.
	# Body collisions off, so the physics does not push the stacked bodies apart.
	_melee.animation_tree.active = false
	for character: Character in [_melee, ally, player]:
		character.collision_layer = 0
		character.collision_mask = 0
	ally.global_position = slot.hitbox.global_position
	player.global_position = slot.hitbox.global_position
	await wait_physics_frames(1)
	var ally_before: float = _health(ally)
	var player_before: float = _health(player)
	weapon.reset_exceptions()
	slot.enabled = true
	await wait_until(func() -> bool: return _health(player) < player_before, "the weapon should hurt the player", 10)
	check_approx(_health(ally), ally_before, "the weapon must never hurt another enemy")


func test_every_swing_can_hit_the_same_target_again() -> void:
	var player: Character = await _spawn_player(_melee.global_position + Vector3(0.0, 0.0, _adjacent()))
	for swing: int in range(2):
		var before: float = _health(player)
		_melee.state_machine.request_state(_attack.name, {"aim": Vector3.BACK})
		await wait_until(func() -> bool: return _melee.state_machine.state.name != _attack.name, "swing %d should end" % (swing + 1), ATTACK_FRAMES)
		check(_health(player) < before, "swing %d should hit the target" % (swing + 1))


func test_the_weapon_slot_switches_the_hitbox() -> void:
	var slot: WeaponSlot = _attack.get_weapon_slot()
	_melee.animation_tree.active = false
	check(not slot.hitbox.monitoring, "the hitbox should start off")
	# Inside a physics frame the slot defers the write: allow one tick.
	slot.enabled = true
	await wait_physics_frames(1)
	check(slot.hitbox.monitoring, "enabling the slot should switch the hitbox on")
	slot.enabled = false
	await wait_physics_frames(1)
	check(not slot.hitbox.monitoring, "disabling the slot should switch the hitbox off")


func _spawn_melee(at: Vector3) -> Character:
	var melee: Character = spawn(MELEE_SCENE, _arena, at) as Character
	disable_ai(melee)
	melee.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, TOUGH)
	await wait_until(func() -> bool: return melee.is_on_floor(), "setup: the enemy should land")
	return melee


func _spawn_player(at: Vector3) -> Character:
	var player: Character = spawn(PLAYER_SCENE, _arena, at) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, TOUGH)
	player.knockback_component.max_knockback = 0.0
	await wait_until(func() -> bool: return player.is_on_floor(), "setup: the player should land")
	return player


## Origin distance that leaves a small gap between the two capsules.
func _adjacent() -> float:
	var player: Character = PLAYER_SCENE.instantiate() as Character
	var radius: float = float((player.get_node("CollisionShape3D") as CollisionShape3D).shape.get("radius"))
	player.free()
	return float(_melee.collision_shape_3d.shape.get("radius")) + radius + 0.3


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
