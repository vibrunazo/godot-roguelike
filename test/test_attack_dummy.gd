extends Node

const TestUtils = preload("res://test/test_utils.gd")

func _ready() -> void:
	print("--- RUNNING ATTACK DUMMY TEST ---")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	var player: Character = level.get_node("Player") as Character
	var dummy: CollisionObject3D = TestUtils.find_dummy(level, player)
	var health_comp: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	
	var initial_health: float = health_comp.current_health
	print("Dummy initial health: ", initial_health)
	
	# Wait for player to land on floor in PlayerRun state
	var landed := false
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			landed = true
			break
			
	if not landed:
		printerr("TEST FAILED: Player did not settle on floor.")
		get_tree().quit(1)
		return
		
	# Position player in front of dummy and face it
	player.global_position = Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z - 1.3)
	var dir: Vector3 = Vector3(0, 0, 1)
	var target: Transform3D = player.mesh_mount.global_transform.looking_at(player.mesh_mount.global_position + dir, Vector3.UP, true)
	player.mesh_mount.global_transform = target
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Send click input
	var ev := InputEventAction.new()
	ev.action = "click"
	ev.pressed = true
	sm._unhandled_input(ev)
	
	print("State after click: ", sm.state.name)
	
	# Wait for animation and hitbox to hit dummy
	var attack_damage: float = (sm.get_node("PlayerAttack") as CharacterAttack).damage
	var hit := false
	for i: int in range(80):
		await get_tree().physics_frame
		if health_comp.current_health < initial_health:
			hit = true
			print("HIT CONFIRMED! Dummy health reduced to: ", health_comp.current_health, " on frame ", i)
			break
			
	print("Final Health: ", health_comp.current_health)
	if hit and is_equal_approx(health_comp.current_health, initial_health - attack_damage):
		print("================================")
		print("  ALL TESTS PASSED (100% OK)    ")
		print("================================")
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(0)
	else:
		printerr("TEST FAILED: Health was not reduced as expected. Got: ", health_comp.current_health)
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(1)
