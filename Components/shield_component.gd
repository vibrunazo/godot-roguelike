## A shield that stops hits arriving from the front. Any hit whose origin lies
## within block_arc degrees of the facing node's forward (+Z, the way
## Character turns its mesh_mount) is blocked outright: no damage, knockback,
## stun or hit effects, only the block feedback here. Attacks ask through
## Hurtbox.is_blocked_from() (AttackComponent.deal_damage_to() does for every
## melee, projectile and area hit). Wire it to the character's Hurtbox
## (Hurtbox.shield). enabled can be keyed by animations or switched by
## abilities to lower the shield for a while.
class_name ShieldComponent
extends Node

## Emitted for every hit the shield stopped, with the damage it would have
## dealt and where the hit came from.
signal blocked(damage: float, origin: Vector3)

## Node whose +Z is the shield's front (the character's mesh_mount).
@export var facing: Node3D
## Total arc in degrees, centered on the front, inside which hits are blocked
## (180.0 = the whole front half, 360.0 = everything).
@export_range(0.0, 360.0, 1.0) var block_arc: float = 180.0
## Whether the shield is up. Off, every hit lands.
@export var enabled: bool = true
## Played on each block (a clang).
@export var block_audio: AudioStreamPlayer3D
## Text floated over the character on a block (empty shows none).
@export var block_text: String = "Blocked"
## Height above the facing node's origin where block_text floats.
@export var block_text_height: float = 1.8


func _ready() -> void:
	if facing == null:
		push_error("%s: facing is not set." % name)


## Whether a hit coming from origin on a target standing at target_position
## is blocked: the shield is up and the origin lies inside the front arc.
## Hits without a known origin (Hurtbox.NO_HIT_ORIGIN) are never blocked.
func blocks_hit_from(origin: Vector3, target_position: Vector3) -> bool:
	if not enabled or facing == null or origin == Hurtbox.NO_HIT_ORIGIN:
		return false
	var to_origin: Vector3 = origin - target_position
	to_origin.y = 0.0
	var front: Vector3 = facing.global_basis.z
	front.y = 0.0
	if to_origin.is_zero_approx() or front.is_zero_approx():
		return false
	var angle: float = rad_to_deg(front.normalized().angle_to(to_origin.normalized()))
	return angle <= block_arc * 0.5


## Shows and sounds a block (the floating text and block_audio) and reports it.
func report_block(damage: float, origin: Vector3) -> void:
	if block_audio != null:
		block_audio.play()
	if not block_text.is_empty() and facing != null:
		VfxManager.spawn_floating_text(facing.global_position + Vector3.UP * block_text_height, block_text)
	blocked.emit(damage, origin)
