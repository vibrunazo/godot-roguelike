## Verifies all Level 13 table decorators physically block the real player
## capsule. Uses a swept body motion, not a visual-only overlap assertion.
extends Node3D

func _ready() -> void:
	var level: Node3D = (load("res://Levels/level_13.tscn") as PackedScene).instantiate() as Node3D
	level.get_node("WaveObjective").set_script(null)
	add_child(level)
	var player: Character = level.get_node("Player") as Character
	# Isolate body collision from AI, camera input and automatic state motion.
	player.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame
	await get_tree().physics_frame
	var names: Array[String] = ["LowerWorkTable", "LowerBanquetTable", "UpperFeastTable", "UpperLongTable"]
	var failed: bool = false
	for table_name: String in names:
		var table: StaticBody3D = level.get_node("NavigationRegion3D/Litter/" + table_name) as StaticBody3D
		for direction: float in [-1.0, 1.0]:
			# Each authored table is yawed 90 degrees, so this crosses its
			# short axis. Keep capsule bottom above the floor to isolate furniture.
			player.global_position = table.global_position + Vector3(direction * 3.0, 1.05, 0.0)
			await get_tree().physics_frame
			var collision: KinematicCollision3D = player.move_and_collide(Vector3(-direction * 6.0, 0.0, 0.0))
			if collision == null or collision.get_collider() != table or (player.global_position.x - table.global_position.x) * direction <= 0.0:
				printerr("TEST FAILED: table did not block player: ", table_name, " direction=", direction, " player=", player.global_position)
				failed = true
			else:
				print("PASS: ", table_name, " blocks player from side ", direction, " at ", player.global_position)
	level.queue_free()
	await get_tree().physics_frame
	print("LEVEL 13 TABLE COLLISION TEST ", "FAILED" if failed else "PASSED")
	get_tree().quit(1 if failed else 0)
