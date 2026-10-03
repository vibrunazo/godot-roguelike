## Slowed status VFX: a ring of dots circling the target's legs like a
## loading spinner (the dots shrink and dim toward the tail). Instanced on a
## character by StatusVisualsComponent for as long as the slow lasts. On a
## Character it holds itself leg_height above the body's feet (whatever the
## body's origin height) and widens to clear its collision shape; elsewhere it
## stays where it was put. The ring stays level whatever its parent does.
## Purely visual (render clock).
class_name StatusLag
extends Node3D

## Number of dots in the ring.
@export var dot_count: int = 8
## Radius of the largest (leading) dot, in meters.
@export var dot_radius: float = 0.09
## Size of the last dot relative to the leading one.
@export_range(0.0, 1.0) var tail_scale: float = 0.35
## Color of the leading dot; the tail fades toward tail_color.
@export var head_color: Color = Color(0.55, 0.95, 1.0)
## Color of the last dot.
@export var tail_color: Color = Color(0.15, 0.35, 0.9)
## Glow of the dots, so they read on dark floors.
@export var emission_energy: float = 1.5
## Ring radius when the parent has no collision shape to measure, in meters.
@export var default_radius: float = 0.5
## Gap kept between the body's collision radius and the ring, in meters.
@export var body_margin: float = 0.15
## Height of the ring above the body's feet, in meters.
@export var leg_height: float = 0.3
## Turns per second (positive spins clockwise seen from above).
@export var spins_per_second: float = 0.8

var _angle: float = 0.0
## The Character this ring circles (null when it is on something else).
var _body: Character = null


func _ready() -> void:
	var node: Node = get_parent()
	while node != null and not (node is Character):
		node = node.get_parent()
	_body = node as Character
	var radius: float = _ring_radius()
	for index: int in maxi(dot_count, 1):
		var weight: float = float(index) / float(maxi(dot_count - 1, 1))
		var dot: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		var size: float = dot_radius * lerpf(1.0, tail_scale, weight)
		mesh.radius = size
		mesh.height = size * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		dot.mesh = mesh
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.material_override = _material(head_color.lerp(tail_color, weight))
		# The tail trails behind the head along the spin.
		var angle: float = TAU * float(index) / float(maxi(dot_count, 1))
		dot.position = Vector3(sin(angle), 0.0, cos(angle)) * radius
		add_child(dot)


func _process(delta: float) -> void:
	_angle = wrapf(_angle - TAU * spins_per_second * delta, 0.0, TAU)
	global_basis = Basis(Vector3.UP, _angle)
	if _body != null and is_instance_valid(_body):
		global_position = _body.get_feet_position() + Vector3.UP * leg_height


## The collision radius of the Character this ring circles plus body_margin,
## or default_radius when there is none to measure.
func _ring_radius() -> float:
	if _body == null or _body.collision_shape_3d == null:
		return default_radius
	var shape: Shape3D = _body.collision_shape_3d.shape
	var scale_xz: float = _body.collision_shape_3d.global_basis.get_scale().x
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius * scale_xz + body_margin
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius * scale_xz + body_margin
	if shape is BoxShape3D:
		var box: Vector3 = (shape as BoxShape3D).size
		return maxf(box.x, box.z) * 0.5 * scale_xz + body_margin
	return default_radius


func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	return material
