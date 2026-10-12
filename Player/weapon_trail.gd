## A ribbon trailing a weapon's blade through its strikes. While the weapon
## slot's hit window is open (WeaponSlot.enabled) it records where the blade
## runs, from blade_base to blade_tip, every physics tick, and draws the last
## lifetime seconds of that path in world space, smoothed between records.
## Its material reads the ribbon's UVs: x is the age (0 at the blade now, 1
## where the trail ends), y runs from the base (0) to the tip (1). It follows
## each animation as it is, so one trail serves every attack of its weapon:
## a swing leaves an arc, a thrust a streak. Optional sparks emit and an
## optional light flares while it draws. Purely visual: the slot's hitbox
## deals the hits.
class_name WeaponTrail
extends MeshInstance3D

## Weapon slot whose hit window the trail draws during.
@export var weapon_slot: WeaponSlot
## Marker at the inner end of the trailed part of the blade (by the hilt).
@export var blade_base: Node3D
## Marker at the blade tip.
@export var blade_tip: Node3D
## Seconds a recorded blade position stays in the trail.
@export var lifetime: float = 0.22
## Ribbon segments drawn between two recorded positions, so fast swings
## curve smoothly instead of in straight chunks.
@export_range(1, 8) var subdivisions: int = 4
## Particles emitting while the trail draws (null for none).
@export var sparks: GPUParticles3D
## Light that flares while the trail draws (null for none).
@export var flare_light: OmniLight3D
## Energy flare_light flares to while the trail draws.
@export var flare_energy: float = 6.0
## Energy per second flare_light rises or falls at.
@export var flare_rate: float = 60.0

var _mesh: ImmediateMesh
## Recorded blade base positions, oldest first; w holds the record's time.
var _bases: Array[Vector4] = []
## Recorded blade tip positions, matching _bases.
var _tips: Array[Vector3] = []
var _clock: float = 0.0
var _rest_energy: float = 0.0


func _ready() -> void:
	if weapon_slot == null:
		push_error("%s: weapon_slot is not set." % name)
	if blade_base == null or blade_tip == null:
		push_error("%s: blade_base and blade_tip must be set." % name)
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	top_level = true
	global_transform = Transform3D.IDENTITY
	if flare_light != null:
		_rest_energy = flare_light.light_energy


func _physics_process(delta: float) -> void:
	_clock += delta
	var drawing: bool = is_drawing()
	if drawing and blade_base != null and blade_tip != null:
		var base: Vector3 = blade_base.global_position
		_bases.append(Vector4(base.x, base.y, base.z, _clock))
		_tips.append(blade_tip.global_position)
	while not _bases.is_empty() and _clock - _bases[0].w > lifetime:
		_bases.pop_front()
		_tips.pop_front()
	_draw_ribbon()
	if sparks != null:
		sparks.emitting = drawing
	if flare_light != null:
		var target: float = flare_energy if drawing else _rest_energy
		flare_light.light_energy = move_toward(flare_light.light_energy, target, flare_rate * delta)


## Whether the trail records the blade now: the slot's hit window is open.
func is_drawing() -> bool:
	return weapon_slot != null and weapon_slot.enabled and is_visible_in_tree()


## Whether any part of the trail is still on screen.
func has_trail() -> bool:
	return _bases.size() >= 2


## Rebuilds the ribbon: a triangle strip through every recorded position,
## with subdivisions cubic-interpolated points between neighbors. Idle (no
## trail and nothing drawn) it does nothing.
func _draw_ribbon() -> void:
	if _mesh.get_surface_count() > 0:
		_mesh.clear_surfaces()
	if not has_trail():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var last: int = _bases.size() - 1
	for index: int in last:
		var steps: int = subdivisions if index < last - 1 else subdivisions + 1
		for step: int in steps:
			_add_ribbon_point(index, float(step) / float(subdivisions))
	_mesh.surface_end()


## Adds the ribbon's base and tip vertices weight of the way from record
## index to the next one.
func _add_ribbon_point(index: int, weight: float) -> void:
	var before: int = maxi(index - 1, 0)
	var after: int = mini(index + 2, _bases.size() - 1)
	var from: Vector4 = _bases[index]
	var to: Vector4 = _bases[index + 1]
	var base: Vector3 = _xyz(from).cubic_interpolate(_xyz(to), _xyz(_bases[before]), _xyz(_bases[after]), weight)
	var tip: Vector3 = _tips[index].cubic_interpolate(_tips[index + 1], _tips[before], _tips[after], weight)
	var age: float = clampf((_clock - lerpf(from.w, to.w, weight)) / maxf(lifetime, 0.001), 0.0, 1.0)
	_mesh.surface_set_uv(Vector2(age, 0.0))
	_mesh.surface_add_vertex(base)
	_mesh.surface_set_uv(Vector2(age, 1.0))
	_mesh.surface_add_vertex(tip)


func _xyz(record: Vector4) -> Vector3:
	return Vector3(record.x, record.y, record.z)
