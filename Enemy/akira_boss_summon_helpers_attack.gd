## Boss attack state that flexes and summons 4 melee enemies.
## 2 land around the boss and become regular melee enemies.
## The other 2 land at the boss backpacks and become 2 riders, restoring melee defense.
class_name AkiraBossSummonHelpersAttack
extends CharacterAttack

const LobbedSpawnProjectileClass = preload("res://Enemy/lobbed_spawn_projectile.gd")

## Projectile scene instantiated for the summoned helpers.
@export var projectile_scene: PackedScene
## Delay in seconds after entering before helpers are summoned (synced to flex peak).
@export var summon_delay: float = 1.0
## World reference to the left backpack mount.
@export var left_backpack: Node3D
## World reference to the right backpack mount.
@export var right_backpack: Node3D
## GameplayEffect applied to restore riders when backpack helpers land.
@export var rider_effect: GameplayEffect

var _backpack_helpers_landed: int = 0


func _ready() -> void:
	super._ready()
	if projectile_scene == null:
		projectile_scene = load("res://Enemy/lobbed_spawn_projectile.tscn") as PackedScene
	if rider_effect == null:
		rider_effect = load("res://Components/effect_has_riders.tres") as GameplayEffect


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	super.enter(_previous_state_path, _data)
	_backpack_helpers_landed = 0
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var timer: SceneTreeTimer = tree.create_timer(maxf(summon_delay, 0.0))
	timer.timeout.connect(_summon_helpers)


func _summon_helpers() -> void:
	if character == null or not is_instance_valid(character):
		return
	if not character.is_alive():
		return
	if character.state_machine == null or character.state_machine.state != self:
		return
	if projectile_scene == null:
		return

	# Helper 1 & 2: Ground helpers landing around the boss
	var ground_left: Vector3 = character.global_position + character.global_basis.x * -3.0 + character.global_basis.z * 1.5
	var ground_right: Vector3 = character.global_position + character.global_basis.x * 3.0 + character.global_basis.z * 1.5

	_spawn_ground_helper(ground_left)
	_spawn_ground_helper(ground_right)

	# Helper 3 & 4: Backpack helpers landing at the backpacks
	var pack_left: Vector3 = left_backpack.global_position if left_backpack != null and is_instance_valid(left_backpack) else character.global_position + Vector3(-0.75, 1.8, -0.45)
	var pack_right: Vector3 = right_backpack.global_position if right_backpack != null and is_instance_valid(right_backpack) else character.global_position + Vector3(0.75, 1.8, -0.45)

	_spawn_backpack_helper(pack_left)
	_spawn_backpack_helper(pack_right)


func _spawn_ground_helper(land_pos: Vector3) -> void:
	var proj: LobbedSpawnProjectileClass = projectile_scene.instantiate() as LobbedSpawnProjectileClass
	if proj == null:
		return
	proj.shooter = character
	proj.deal_area_damage = false
	proj.spawn_enemy_on_land = true
	# Arrive from high above
	var start_pos: Vector3 = land_pos + Vector3(0.0, 10.0, -1.0)
	proj.position = start_pos
	proj.set_target_position(land_pos)
	VfxManager.spawn_world_entity(proj)
	proj.initialize_trajectory()


func _spawn_backpack_helper(land_pos: Vector3) -> void:
	var proj: LobbedSpawnProjectileClass = projectile_scene.instantiate() as LobbedSpawnProjectileClass
	if proj == null:
		return
	proj.shooter = character
	proj.deal_area_damage = false
	proj.spawn_enemy_on_land = false
	proj.landing_callback = _on_backpack_helper_landed
	var start_pos: Vector3 = land_pos + Vector3(0.0, 10.0, -1.0)
	proj.position = start_pos
	proj.set_target_position(land_pos)
	VfxManager.spawn_world_entity(proj)
	proj.initialize_trajectory()


func _on_backpack_helper_landed(_pos: Vector3) -> void:
	_backpack_helpers_landed += 1
	if character == null or not is_instance_valid(character) or not character.is_alive():
		return
	# When backpack helpers land, restore the riders and effect
	if _backpack_helpers_landed >= 2:
		if rider_effect != null and character.attribute_component != null:
			character.attribute_component.apply_effect(rider_effect)
		elif character.attribute_component != null:
			character.attribute_component.add_tag(&"has_riders")
