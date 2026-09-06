class_name TestUtils
extends RefCounted

## Finds the first damageable collision object (dummy/enemy) in the level, excluding the player.
static func find_dummy(level: Node, exclude: Node = null) -> CollisionObject3D:
	for child: Node in level.get_children():
		if child == exclude or (child is Player):
			continue
		if child is CollisionObject3D and child.has_node("HealthComponent"):
			return child as CollisionObject3D
	var wave_obj: Node = level.get_node_or_null("WaveObjective")
	if wave_obj:
		for child: Node in wave_obj.get_children():
			if child == exclude or (child is Player):
				continue
			if child is CollisionObject3D and child.has_node("HealthComponent"):
				return child as CollisionObject3D
		if "all_enemies" in wave_obj and not (wave_obj.all_enemies as Array).is_empty():
			var enemy: Enemy = wave_obj.all_enemies[0] as Enemy
			if not enemy.is_inside_tree():
				wave_obj.add_child(enemy)
			return enemy
	return null

## Finds the first Enemy instance in the level.
static func find_enemy(level: Node) -> Enemy:
	for child: Node in level.get_children():
		if child is Enemy:
			return child as Enemy
	var wave_obj: Node = level.get_node_or_null("WaveObjective")
	if wave_obj:
		for child: Node in wave_obj.get_children():
			if child is Enemy:
				return child as Enemy
		if "all_enemies" in wave_obj and not (wave_obj.all_enemies as Array).is_empty():
			var enemy: Enemy = wave_obj.all_enemies[0] as Enemy
			if not enemy.is_inside_tree():
				wave_obj.add_child(enemy)
			return enemy
	return null
