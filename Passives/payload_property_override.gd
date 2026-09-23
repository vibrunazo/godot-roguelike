## One typed property patch applied to a spawned payload before it enters the
## tree, so setters and _ready() observe final values. Lets several shop
## upgrades share one payload scene and tune it per grant (bigger blast, softer
## knockback, hot recolor) without dedicated scene variants. Applied by
## PayloadPassiveAbility in array order, after instantiation and before
## wielder/damage configuration.
class_name PayloadPropertyOverride
extends Resource

## Value kinds matching the target property's type.
enum ValueType {
	FLOAT, ## Apply float_value (also covers int properties).
	BOOL, ## Apply bool_value.
	STRING_NAME, ## Apply string_name_value.
	VECTOR3, ## Apply vector3_value.
	COLOR, ## Apply color_value.
}

## Value kind to apply; must match the target property's type.
@export_enum("FLOAT", "BOOL", "STRING_NAME", "VECTOR3", "COLOR") var value_type: int = ValueType.FLOAT
## Property name on the payload root node (e.g. &"radius", &"knockback_force").
@export var property: StringName = &""
## Value applied when value_type is FLOAT.
@export var float_value: float = 0.0
## Value applied when value_type is BOOL.
@export var bool_value: bool = false
## Value applied when value_type is STRING_NAME.
@export var string_name_value: StringName = &""
## Value applied when value_type is VECTOR3.
@export var vector3_value: Vector3 = Vector3.ZERO
## Value applied when value_type is COLOR.
@export var color_value: Color = Color.WHITE


## Returns the typed field selected by value_type.
func resolve_value() -> Variant:
	match value_type:
		ValueType.BOOL:
			return bool_value
		ValueType.STRING_NAME:
			return string_name_value
		ValueType.VECTOR3:
			return vector3_value
		ValueType.COLOR:
			return color_value
	return float_value


## Applies this override to the target object's named property. Warns loudly
## (and changes nothing) when the property does not exist on the target, so a
## typo can never silently disable a tuning tweak.
func apply_to(target: Object) -> void:
	if target == null or property.is_empty():
		return
	if not _has_property(target):
		push_warning("PayloadPropertyOverride: '%s' has no property '%s'; override skipped." % [target, property])
		return
	target.set(property, resolve_value())


func _has_property(target: Object) -> bool:
	for prop: Dictionary in target.get_property_list():
		if StringName(prop.get("name", "")) == property:
			return true
	return false