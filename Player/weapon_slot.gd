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
		hitbox.monitoring = enabled
		hitbox.monitorable = enabled
