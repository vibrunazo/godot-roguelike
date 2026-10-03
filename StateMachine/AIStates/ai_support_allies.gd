## AI state that casts a support ability (body_state, e.g. an ability slot
## whose payload buffs or heals allies) when at least min_allies living allies
## other than the character stand within ally_range and the ability can be
## cast, interrupting whatever the mind was doing (see AIAttackBase), then
## moves to next_state. It only triggers in combat (the mind has a target),
## so supporters never waste the ability on idle allies.
class_name AISupportAllies
extends AIAttackBase

## Distance in meters within which allies count (match the ability's reach).
@export var ally_range: float = 6.0
## Allies (other than the character) that must be within ally_range.
@export var min_allies: int = 1
## AI state to move to once the ability has been cast (or was refused).
@export var next_state: AIState


func evaluate_trigger(_delta: float) -> bool:
	if character == null or not character.is_inside_tree() or not character.is_alive() or ai_state_machine == null:
		return false
	if body_state == null or not body_state.can_activate():
		return false
	if ai_state_machine.get_target() == null:
		return false
	if count_allies_in_range() < min_allies:
		return false
	if not character.can_accept_order(body_state):
		return false
	ai_state_machine.request_state(name)
	return true


## Living allies other than the character within ally_range.
func count_allies_in_range() -> int:
	var own_group: String = "enemy" if character.is_enemy() else "player"
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(own_group):
		var ally: Character = node as Character
		if ally == null or ally == character or not ally.is_alive():
			continue
		if ally.global_position.distance_squared_to(character.global_position) <= ally_range * ally_range:
			count += 1
	return count


func _next_state() -> AIState:
	return next_state
