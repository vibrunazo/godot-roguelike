extends BoneAttachment3D
class_name WeaponSlot

signal ranged_attack
signal slash
enum mode {NONE, SLASH, STAB}

## Area3D hitbox this slot switches on and off (its AttackComponent deals the hits).
@export var hitbox: Area3D
## Which trail VFX is showing (keyed by attack animations: SLASH or STAB, NONE otherwise).
@export var attack_mode: mode = mode.NONE
## Slash-trail shader sweep (keyed by attack animations, 1.0 -> 0.0 -> 1.0).
@export var vfx_threshold: float = 0.0
## The hit window: animations key it on at the strike apex and off after it.
## Turning it on emits slash and switches the hitbox monitoring on.
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
