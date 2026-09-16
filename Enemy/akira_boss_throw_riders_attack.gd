## Boss attack state that throws the two backpack riders at the target.
## Upon landing, the thrown riders deal area damage and become regular melee enemies.
## Detaches the riders from the boss backpack so they no longer provide melee defense.
class_name AkiraBossThrowRidersAttack
extends CharacterAttack

const LobbedSpawnProjectileClass = preload("res://Enemy/lobbed_spawn_projectile.gd")

## Projectile scene instantiated for the thrown riders.
@export var projectile_scene: PackedScene
## Delay in seconds after entering before riders are thrown (synced to slash apex).
@export var throw_delay: float = 0.45
## Area damage dealt when each thrown rider lands.
@export var impact_damage: float = 20.0
## Radius in meters of the landing area damage.
@export var impact_radius: float = 3.0
## Knockback impulse applied to targets caught in the landing area damage.
@export var impact_knockback: float = 15.0
## World spawn point for the left thrown rider (defaults to boss left backpack).
@export var left_spawn_point: Node3D
## World spawn point for the right thrown rider (defaults to boss right backpack).
@export var right_spawn_point: Node3D
## GameplayEffect representing backpack riders to remove upon throwing.
@export var rider_effect: GameplayEffect


func _ready() -> void:
	super._ready()
	if projectile_scene == null:
		projectile_scene = load("res://Enemy/lobbed_spawn_projectile.tscn") as PackedScene
	if rider_effect == null:
		rider_effect = load("res://Components/effect_has_riders.tres") as GameplayEffect


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	super.enter(_previous_state_path, _data)
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var timer: SceneTreeTimer = tree.create_timer(maxf(throw_delay, 0.0))
	timer.timeout.connect(_throw_riders)


func _throw_riders() -> void:
	if character == null or not is_instance_valid(character):
		return
	if not character.is_alive():
		return
	if character.state_machine == null or character.state_machine.state != self:
		return

	# Remove has_riders GameplayEffect and tag from boss
	if character.attribute_component != null:
		character.attribute_component.remove_effect(&"has_riders")
		character.attribute_component.remove_tag(&"has_riders")

	# Resolve target ground position
	var target: Character = null
	if character.current_target != null and is_instance_valid(character.current_target) and character.current_target is Character:
		target = character.current_target as Character
	elif character.is_inside_tree():
		target = character.get_nearest_target("player")
	if target == null and is_inside_tree():
		target = get_tree().get_first_node_in_group("player") as Character

	var target_pos: Vector3 = character.global_position + character.global_basis.z * 8.0
	if target != null and is_instance_valid(target):
		target_pos = target.global_position

	# Calculate spread for landing
	var to_target: Vector3 = target_pos - character.global_position
	to_target.y = 0.0
	var right_vec: Vector3 = to_target.normalized().cross(Vector3.UP)
	if right_vec.is_zero_approx():
		right_vec = Vector3.RIGHT

	var left_land: Vector3 = target_pos - right_vec * 1.5
	var right_land: Vector3 = target_pos + right_vec * 1.5

	var left_pos: Vector3 = left_spawn_point.global_position if left_spawn_point != null and is_instance_valid(left_spawn_point) else character.global_position + Vector3(-0.75, 1.8, -0.45)
	var right_pos: Vector3 = right_spawn_point.global_position if right_spawn_point != null and is_instance_valid(right_spawn_point) else character.global_position + Vector3(0.75, 1.8, -0.45)

	_spawn_rider_projectile(left_pos, left_land)
	_spawn_rider_projectile(right_pos, right_land)


func _spawn_rider_projectile(spawn_pos: Vector3, land_pos: Vector3) -> void:
	if projectile_scene == null:
		return
	var proj: LobbedSpawnProjectileClass = projectile_scene.instantiate() as LobbedSpawnProjectileClass
	if proj == null:
		return
	proj.shooter = character
	proj.damage = impact_damage
	proj.area_damage = impact_damage
	proj.area_radius = impact_radius
	proj.area_knockback = impact_knockback
	proj.deal_area_damage = true
	proj.spawn_enemy_on_land = true
	proj.position = spawn_pos
	proj.set_target_position(land_pos)
	VfxManager.spawn_world_entity(proj)
	proj.initialize_trajectory()
