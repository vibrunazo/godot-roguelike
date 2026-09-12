@tool
## Continuous floor fire hazard that instantly damages any character upon contact
## and repeatedly damages lingering characters at a safe, non-stunlocking interval.
## Supports dynamic sizing, removable ground plate, tool-mode editor preview,
## and configurable duration for dynamic enemy spawns (e.g. fire bombs).
class_name FireTrap
extends Node3D

## Size in meters (X = width, Y = depth in 3D space) of the fire field.
@export var trap_size: Vector2 = Vector2(1.0, 1.0):
	set(value):
		trap_size = value
		if is_inside_tree():
			_apply_trap_size()

## Whether to display the charred ground plate under the fire hazard.
## Disable for dynamically spawned fire patches (e.g. fire bombs).
@export var show_ground_mesh: bool = true:
	set(value):
		show_ground_mesh = value
		if is_inside_tree():
			_apply_ground_mesh_state()

## Lifetime in seconds before the fire trap extinguishes and frees itself.
## If <= 0.0, the fire trap persists indefinitely.
@export var duration: float = 0.0

## Fire damage dealt per tick to any character in the area.
@export var damage: float = 5.0:
	set(value):
		damage = value
		var att: AttackComponent = _get_attack_component()
		if att != null:
			att.damage = damage

## Interval in seconds between consecutive damage ticks on lingering characters.
## Default 2.0s ensures enemies aren't permanently locked in EnemyStun.
@export var damage_interval: float = 2.0:
	set(value):
		damage_interval = value
		var att: AttackComponent = _get_attack_component()
		if att != null:
			att.rehit_interval = damage_interval

## Knockback impulse applied upon taking fire damage (default 0).
@export var knockback_force: float = 0.0

## Base particle amount for a 1m x 1m area, captured from GPUParticles3D.amount.
var base_particle_amount: int = 0

var _is_extinguished: bool = false

@onready var damage_hitbox: Area3D = $DamageHitbox
@onready var collision_shape: CollisionShape3D = $DamageHitbox/CollisionShape3D
@onready var attack_component: AttackComponent = $DamageHitbox/AttackComponent
@onready var particles: GPUParticles3D = $GPUParticles3D
@onready var ground_mesh: MeshInstance3D = $GroundMesh
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var life_timer: Timer = $LifeTimer


func _get_damage_hitbox() -> Area3D:
	if damage_hitbox == null and is_inside_tree():
		damage_hitbox = get_node_or_null("DamageHitbox") as Area3D
	return damage_hitbox


func _get_collision_shape() -> CollisionShape3D:
	if collision_shape == null and is_inside_tree():
		collision_shape = get_node_or_null("DamageHitbox/CollisionShape3D") as CollisionShape3D
	return collision_shape


func _get_attack_component() -> AttackComponent:
	if attack_component == null and is_inside_tree():
		attack_component = get_node_or_null("DamageHitbox/AttackComponent") as AttackComponent
	return attack_component


func _get_particles() -> GPUParticles3D:
	if particles == null and is_inside_tree():
		particles = get_node_or_null("GPUParticles3D") as GPUParticles3D
	return particles


func _get_ground_mesh() -> MeshInstance3D:
	if ground_mesh == null and is_inside_tree():
		ground_mesh = get_node_or_null("GroundMesh") as MeshInstance3D
	return ground_mesh


func _get_audio_player() -> AudioStreamPlayer3D:
	if audio_player == null and is_inside_tree():
		audio_player = get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	return audio_player


func _get_life_timer() -> Timer:
	if life_timer == null and is_inside_tree():
		life_timer = get_node_or_null("LifeTimer") as Timer
	return life_timer


func _ready() -> void:
	var col: CollisionShape3D = _get_collision_shape()
	if col != null and col.shape != null:
		col.shape = col.shape.duplicate()

	var gm: MeshInstance3D = _get_ground_mesh()
	if gm != null:
		if show_ground_mesh:
			gm.visible = true
			if gm.mesh != null:
				gm.mesh = gm.mesh.duplicate()
		else:
			gm.visible = false

	var p: GPUParticles3D = _get_particles()
	if p != null:
		if p.process_material != null:
			p.process_material = p.process_material.duplicate()
		if base_particle_amount <= 0:
			base_particle_amount = p.amount

	_apply_trap_size()

	# In editor hint mode, avoid gameplay timers, audio autoplay, or damage processing
	if Engine.is_editor_hint():
		var audio: AudioStreamPlayer3D = _get_audio_player()
		if audio != null:
			audio.autoplay = false
			audio.stop()
		return

	var att: AttackComponent = _get_attack_component()
	if att != null:
		att.damage = damage
		att.rehit_interval = damage_interval
		att.knockback = Vector3(0.0, knockback_force, 0.0)

	if duration > 0.0:
		var timer: Timer = _get_life_timer()
		if timer != null:
			timer.wait_time = duration
			timer.timeout.connect(extinguish)
			timer.start()


## Dynamically scales the collision hitbox, ground plate, and particle emission volume.
func set_trap_size(new_size: Vector2) -> void:
	trap_size = new_size
	_apply_trap_size()


func _apply_ground_mesh_state() -> void:
	var gm: MeshInstance3D = _get_ground_mesh()
	if gm == null:
		return

	gm.visible = show_ground_mesh
	if not show_ground_mesh:
		return

	if gm.mesh is BoxMesh:
		(gm.mesh as BoxMesh).size = Vector3(trap_size.x, 0.02, trap_size.y)


func _apply_trap_size() -> void:
	var col: CollisionShape3D = _get_collision_shape()
	if col != null and col.shape is BoxShape3D:
		(col.shape as BoxShape3D).size = Vector3(trap_size.x, 1.0, trap_size.y)

	_apply_ground_mesh_state()

	var p: GPUParticles3D = _get_particles()
	if p != null:
		if base_particle_amount <= 0:
			base_particle_amount = p.amount
		if p.process_material is ParticleProcessMaterial:
			var mat: ParticleProcessMaterial = p.process_material as ParticleProcessMaterial
			# emission_box_extents are half-extents
			mat.emission_box_extents = Vector3(trap_size.x * 0.42, 0.05, trap_size.y * 0.42)
		var area: float = trap_size.x * trap_size.y
		p.amount = maxi(1, int(round(float(base_particle_amount) * area)))


## Extinguishes the fire trap, turning off damage and fading out VFX/audio.
func extinguish() -> void:
	if _is_extinguished:
		return
	_is_extinguished = true

	var hitbox: Area3D = _get_damage_hitbox()
	if hitbox != null:
		hitbox.set_deferred("monitoring", false)
		hitbox.set_deferred("monitorable", false)

	var p: GPUParticles3D = _get_particles()
	if p != null:
		p.emitting = false

	var audio: AudioStreamPlayer3D = _get_audio_player()
	if audio != null and audio.playing:
		if is_inside_tree():
			var tween: Tween = create_tween()
			tween.tween_property(audio, "volume_db", -40.0, 0.4)
			tween.tween_callback(audio.stop)
		else:
			audio.stop()

	if is_inside_tree() and get_tree() != null:
		var free_timer: SceneTreeTimer = get_tree().create_timer(0.8)
		free_timer.timeout.connect(queue_free)
	else:
		queue_free()


func is_extinguished() -> bool:
	return _is_extinguished
