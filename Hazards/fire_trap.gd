## Continuous floor fire hazard that instantly damages any character upon contact
## and repeatedly damages lingering characters at a safe, non-stunlocking interval.
## Supports dynamic sizing and configurable duration for dynamic enemy spawns.
class_name FireTrap
extends Node3D

## Size in meters (X = width, Y = depth in 3D space) of the fire field.
@export var trap_size: Vector2 = Vector2(1.0, 1.0):
	set(value):
		trap_size = value
		if is_inside_tree():
			_apply_trap_size()

## Lifetime in seconds before the fire trap extinguishes and frees itself.
## If <= 0.0, the fire trap persists indefinitely.
@export var duration: float = 0.0

## Fire damage dealt per tick to any character in the area.
@export var damage: float = 5.0:
	set(value):
		damage = value
		if attack_component != null:
			attack_component.damage = damage

## Interval in seconds between consecutive damage ticks on lingering characters.
## Default 2.0s ensures enemies aren't permanently locked in EnemyStun.
@export var damage_interval: float = 2.0:
	set(value):
		damage_interval = value
		if attack_component != null:
			attack_component.rehit_interval = damage_interval

## Knockback impulse applied upon taking fire damage (default 0).
@export var knockback_force: float = 0.0

var _is_extinguished: bool = false

@onready var damage_hitbox: Area3D = $DamageHitbox
@onready var collision_shape: CollisionShape3D = $DamageHitbox/CollisionShape3D
@onready var attack_component: AttackComponent = $DamageHitbox/AttackComponent
@onready var particles: GPUParticles3D = $GPUParticles3D
@onready var ground_mesh: MeshInstance3D = $GroundMesh
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var life_timer: Timer = $LifeTimer


func _ready() -> void:
	# Duplicate resource instances to prevent shared modifications across instances
	if collision_shape != null and collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
	if ground_mesh != null and ground_mesh.mesh != null:
		ground_mesh.mesh = ground_mesh.mesh.duplicate()
	if particles != null and particles.process_material != null:
		particles.process_material = particles.process_material.duplicate()

	_apply_trap_size()

	if attack_component != null:
		attack_component.damage = damage
		attack_component.rehit_interval = damage_interval
		attack_component.knockback = Vector3(0.0, knockback_force, 0.0)

	if duration > 0.0:
		life_timer.wait_time = duration
		life_timer.timeout.connect(extinguish)
		life_timer.start()


## Dynamically scales the collision hitbox, ground plate, and particle emission volume.
func set_trap_size(new_size: Vector2) -> void:
	trap_size = new_size
	_apply_trap_size()


func _apply_trap_size() -> void:
	if collision_shape != null and collision_shape.shape is BoxShape3D:
		(collision_shape.shape as BoxShape3D).size = Vector3(trap_size.x, 1.0, trap_size.y)

	if ground_mesh != null and ground_mesh.mesh is BoxMesh:
		(ground_mesh.mesh as BoxMesh).size = Vector3(trap_size.x, 0.02, trap_size.y)

	if particles != null and particles.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = particles.process_material as ParticleProcessMaterial
		# emission_box_extents are half-extents
		mat.emission_box_extents = Vector3(trap_size.x * 0.42, 0.05, trap_size.y * 0.42)
		var area: float = trap_size.x * trap_size.y
		particles.amount = maxi(10, int(round(28.0 * area)))


## Extinguishes the fire trap, turning off damage and fading out VFX/audio.
func extinguish() -> void:
	if _is_extinguished:
		return
	_is_extinguished = true

	if damage_hitbox != null:
		damage_hitbox.set_deferred("monitoring", false)
		damage_hitbox.set_deferred("monitorable", false)

	if particles != null:
		particles.emitting = false

	if audio_player != null and audio_player.playing:
		var tween: Tween = create_tween()
		tween.tween_property(audio_player, "volume_db", -40.0, 0.4)
		tween.tween_callback(audio_player.stop)

	var free_timer: SceneTreeTimer = get_tree().create_timer(0.8)
	free_timer.timeout.connect(queue_free)


func is_extinguished() -> bool:
	return _is_extinguished
