## Damage entry point for one character. Owns no health values: the health pool
## and the max_health stat live in the sibling AttributeComponent, which is the
## single home for all health reads and writes. This component keeps the combat
## verb (take_damage with damage numbers and hit audio) plus the
## health_changed/defeat signals that Character, Hurtbox, and HealthBar
## subscribe to. A wired AttributeComponent is required.
class_name HealthComponent
extends Node

signal health_changed(value: float)
signal defeat()

## Audio player played when damage is taken.
@export var hit_audio: AudioStreamPlayer3D
## Sibling AttributeComponent holding the health pool and max_health stat.
## Required; falls back to a "../AttributeComponent" sibling lookup when unset.
@export var attribute_component: AttributeComponent

func _ready() -> void:
	_resolve_attributes()
	if attribute_component == null or not is_instance_valid(attribute_component):
		push_error("HealthComponent on '%s' has no AttributeComponent; damage will be ignored." % _owner_name())
		return
	if not attribute_component.attribute_changed.is_connected(_on_attribute_changed):
		attribute_component.attribute_changed.connect(_on_attribute_changed)
	if not attribute_component.defeat.is_connected(_on_attribute_defeat):
		attribute_component.defeat.connect(_on_attribute_defeat)


## Applies damage to the attribute health pool, spawning a damage number and
## playing hit audio. Defeat is emitted through the attribute signal when the
## pool reaches zero. Calls without a wired AttributeComponent are dropped.
func take_damage(damage_in: float) -> void:
	if attribute_component == null or not is_instance_valid(attribute_component):
		_resolve_attributes()
	if attribute_component == null or not is_instance_valid(attribute_component):
		push_error("HealthComponent on '%s' cannot take damage without an AttributeComponent." % _owner_name())
		return
	attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, damage_in)
	var parent: Node = get_parent()
	if parent is Node3D:
		VfxManager.spawn_damage_number(parent as Node3D, damage_in)
	if hit_audio: hit_audio.play()


## Falls back to the "../AttributeComponent" sibling (then any sibling of that
## class, so renamed nodes still resolve) when the export is unset.
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


## Display name of the owning node for error messages.
func _owner_name() -> String:
	var parent: Node = get_parent()
	if parent != null:
		return parent.name
	return name


## Forwards pool and max-health attribute changes as legacy health_changed.
func _on_attribute_changed(attribute_name: StringName, _value: float) -> void:
	if attribute_component == null or not is_instance_valid(attribute_component):
		return
	if attribute_name == AttributeComponent.POOL_HEALTH or attribute_name == AttributeComponent.STAT_MAX_HEALTH:
		health_changed.emit(attribute_component.get_current(AttributeComponent.POOL_HEALTH))


## Forwards the attribute health depletion as the defeat signal.
func _on_attribute_defeat() -> void:
	defeat.emit()
