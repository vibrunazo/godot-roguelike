## Damageable area attached to a character. Registered on a team hurtbox layer
## (layer 7 for players, layer 8 for enemies) so weapon and projectile hitboxes
## detect it instead of the character's movement body. Team split means melee
## hitboxes only ever overlap opposing teams; projectiles mask both layers.
## Attackers call receive_hit(); this component applies damage to the
## character's AttributeComponent health pool and momentum to its
## KnockbackComponent, spawns the damage number, and plays hit audio, so
## attackers never need to know about target internals. Health values live in
## the AttributeComponent alone. Future invulnerability frames hook in here
## (e.g. toggling monitoring or the collision shape while keeping movement
## collision active).
class_name Hurtbox
extends Area3D

## Emitted once per successful receive_hit(), after damage is applied. Marks a
## discrete "was struck" event for hit reactions (stun, damage flash, hurt
## shake). Damage-over-time ticks write to the pool directly and never emit
## this, so reactions fire once per hit instead of every frame of a burn.
signal struck(damage: float)

## Audio player played when damage is taken.
@export var hit_audio: AudioStreamPlayer3D
## AttributeComponent holding the health pool damaged by receive_hit().
@export var attribute_component: AttributeComponent
## KnockbackComponent receiving momentum from receive_hit().
@export var knockback_component: KnockbackComponent


func _ready() -> void:
	_resolve_attributes()
	if attribute_component != null and not attribute_component.defeat.is_connected(_on_defeat):
		attribute_component.defeat.connect(_on_defeat)


## Returns true if the owning target is alive and eligible to receive hits.
func is_alive() -> bool:
	var parent_node: Node = get_parent()
	if parent_node is Character and not (parent_node as Character).is_alive():
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


## Applies damage and knockback to the owning character, spawning a damage
## number and playing hit audio.
## Returns true when damage was dealt. Returns false when no AttributeComponent
## is wired or the owner is already defeated (health pool at zero), so corpses
## can never be re-hit for extra damage numbers, knockback, or screen shake.
func receive_hit(damage: float, knockback: Vector3) -> bool:
	if not is_alive():
		return false
	attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, damage)
	if knockback_component != null and is_instance_valid(knockback_component):
		knockback_component.add_knockback(knockback)
	var parent: Node = get_parent()
	if parent is Node3D:
		VfxManager.spawn_damage_number(parent as Node3D, damage)
	if hit_audio: hit_audio.play()
	struck.emit(damage)
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
