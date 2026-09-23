@tool
## Reusable ground-level area-of-effect damage zone.
## Uses a low-profile CylinderShape3D resting on the ground so jumping players
## can leap over it to avoid damage. Provides clear visual indicators including an
## expanding shockwave ring, ground impact circle, and debris particle burst.
class_name GroundDamageArea
extends DamageArea

## Radius in meters of the cylindrical damage zone and ground visuals.
@export var radius: float = 3.0:
	set(value):
		radius = maxf(0.1, value)
		if is_inside_tree():
			_apply_dimensions()

## Height in meters of the cylindrical damage zone.
## Keep short (e.g. 0.4m) so jumping players easily clear the hitbox.
@export var height: float = 0.4:
	set(value):
		height = maxf(0.05, value)
		if is_inside_tree():
			_apply_dimensions()

## Duration in seconds the damage hitbox actively monitors for targets.
## After this expires, the hitbox is turned off while visuals finish animating.
@export var active_duration: float = 0.2

## Total lifetime in seconds before the visual effects finish and the node frees itself.
@export var visual_duration: float = 0.6

## Accent color used for the shockwave ring, ground indicator disc, and particles.
@export var aoe_color: Color = Color(1.0, 0.65, 0.2, 1.0):
	set(value):
		aoe_color = value
		if is_inside_tree():
			_apply_visual_styling()

## Whether to show the expanding shockwave ring.
@export var show_shockwave: bool = true

## Whether to display the circular impact zone decal on the floor.
@export var show_ground_indicator: bool = true

## Whether to emit dust/debris particles on impact.
@export var show_particles: bool = true

@onready var shockwave_mesh: MeshInstance3D = $ShockwaveRing
@onready var ground_indicator: MeshInstance3D = $GroundIndicator
@onready var particles: GPUParticles3D = $GPUParticles3D
@onready var impact_audio: AudioStreamPlayer3D = $ImpactAudio

var _active_timer: SceneTreeTimer = null
var _visual_timer: SceneTreeTimer = null


func _get_shockwave_mesh() -> MeshInstance3D:
	if shockwave_mesh == null and is_inside_tree():
		shockwave_mesh = get_node_or_null("ShockwaveRing") as MeshInstance3D
	return shockwave_mesh


func _get_ground_indicator() -> MeshInstance3D:
	if ground_indicator == null and is_inside_tree():
		ground_indicator = get_node_or_null("GroundIndicator") as MeshInstance3D
	return ground_indicator


func _get_particles() -> GPUParticles3D:
	if particles == null and is_inside_tree():
		particles = get_node_or_null("GPUParticles3D") as GPUParticles3D
	return particles


func _get_impact_audio() -> AudioStreamPlayer3D:
	if impact_audio == null and is_inside_tree():
		impact_audio = get_node_or_null("ImpactAudio") as AudioStreamPlayer3D
	return impact_audio


func _ready() -> void:
	# Ensure shapes and materials are duplicated to avoid cross-instance pollution
	var col: CollisionShape3D = _get_collision_shape()
	if col != null:
		if col.shape == null or not (col.shape is CylinderShape3D):
			col.shape = CylinderShape3D.new()
		else:
			col.shape = col.shape.duplicate()

	_duplicate_visual_materials()
	super._ready()
	_apply_dimensions()
	_apply_visual_styling()

	if Engine.is_editor_hint():
		return

	# Enable hitbox monitoring for the active window. Physics-frame spawns (the
	# common case: state exits, animation callbacks, and passive payloads fired
	# from physics signal dispatch) defer the arming through set_hitbox_active;
	# pre-existing victims are then struck by area_entered on the next physics
	# step instead of the spawn-frame sweep below.
	set_hitbox_active(true, true)

	# Play impact sound if available
	var audio: AudioStreamPlayer3D = _get_impact_audio()
	if audio != null and not audio.playing:
		audio.play()

	# Immediately deal damage to anyone already inside the cylinder on spawn frame
	deal_damage()

	# Run visual animations
	_start_visual_animations()

	# Arm active duration window to disable damage monitoring
	if get_tree() != null:
		_active_timer = get_tree().create_timer(active_duration)
		_active_timer.timeout.connect(_on_active_window_expired)

		# Arm visual duration to queue_free
		_visual_timer = get_tree().create_timer(visual_duration)
		_visual_timer.timeout.connect(expire)


func _duplicate_visual_materials() -> void:
	var sw: MeshInstance3D = _get_shockwave_mesh()
	if sw != null and sw.material_override != null:
		sw.material_override = sw.material_override.duplicate()

	var gi: MeshInstance3D = _get_ground_indicator()
	if gi != null and gi.material_override != null:
		gi.material_override = gi.material_override.duplicate()

	var p: GPUParticles3D = _get_particles()
	if p != null and p.process_material != null:
		p.process_material = p.process_material.duplicate()


