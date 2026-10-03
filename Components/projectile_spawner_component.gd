## Component that spawns projectiles at a designated bone/marker: a ranged
## attack's shot, aimed by the attack (see spawn_projectile()).
class_name ProjectileSpawnerComponent
extends Node

## Projectile scene to instantiate. Leave unset to use the GlobalVars registry.
@export var projectile_scene: PackedScene
## Node representing the projectile spawn origin (e.g., weapon bone or socket).
@export var spawn_point: Node3D
## Character executing the ranged attack.
@export var character: Character
## Scale the projectile's damage by the character's attack stat (the formula
## melee attacks and abilities use), so attack buffs reach ranged attacks.
@export var scale_with_attack: bool = true


func _ready() -> void:
	if character == null:
		character = get_parent() as Character


## Fires the projectile from the spawn point. Inside an action (the ranged
## attack whose animation calls this) it is that action's release, aimed at
## the attack's aim by its aim_mode (CharacterAction.release_payload());
## outside one it flies along the character's facing.
func spawn_projectile() -> void:
	var scene: PackedScene = projectile_scene if projectile_scene != null else GlobalVars.default_projectile_scene
	if scene == null or not is_inside_tree() or character == null:
		return
	var origin: Vector3 = character.global_position
	if spawn_point != null:
		origin = spawn_point.global_position
	elif character.mesh_mount != null:
		origin = character.mesh_mount.global_position
	var action: CharacterAction = character.state_machine.state as CharacterAction if character.state_machine != null else null
	if action != null:
		action.release_payload(scene, origin, [], 1.0, scale_with_attack)
		return
	var facing: Vector3 = character.mesh_mount.global_basis.z if character.mesh_mount != null else Vector3.ZERO
	PayloadSpawner.spawn(scene, character, origin, facing, [], 1.0, scale_with_attack)
