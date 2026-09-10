class_name TestUtils
extends RefCounted

## Finds the first damageable collision object (dummy/enemy) in the level, excluding the player.
static func find_dummy(level: Node, exclude: Node = null) -> CollisionObject3D:
	for child: Node in level.get_children():
		if child == exclude or child.is_in_group("player"):
			continue
		if child is CollisionObject3D and child.has_node("HealthComponent"):
			return child as CollisionObject3D
	var wave_obj: Node = level.get_node_or_null("WaveObjective")
	if wave_obj:
		for child: Node in wave_obj.get_children():
			if child == exclude or child.is_in_group("player"):
				continue
			if child is CollisionObject3D and child.has_node("HealthComponent"):
				return child as CollisionObject3D
		if "all_enemies" in wave_obj and not (wave_obj.all_enemies as Array).is_empty():
			var enemy: Character = wave_obj.all_enemies[0] as Character
			if not enemy.is_inside_tree():
				if wave_obj.has_method("spawn_enemy"):
					wave_obj.spawn_enemy(enemy)
				else:
					wave_obj.add_child(enemy)
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