## Applies the radius and height to the CylinderShape3D and visual meshes.
func _apply_dimensions() -> void:
	var col: CollisionShape3D = _get_collision_shape()
	if col != null and col.shape is CylinderShape3D:
		var cyl: CylinderShape3D = col.shape as CylinderShape3D
		cyl.radius = radius
		cyl.height = height
		# Position center at half-height so base of cylinder rests on local ground (y=0)
		col.position = Vector3(0.0, height * 0.5, 0.0)

	var gi: MeshInstance3D = _get_ground_indicator()
	if gi != null:
		gi.visible = show_ground_indicator
		gi.scale = Vector3(radius, 1.0, radius)

	var p: GPUParticles3D = _get_particles()
	if p != null and p.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = p.process_material as ParticleProcessMaterial
		# emission_ring_radius scales with AOE radius
		mat.emission_ring_radius = radius * 0.75
		mat.emission_ring_inner_radius = radius * 0.25


## Applies color tinting to materials.
func _apply_visual_styling() -> void:
	var sw: MeshInstance3D = _get_shockwave_mesh()
	if sw != null and sw.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = sw.material_override as StandardMaterial3D
		mat.albedo_color = aoe_color
		mat.emission = aoe_color

	var gi: MeshInstance3D = _get_ground_indicator()
	if gi != null and gi.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = gi.material_override as StandardMaterial3D
		var disc_color: Color = aoe_color
		disc_color.a = 0.35
		mat.albedo_color = disc_color
		mat.emission = aoe_color

	var p: GPUParticles3D = _get_particles()
	if p != null and p.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = p.process_material as ParticleProcessMaterial
		mat.color = aoe_color


## Starts Tween animations for shockwave expansion and indicator fadeout.
func _start_visual_animations() -> void:
	if not is_inside_tree():
		return

	var sw: MeshInstance3D = _get_shockwave_mesh()
	if sw != null and show_shockwave:
		sw.visible = true
		sw.scale = Vector3(0.1, 1.0, 0.1)
		var sw_mat: StandardMaterial3D = sw.material_override as StandardMaterial3D

		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(sw, "scale", Vector3(radius, 1.0, radius), visual_duration * 0.75)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		if sw_mat != null:
			var start_col: Color = aoe_color
			start_col.a = 1.0
			var end_col: Color = aoe_color
			end_col.a = 0.0
			sw_mat.albedo_color = start_col
			tween.tween_property(sw_mat, "albedo_color", end_col, visual_duration)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif sw != null:
		sw.visible = false

	var gi: MeshInstance3D = _get_ground_indicator()
	if gi != null and show_ground_indicator:
		gi.visible = true
		var gi_mat: StandardMaterial3D = gi.material_override as StandardMaterial3D
		if gi_mat != null:
			var start_col: Color = aoe_color
			start_col.a = 0.35
			var end_col: Color = aoe_color
			end_col.a = 0.0
			gi_mat.albedo_color = start_col
			var fade_tween: Tween = create_tween()
			fade_tween.tween_property(gi_mat, "albedo_color", end_col, visual_duration)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif gi != null:
		gi.visible = false

	var p: GPUParticles3D = _get_particles()
	if p != null and show_particles:
		p.emitting = true
	elif p != null:
		p.emitting = false


## Shuts down hitbox monitoring once active damage window has concluded.
func _on_active_window_expired() -> void:
	var hitbox: Area3D = _get_damage_hitbox()
	if hitbox != null:
		hitbox.set_deferred("monitoring", false)
		hitbox.set_deferred("monitorable", false)


## Static helper to spawn a GroundDamageArea with configurable parameters into the world.
static func spawn_ground_aoe(
	tree_node: Node,
	pos: Vector3,
	aoe_radius: float = 3.0,
	aoe_height: float = 0.4,
	aoe_damage: float = 25.0,
	aoe_knockback: float = 35.0,
	caster: Character = null,
	color: Color = Color(1.0, 0.65, 0.2, 1.0)
) -> GroundDamageArea:
	var scene: PackedScene = load("res://Hazards/ground_damage_aoe.tscn") as PackedScene
	if scene == null:
		return null
	var instance: GroundDamageArea = scene.instantiate() as GroundDamageArea
	if instance == null:
		return null
	instance.radius = aoe_radius
	instance.height = aoe_height
	instance.damage = aoe_damage
	instance.knockback_force = aoe_knockback
	instance.aoe_color = color
	instance.position = pos
	if caster != null:
		instance.set_wielder(caster)
	VfxManager.spawn_world_entity(instance)
	return instance
