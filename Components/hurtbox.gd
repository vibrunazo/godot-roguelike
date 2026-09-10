## Damageable area attached to a character. Registered on a team hurtbox layer
## (layer 7 for players, layer 8 for enemies) so weapon and projectile hitboxes
## detect it instead of the character's movement body. Team split means melee
## hitboxes only ever overlap opposing teams; projectiles mask both layers.
## Attackers call receive_hit(); this component delegates damage to the
## character's HealthComponent and momentum to its KnockbackComponent, so
## attackers never need to know about target internals.
## Future invulnerability frames hook in here (e.g. toggling monitoring or the
## collision shape while keeping movement collision active).
class_name Hurtbox
extends Area3D

## HealthComponent receiving damage from receive_hit().
@export var health_component: HealthComponent
## KnockbackComponent receiving momentum from receive_hit().
@export var knockback_component: KnockbackComponent


## Applies damage and knockback to the owning character.
## Returns true when damage was dealt. Returns false when no HealthComponent is
## wired or the owner is already defeated (current_health <= 0.0), so corpses
## can never be re-hit for extra damage numbers, knockback, or screen shake.
func receive_hit(damage: float, knockback: Vector3) -> bool:
	if health_component == null or not is_instance_valid(health_component):
		return false
	if health_component.current_health <= 0.0:
		return false
	health_component.take_damage(damage)
	if knockback_component != null and is_instance_valid(knockback_component):
		knockback_component.add_knockback(knockback)
	return true
