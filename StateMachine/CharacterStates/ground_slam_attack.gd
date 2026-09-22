## Attack state that performs a ground slam, creating a cylindrical ground damage AOE
## at the impact point when the strike connects with the floor.
## Uses a downward physics raycast to detect true floor level so mid-air jumps,
## elevated stairs, and platform drops accurately place the ground hazard.
class_name GroundSlamAttack
extends CharacterAttack

## Scene instantiated for the ground damage AOE.
@export var aoe_scene: PackedScene = preload("res://Hazards/ground_damage_aoe.tscn")

## Radius in meters of the spawned ground damage AOE.
@export var aoe_radius: float = 3.0

## Height in meters of the spawned ground damage AOE (low height allows jump clearance).
@export var aoe_height: float = 0.4

## Forward distance in meters from the character to place the ground impact.
@export var aoe_forward_offset: float = 2.8

## Color tint applied to the ground AOE shockwave ring, disc, and particles.
@export var aoe_color: Color = Color(1.0, 0.65, 0.2, 1.0)

## Collision mask for downward raycast to locate floor geometry (1 = World / Environment).
@export var ground_raycast_mask: int = 1

## Maximum vertical distance in meters downward to search for the floor.
@export var max_ground_drop: float = 20.0

## Whether the ground slam deals friendly fire to allies of the attacker.
@export var friendly_fire: bool = false

var _aoe_spawned: bool = false


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	_aoe_spawned = false
	super.enter(_previous_state_path, _data)

	var slot: WeaponSlot = get_weapon_slot()
	if slot != null:
		connect_one_shot(slot.slash, _on_slam_impact)


## Overrides AttackComponent resolution so the hand bone hitbox does not deal direct damage.
## Slam damage is delivered exclusively through the spawned GroundDamageArea.
func get_attack_component() -> AttackComponent:
	return null


## Callback fired when the weapon slot reaches the ground impact apex.
func _on_slam_impact() -> void:
	if _aoe_spawned:
		return
	if character == null or not is_instance_valid(character) or not character.is_inside_tree():
		return
	if not character.is_alive():
		return
	if character.state_machine == null or character.state_machine.state != self:
		return

	_spawn_ground_aoe()


## Computes the floor impact position and spawns the GroundDamageArea.
func _spawn_ground_aoe() -> void:
	_aoe_spawned = true

	var scene_to_spawn: PackedScene = aoe_scene
	if scene_to_spawn == null:
		scene_to_spawn = load("res://Hazards/ground_damage_aoe.tscn") as PackedScene
	if scene_to_spawn == null:
		return

	var forward: Vector3 = _get_forward_vector()
	var prospective_pos: Vector3 = character.global_position + forward * aoe_forward_offset

	# If weapon slot is available and extended in front of the body, prefer its XZ placement
	var slot: WeaponSlot = get_weapon_slot()
	if slot != null:
		var slot_pos: Vector3 = slot.global_position
		var to_slot: Vector3 = slot_pos - character.global_position
		to_slot.y = 0.0
		if to_slot.length() > 0.5 and to_slot.normalized().dot(forward) > 0.2:
			prospective_pos.x = slot_pos.x
			prospective_pos.z = slot_pos.z

	# Locate true floor level via downward physics raycast
	var floor_y: float = _detect_floor_height(prospective_pos)
	prospective_pos.y = floor_y
	print("GroundSlamAttack AOE spawned at: ", prospective_pos, " forward: ", forward)

	var aoe_instance: GroundDamageArea = scene_to_spawn.instantiate() as GroundDamageArea
	if aoe_instance == null:
		return

	aoe_instance.radius = aoe_radius
	aoe_instance.height = aoe_height
	aoe_instance.damage = damage * (character.get_damage_modifier() if character.has_method("get_damage_modifier") else 1.0)
	aoe_instance.knockback_force = knockback
	aoe_instance.aoe_color = aoe_color
	aoe_instance.position = prospective_pos
	aoe_instance.set_wielder(character)

	var enemy_check: bool = character.is_enemy() if character.has_method("is_enemy") else true
	aoe_instance.can_hit_player = enemy_check
	aoe_instance.can_hit_enemies = not enemy_check
	aoe_instance.friendly_fire = friendly_fire

	VfxManager.spawn_world_entity(aoe_instance)


## Returns the forward facing unit vector in the horizontal XZ plane.
func _get_forward_vector() -> Vector3:
	if character == null:
		return Vector3.FORWARD
	if character.mesh_mount != null:
		var mount_z: Vector3 = character.mesh_mount.global_basis.z
		var flat: Vector3 = Vector3(mount_z.x, 0.0, mount_z.z)
		if not flat.is_zero_approx():
			return flat.normalized()
	# Fallback to standard Godot -Z forward
	var body_forward: Vector3 = -character.global_basis.z
	var flat_body: Vector3 = Vector3(body_forward.x, 0.0, body_forward.z)
	if not flat_body.is_zero_approx():
		return flat_body.normalized()
	return Vector3.FORWARD


## Casts a physics ray downward to find the actual floor surface height.
func _detect_floor_height(start_pos: Vector3) -> float:
	if character == null or not character.is_inside_tree():
		return start_pos.y
	var world_3d: World3D = character.get_world_3d()
	if world_3d == null:
		return start_pos.y
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if space_state == null:
		return start_pos.y

	var ray_start: Vector3 = Vector3(start_pos.x, character.global_position.y + 0.5, start_pos.z)
	var ray_end: Vector3 = Vector3(start_pos.x, character.global_position.y - max_ground_drop, start_pos.z)
	var ray_params := PhysicsRayQueryParameters3D.create(ray_start, ray_end, ground_raycast_mask)

	var result: Dictionary = space_state.intersect_ray(ray_params)
	if not result.is_empty() and result.has("position"):
		return (result["position"] as Vector3).y

	return character.global_position.y


func exit() -> void:
	_aoe_spawned = false
	var slot: WeaponSlot = get_weapon_slot()
	if slot != null:
		disconnect_safe(slot.slash, _on_slam_impact)
	super.exit()
