## Base state for AI decision states (Mind).
class_name AIState
extends State

## Reference to the owning AIStateMachine.
@export var ai_state_machine: AIStateMachine

## Reference to the Character controlled by the AI.
var character: Character:
	get:
		return ai_state_machine.character if ai_state_machine != null else null


func _ready() -> void:
	if ai_state_machine == null:
		ai_state_machine = get_parent() as AIStateMachine


## Evaluates whether this AI state wants to preemptively interrupt the active state and activate itself.
## Returns true if the state triggered and requested a transition to itself.
func evaluate_trigger(_delta: float) -> bool:
	return false


## True when the character's mount facing falls inside a cone (in degrees,
## centered on the target direction; 360.0 = anywhere, 0.0 = perfect
## alignment only). Shared aim-gate predicate for ordered attacks: callers
## turn the body toward the target at its rotation speed limit first and only
## order once this returns true, so attacks never start while facing away.
func is_facing_within_cone(target: Character, cone_degrees: float) -> bool:
	if cone_degrees >= 360.0:
		return true
	if character == null or character.mesh_mount == null or target == null:
		return false
	var facing: Vector3 = character.mesh_mount.global_transform.basis.z
	facing.y = 0.0
	if facing.is_zero_approx():
		return false
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	if to_target.is_zero_approx():
		return true
	var angle: float = rad_to_deg(acos(clampf(facing.normalized().dot(to_target.normalized()), -1.0, 1.0)))
	# The 0.05-degree hair covers float dust from the final exact step, so a
	# 0.0 cone still opens on true alignment instead of stalling forever.
	return angle <= maxf(cone_degrees, 0.0) * 0.5 + 0.05


## Builds the {"aim": ...} facing intent payload for order_attack so the body
## snapshots the order-time facing and turns toward it at its rotation speed
## limit during the attack. Empty when the target stacks on the body.
func build_aim_order_data(target: Character) -> Dictionary:
	var order_data: Dictionary = {}
	if character == null or target == null:
		return order_data
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	if not to_target.is_zero_approx():
		order_data["aim"] = to_target.normalized()
	return order_data
