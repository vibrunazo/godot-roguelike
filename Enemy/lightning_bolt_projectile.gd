## Fast electric bolt projectile cast by the Enemy Thunder Mage.
class_name LightningBoltProjectile
extends EnemyProjectile

## Hit impact effect scene spawned when striking targets or obstacles.
@export var hit_effect_scene: PackedScene


func _init() -> void:
	speed = 14.0
	damage = 15.0
	knockback = 12.0


func _ready() -> void:
	super._ready()
	if hit_effect_scene == null:
		push_error("%s: hit_effect_scene is not set." % name)


## Spawns the electric burst hit effect upon collision.
func hit_effect() -> void:
	if hit_effect_scene != null:
		var hit: Node3D = hit_effect_scene.instantiate() as Node3D
		VfxManager.spawn_world_entity(hit)
		hit.global_position = global_position
	else:
		super.hit_effect()
