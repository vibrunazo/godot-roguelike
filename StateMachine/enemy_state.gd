## Base class for enemy-specific physical states.
class_name EnemyState
extends CharacterState


## Points the character's visual mesh toward the specified target in world space.
func look_at_target(target: Vector3) -> void:
	if character != null:
		character.look_at_target(target)
