## World-space visual effects service, registered as the `VfxManager` autoload
## (script) in `project.godot`. Access from anywhere via `VfxManager`, e.g.
## `VfxManager.spawn_damage_number(source, 10.0)`.
##
## Unique responsibilities:
## - Floating combat text (`spawn_damage_number`, parented to itself as screen-space UI).
## - World-space spawning (`spawn_world_entity`): parents gameplay entities and
##   effects (projectiles, impact VFX) to the active level so they outlive the
##   actor that spawned them. It owns placement only, never gameplay logic.
extends Node


## Parents a Node3D to the active level (falling back to the scene root) so it
## survives the death or removal of its spawner. Returns the added node.
func spawn_world_entity(node: Node3D) -> Node3D:
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(node)
	return node


func spawn_damage_number(source: Node3D, damage: float) -> void:
	if not is_instance_valid(source):
		return
	var damage_number: DamageNumber = (GlobalVars.damage_number_scene as PackedScene).instantiate() as DamageNumber
	add_child(damage_number)
	damage_number.set_damage_text(damage)
	damage_number.target_position = source.global_position
