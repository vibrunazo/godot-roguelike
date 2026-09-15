## Damage entry point for one character. Keeps its historic hurtbox-facing
## duties (damage intake, damage numbers, hit audio, health_changed/defeat
## signals) while delegating number storage to a sibling AttributeComponent
## when one is wired: health pools and the max_health stat then live in the
## attribute store and this component acts as a thin forwarding adapter.
## Without a sibling component it falls back to local storage, so older scenes
## and test dummies behave exactly as before.
class_name HealthComponent
extends Node

signal health_changed(value: float)
signal defeat()

## Audio player played when damage is taken.
@export var hit_audio: AudioStreamPlayer3D
## Sibling AttributeComponent backing health numbers when present. Falls back
## to a "../AttributeComponent" sibling lookup when left unassigned.
@export var attribute_component: AttributeComponent
var is_ready: bool = false

var _max_health_fallback: float = 100.0
var _current_health_fallback: float = 100.0

## Maximum health value of this component. Forwards to the max_health stat
## base when an AttributeComponent is wired.
var max_health: float:
	get:
		if _use_attributes():
			return attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH)
		return _max_health_fallback
	set(value):
		if _use_attributes():
			attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, value)
		else:
			_max_health_fallback = value
			if is_ready:
				health_changed.emit(_current_health_fallback)

## Current health value of this component. Forwards to the health pool when an
## AttributeComponent is wired. Direct writes clamp but never emit defeat;
## only take_damage() can turn damage into a defeat.
var current_health: float:
	get:
		if _use_attributes():
			return attribute_component.get_current(AttributeComponent.POOL_HEALTH)
		return _current_health_fallback
	set(value):
		if _use_attributes():
			attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, value)
		else:
			_current_health_fallback = value
			if is_ready:
				health_changed.emit(_current_health_fallback)

func _ready() -> void:
	_resolve_attributes()
	if _use_attributes():
		if not attribute_component.attribute_changed.is_connected(_on_attribute_changed):
			attribute_component.attribute_changed.connect(_on_attribute_changed)
		if not attribute_component.defeat.is_connected(_on_attribute_defeat):
			attribute_component.defeat.connect(_on_attribute_defeat)
	else:
		_current_health_fallback = _max_health_fallback
	is_ready = true

## Applies damage through the attribute health pool when wired, preserving the
## legacy setter-emit behavior (every call emits, including zero deltas).
func take_damage(damage_in: float) -> void:
	if _use_attributes():
		attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, damage_in)
	else:
		current_health -= damage_in
	var parent: Node = get_parent()
	if parent is Node3D:
		VfxManager.spawn_damage_number(parent as Node3D, damage_in)
	if hit_audio: hit_audio.play()
	if not _use_attributes() and _current_health_fallback <= 0.0: defeat.emit()


## Returns true when a sibling AttributeComponent is available for delegation.
func _use_attributes() -> bool:
	if attribute_component == null or not is_instance_valid(attribute_component):
		_resolve_attributes()
	return attribute_component != null and is_instance_valid(attribute_component)


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


## Forwards pool and max-health attribute changes as legacy health_changed.
func _on_attribute_changed(attribute_name: StringName, _value: float) -> void:
	if attribute_name == AttributeComponent.POOL_HEALTH or attribute_name == AttributeComponent.STAT_MAX_HEALTH:
		health_changed.emit(current_health)


## Forwards the attribute health depletion as the legacy defeat signal.
func _on_attribute_defeat() -> void:
	defeat.emit()
