## Minimal real-physics regression for enemy top contacts and terrain landing.
extends Node3D

var failures: int = 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("TEST FAILED: ", message)
	else:
		print("  ok: ", message)


func add_shape(body: CollisionObject3D, shape: Shape3D) -> void:
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)


func _ready() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: BoxShape3D = BoxShape3D.new()
	floor_shape.size = Vector3(30.0, 1.0, 30.0)
	add_shape(floor_body, floor_shape)
	floor_body.position.y = -0.5
	add_child(floor_body)

	var enemy: Character = Character.new()
	enemy.add_to_group("enemy")
	var enemy_shape: BoxShape3D = BoxShape3D.new()
	enemy_shape.size = Vector3(2.0, 2.0, 2.0)
	add_shape(enemy, enemy_shape)
	enemy.position.y = 1.0
	add_child(enemy)

	var player: Character = Character.new()
	player.add_to_group("player")
	add_shape(player, CapsuleShape3D.new())
	player.position.y = 5.0
	add_child(player)
	var false_landing: bool = false
	var terrain_landing: bool = false
	for frame: int in range(240):
		await get_tree().physics_frame
		player.velocity += player.get_gravity() * get_physics_process_delta_time()
		player.move_character()
		if player.is_on_floor():
			if player.position.y > 1.1:
				false_landing = true
			else:
				terrain_landing = true
				break
	check(not false_landing, "Enemy top never counts as floor")
	check(terrain_landing, "Player slides off and lands on terrain")
	check(absf(player.position.x) > 1.0, "Centered drop gets outward motion")

	player.position = Vector3(4.0, 1.01, 0.0)
	for frame: int in range(90):
		await get_tree().physics_frame
		player.velocity = Vector3(-3.0, -1.0, 0.0)
		player.move_character()
	check(player.position.x > 1.0, "Enemy still blocks a ground-level side approach")
	get_tree().quit(0 if failures == 0 else 1)
