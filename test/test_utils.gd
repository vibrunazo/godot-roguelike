class_name TestUtils
extends RefCounted

## Finds the first damageable collision object (dummy/enemy) in the level, excluding the player.
static func find_dummy(level: Node, exclude: Node = null) -> CollisionObject3D:
	for child: Node in level.get_children():
		if child == exclude or (child is Player):
			continue
		if child is CollisionObject3D and child.has_node("HealthComponent"):
			return child as CollisionObject3D
	return null

## Finds the first Enemy instance in the level.
static func find_enemy(level: Node) -> Enemy:
	for child: Node in level.get_children():
		if child is Enemy:
			return child as Enemy
	return null
