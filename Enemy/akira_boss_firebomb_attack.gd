## Ranged firebomb cast used by the Akira boss.
## Plays a brute punch/throw animation, then lobs an oversized firebomb
## through the boss ProjectileSpawnerComponent toward the current target.
## Timing mirrors FirebomberEnemy: the projectile arcs ballistically and
## spawns a larger fire trap on ground impact.
class_name AkiraBossFirebombAttack
extends CharacterAttack

## Spawner that instantiates the oversized Akira firebomb projectile.
@export var projectile_spawner: ProjectileSpawnerComponent
## Delay in seconds after entering before spawning, synced to the throw apex.
@export var spawn_delay: float = 0.45


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	super.enter(_previous_state_path, _data)
	if projectile_spawner == null and character != null:
		projectile_spawner = character.get_node_or_null("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var timer: SceneTreeTimer = tree.create_timer(maxf(spawn_delay, 0.0))
	timer.timeout.connect(_spawn_firebomb)


## Spawns the firebomb only while still inside this attack and alive.
func _spawn_firebomb() -> void:
	if character == null or not is_instance_valid(character):
		return
	if not character.is_alive():
		return
	if character.state_machine == null or character.state_machine.state != self:
		return
	if projectile_spawner == null or not is_instance_valid(projectile_spawner):
		return
	if not projectile_spawner.is_inside_tree():
		return
	projectile_spawner.spawn_projectile()
