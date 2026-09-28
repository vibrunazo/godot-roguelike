## Lobbed projectile fired in a ballistic arc (see BallisticProjectile) that
## detonates into a FireTrap upon hitting the ground, or damages a hurtbox it
## hits in flight.
class_name FirebombProjectile
extends BallisticProjectile

## Fire trap hazard scene spawned on ground impact.
@export var fire_trap_scene: PackedScene
## Duration in seconds of the spawned fire trap before extinguishing.
@export var trap_duration: float = 10.0
## Size in meters (X = width, Y = depth) of the spawned fire trap.
@export var trap_size: Vector2 = Vector2(2.0, 2.0)
## Damage per tick dealt by the spawned fire trap.
@export var trap_damage: float = 5.0


func _ready() -> void:
	super._ready()
	if fire_trap_scene == null:
		push_error("%s: fire_trap_scene is not set." % name)


## A direct hit damages the hurtbox (knocked back along the flight) and
## leaves no fire.
func _on_direct_hit(hurtbox: Hurtbox) -> void:
	_detonated = true
	_is_hit = true
	if attack_component != null:
		var knock_dir: Vector3 = velocity.normalized()
		if knock_dir.is_zero_approx():
			knock_dir = global_basis.z
		attack_component.deal_damage_to(hurtbox, damage, knock_dir * knockback)
	hit_effect()
	queue_free()


## Leaves a fire trap configured from this bomb where it lands.
func _on_landed(ground_position: Vector3) -> void:
	if fire_trap_scene == null:
		return
	var trap: FireTrap = fire_trap_scene.instantiate() as FireTrap
	if trap == null:
		return
	trap.trap_size = trap_size
	trap.show_ground_mesh = false
	trap.duration = trap_duration
	trap.damage = trap_damage
	trap.position = ground_position
	VfxManager.spawn_world_entity(trap)
