class_name TestUtils
extends RefCounted

## Clears the character's auto-aim lock and holds a facing snapshot (mesh-forward)
## while physics ticks. Level enemies wander into auto-aim range, so tests that
## need deterministic jump/dash routing call this before pressing the jump
## button: no lock means the button always commands a dash, while the facing
## snapshot keeps stationary dash directions stable regardless of roaming enemies.
static func clear_lock_and_hold_facing(character: Character) -> void:
	var facing: Vector3 = Vector3.FORWARD
	if character.mesh_mount != null:
		facing = character.mesh_mount.global_basis.z.normalized()
	character.current_target = null
	character.move_direction = Vector3.ZERO
	character.face_target = facing


## Finds the first damageable collision object (dummy/enemy) in the level, excluding the player.
static func find_dummy(level: Node, exclude: Node = null) -> CollisionObject3D:
	for child: Node in level.get_children():
		if child == exclude or child.is_in_group("player"):
			continue
		if child is CollisionObject3D and child.has_node("AttributeComponent"):
			return child as CollisionObject3D
	var wave_obj: Node = level.get_node_or_null("WaveObjective")
	if wave_obj:
		for child: Node in wave_obj.get_children():
			if child == exclude or child.is_in_group("player"):
				continue
			if child is CollisionObject3D and child.has_node("AttributeComponent"):
				return child as CollisionObject3D
		if "all_enemies" in wave_obj and not (wave_obj.all_enemies as Array).is_empty():
			var enemy: Character = null
			for cand: Character in (wave_obj.all_enemies as Array):
				if cand != null and (cand.ai_state_machine == null or not cand.ai_state_machine.has_node("AILeapingDodge")):
					enemy = cand
					break
			if enemy == null:
				enemy = wave_obj.all_enemies[0] as Character
			if not enemy.is_inside_tree():
				if wave_obj.has_method("spawn_enemy"):
					wave_obj.spawn_enemy(enemy)
				else:
					wave_obj.add_child(enemy)
			if enemy.ai_state_machine != null:
				enemy.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
			return enemy
	return null

## Finds the first Enemy instance in the level.
static func find_enemy(level: Node) -> Character:
	for child: Node in level.get_children():
		if child.is_in_group("enemy") and child is Character:
			return child as Character
	var wave_obj: Node = level.get_node_or_null("WaveObjective")
	if wave_obj:
		for child: Node in wave_obj.get_children():
			if child.is_in_group("enemy") and child is Character:
				return child as Character
		if "all_enemies" in wave_obj and not (wave_obj.all_enemies as Array).is_empty():
			var enemy: Character = wave_obj.all_enemies[0] as Character
			if not enemy.is_inside_tree():
				if wave_obj.has_method("spawn_enemy"):
					wave_obj.spawn_enemy(enemy)
				else:
					wave_obj.add_child(enemy)
			return enemy
	return null
