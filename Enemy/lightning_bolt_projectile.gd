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
		if GlobalVars != null and "lightning_hit_scene" in GlobalVars and GlobalVars.lightning_hit_scene != null:
			hit_effect_scene = GlobalVars.lightning_hit_scene
		else:
			hit_effect_scene = load("res://Enemy/lightning_hit.tscn") as PackedScene


## Spawns the electric burst hit effect upon collision.
func hit_effect() -> void:
	var scene: PackedScene = hit_effect_scene
	if scene == null and GlobalVars != null and "lightning_hit_scene" in GlobalVars and GlobalVars.lightning_hit_scene != null:
		scene = GlobalVars.lightning_hit_scene
	if scene == null:
		scene = load("res://Enemy/lightning_hit.tscn") as PackedScene
	
	if scene != null:
		var hit: Node3D = scene.instantiate() as Node3D
		VfxManager.spawn_world_entity(hit)
		hit.global_position = global_position
	else:
		super.hit_effect()
