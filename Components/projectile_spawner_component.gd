## Component that spawns projectiles at a designated bone/marker in the character's facing direction.
class_name ProjectileSpawnerComponent
extends Node

## Projectile scene to instantiate. Leave unset to use the GlobalVars registry.
@export var projectile_scene: PackedScene
## Node representing the projectile spawn origin (e.g., weapon bone or socket).
@export var spawn_point: Node3D
## Character executing the ranged attack.
@export var character: Character


func _ready() -> void:
	if character == null:
		character = get_parent() as Character


## Spawns a projectile aligned with the character's facing direction.
func spawn_projectile() -> void:
	var scene: PackedScene = projectile_scene if projectile_scene != null else GlobalVars.default_projectile_scene
	if scene == null or not is_inside_tree() or character == null:
		return
	var origin: Vector3 = character.global_position
	if spawn_point != null:
		origin = spawn_point.global_position
	elif character.mesh_mount != null:
		origin = character.mesh_mount.global_position
	var facing: Vector3 = character.mesh_mount.global_basis.z if character.mesh_mount != null else Vector3.ZERO
	PayloadSpawner.spawn(scene, character, origin, facing)
