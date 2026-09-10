## World-space visual effects service, registered as the `VfxManager` autoload
## (script) in `project.godot`. Access from anywhere via `VfxManager`, e.g.
## `VfxManager.spawn_damage_number(source, 10.0)`.
##
## Unique responsibilities:
## - Floating combat text (`spawn_damage_number`, parented to itself as screen-space UI).
## - Player-only target reticle (`target_reticle`, a persistent TargetReticle
##   following the player's `current_target`; enemies never spawn one).
## - World-space spawning (`spawn_world_entity`): parents gameplay entities and
##   effects (projectiles, impact VFX) to the active level so they outlive the
##   actor that spawned them. It owns placement only, never gameplay logic.
extends Node


## Persistent player-only target reticle. Spawned once for the player
## character; enemies never spawn a reticle and run no reticle math at all.
var target_reticle: TargetReticle = null


func _ready() -> void:
	_ensure_reticle()


func _physics_process(_delta: float) -> void:
	_update_reticle()


## Spawns the single player reticle instance when the registered scene exists.
func _ensure_reticle() -> void:
	if target_reticle != null and is_instance_valid(target_reticle):
		return
	if GlobalVars.target_reticle_scene == null:
		return
	target_reticle = (GlobalVars.target_reticle_scene as PackedScene).instantiate() as TargetReticle
	add_child(target_reticle)


## Points the player reticle at the player character's current_target.
## Only the player is ever looked up here, so enemies pay zero reticle cost.
func _update_reticle() -> void:
	if target_reticle == null or not is_instance_valid(target_reticle):
		return
	var player: Character = get_tree().get_first_node_in_group("player") as Character
	var next_target: Node3D = null
	# Guarded lookup: assigning a freed target to the typed slot errors, and
	# the owner's own tick may not have cleared it yet this frame.
	if player != null and player.current_target != null and is_instance_valid(player.current_target):
		next_target = player.current_target
	target_reticle.target = next_target


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
