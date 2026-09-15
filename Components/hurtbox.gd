## Damageable area attached to a character. Registered on a team hurtbox layer
## (layer 7 for players, layer 8 for enemies) so weapon and projectile hitboxes
## detect it instead of the character's movement body. Team split means melee
## hitboxes only ever overlap opposing teams; projectiles mask both layers.
## Attackers call receive_hit(); this component routes damage through the
## character's HealthComponent verb and momentum to its KnockbackComponent, so
## attackers never need to know about target internals. Liveness reads come
## from the character's AttributeComponent health pool (the single home for
## health values). Future invulnerability frames hook in here (e.g. toggling
## monitoring or the collision shape while keeping movement collision active).
class_name Hurtbox
extends Area3D

## HealthComponent receiving damage from receive_hit() (verb + defeat signal).
@export var health_component: HealthComponent
## AttributeComponent holding the health pool read by is_alive().
@export var attribute_component: AttributeComponent
## KnockbackComponent receiving momentum from receive_hit().
@export var knockback_component: KnockbackComponent


func _ready() -> void:
	_resolve_attributes()
	if health_component != null and not health_component.defeat.is_connected(_on_defeat):
		health_component.defeat.connect(_on_defeat)


## Returns true if the owning target is alive and eligible to receive hits.
func is_alive() -> bool:
	var parent_node: Node = get_parent()
	if parent_node is Character and not (parent_node as Character).is_alive():
		return false
	if health_component == null or not is_instance_valid(health_component):
		return false
	if attribute_component == null or not is_instance_valid(attribute_component):
		return false
	return attribute_component.is_alive()


## Deactivates the hurtbox so corpses stop participating in collision queries.
func _on_defeat() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	var shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", true)


## Applies damage and knockback to the owning character.
## Returns true when damage was dealt. Returns false when no HealthComponent is
## wired or the owner is already defeated (health pool at zero), so corpses
## can never be re-hit for extra damage numbers, knockback, or screen shake.
func receive_hit(damage: float, knockback: Vector3) -> bool:
	if not is_alive():
		return false
	health_component.take_damage(damage)
	if knockback_component != null and is_instance_valid(knockback_component):
		knockback_component.add_knockback(knockback)
	return true


## Falls back to the "../AttributeComponent" sibling (then any sibling of that
## class) when the export is unset.
func _resolve_attributes() -> void:
	if attribute_component != null and is_instance_valid(attribute_component):
		return
	attribute_component = get_node_or_null("../AttributeComponent") as AttributeComponent
	if attribute_component != null:
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	for child: Node in parent.get_children():
		if child is AttributeComponent:
			attribute_component = child as AttributeComponent
			break
