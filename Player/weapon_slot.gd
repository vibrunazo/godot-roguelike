extends BoneAttachment3D
class_name WeaponSlot

signal ranged_attack
signal slash
enum mode {NONE, SLASH, STAB}

@export var hitbox: Area3D
@export var attack_mode: mode = mode.NONE
@export var vfx_threshold: float = 0.0
@export var enabled: bool = false:
	set(value):
		if enabled == false and value == true:
			slash.emit()
		enabled = value
		if hitbox:
			# Direct writes keep animation-driven hit windows frame-accurate,
			# but Area3D properties are locked during the physics step (e.g.
			# cancel_movement_and_abilities running from an exit portal
			# body_entered during a scene transition): defer there, as the
			# engine error suggests.
			if Engine.is_in_physics_frame():
				hitbox.set_deferred("monitoring", enabled)
				hitbox.set_deferred("monitorable", enabled)
			else:
				hitbox.monitoring = enabled
				hitbox.monitorable = enabled

## Backward-compatible alias for hitbox
var shapecast: Area3D:
	get:
		return hitbox
	set(val):
		hitbox = val


func _ready() -> void:
	if hitbox:
		if Engine.is_in_physics_frame():
			hitbox.set_deferred("monitoring", enabled)
			hitbox.set_deferred("monitorable", enabled)
		else:
			hitbox.monitoring = enabled
			hitbox.monitorable = enabled
