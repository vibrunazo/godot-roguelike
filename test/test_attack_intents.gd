extends Node

## Automated test suite for unified attack intents (Phase A):
## - Edge intents on Character (attack_requested/dash_requested, consume-once)
## - command_attack()/command_dash() parity between PlayerInputComponent and AIStateMachine
## - Character.can_dash() cooldown gating (timer vs null timer)
## - StateMachine.request_state() shared transition API + validation
## - PlayerInputComponent.order_attack()/order_dash() via the shared API

const MeleeEnemyScene: PackedScene = preload("res://Enemy/melee_enemy.tscn")


func _ready() -> void:
	print("--- RUNNING ATTACK INTENTS TEST ---")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)

	var player: Character = level.get_node("Player") as Character
	var input_comp: PlayerInputComponent = player.get_node("PlayerInputComponent") as PlayerInputComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	var cooldown: Timer = player.get_node("DashCooldown") as Timer

	# Wait for spawn repositioning to settle, then for player to land in PlayerRun.
	await get_tree().create_timer(1.1).timeout
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break
	if sm.state.name != "PlayerRun":
		printerr("TEST FAILED: Player did not enter PlayerRun.")
		get_tree().quit(1)
		return

	# Enemy provides the AI-controller side; freeze its mind so the body stays put.
	var enemy: Character = MeleeEnemyScene.instantiate() as Character
	add_child(enemy)
	await get_tree().physics_frame
	var mind_sm: AIStateMachine = enemy.ai_state_machine as AIStateMachine
	mind_sm.set_physics_process(false)
	cooldown.stop()

	test_part_1_player_controller_intents(player, input_comp)
	test_part_2_ai_controller_intents(enemy, mind_sm)
	test_part_3_dash_cooldown_gating(player, input_comp, cooldown, enemy)
	await test_part_4_request_state_api(sm)
	test_part_5_player_orders(player, input_comp, sm, cooldown)
	await test_part_6_enemy_shared_attack()

	print("\n================================================================")
	print("  ALL ATTACK INTENTS TESTS PASSED!                              ")
	print("  1. PlayerController edge intents + consume-once verified       ")
	print("  2. AIController edge intents + consume-once verified           ")
	print("  3. Dash cooldown gating (timer vs null) verified               ")
	print("  4. Shared request_state() API + validation verified            ")
	print("  5. PlayerController orders via shared API verified             ")
	print("  6. Enemy shared-attack order/queue/cancel proof verified       ")
	print("================================================================")
	get_tree().quit(0)


func test_part_1_player_controller_intents(player: Character, input_comp: PlayerInputComponent) -> void:
	print("\n>>> PART 1: PlayerController edge intents")
	input_comp.command_attack()
	if not player.attack_requested:
		printerr("TEST FAILED: command_attack did not raise attack_requested.")
		get_tree().quit(1)
		return
	if not player.consume_attack_request():
		printerr("TEST FAILED: consume_attack_request did not return true once.")
		get_tree().quit(1)
		return
	if player.attack_requested or player.consume_attack_request():
		printerr("TEST FAILED: attack intent not cleared after consume.")
		get_tree().quit(1)
		return
	input_comp.command_dash()
	if not player.dash_requested:
		printerr("TEST FAILED: command_dash did not raise dash_requested.")
		get_tree().quit(1)
		return
	if not player.consume_dash_request():
		printerr("TEST FAILED: consume_dash_request did not return true once.")
		get_tree().quit(1)
		return
	if player.dash_requested or player.consume_dash_request():
		printerr("TEST FAILED: dash intent not cleared after consume.")
		get_tree().quit(1)
		return
	print("PlayerController intents set, consumed once, and cleared.")


func test_part_2_ai_controller_intents(enemy: Character, mind_sm: AIStateMachine) -> void:
	print("\n>>> PART 2: AIController edge intents")
	mind_sm.command_attack()
	if not enemy.attack_requested:
		printerr("TEST FAILED: AI command_attack did not raise attack_requested.")
		get_tree().quit(1)
		return
	if not enemy.consume_attack_request() or enemy.consume_attack_request():
		printerr("TEST FAILED: AI attack intent consume-once broken.")
		get_tree().quit(1)
		return
	mind_sm.command_dash()
	if not enemy.dash_requested:
		printerr("TEST FAILED: AI command_dash did not raise dash_requested.")
		get_tree().quit(1)
		return
	if not enemy.consume_dash_request() or enemy.consume_dash_request():
		printerr("TEST FAILED: AI dash intent consume-once broken.")
		get_tree().quit(1)
		return
	# AI order_attack still validates through delegation: missing state returns false.
	if mind_sm.order_attack("NoSuchState"):
		printerr("TEST FAILED: AI order_attack accepted a missing state.")
		get_tree().quit(1)
		return
	print("AIController intents set, consumed once, and order validation delegates.")


func test_part_3_dash_cooldown_gating(player: Character, input_comp: PlayerInputComponent, cooldown: Timer, enemy: Character) -> void:
	print("\n>>> PART 3: Dash cooldown gating")
	if not player.can_dash() or not input_comp.can_dash():
		printerr("TEST FAILED: can_dash false with stopped cooldown.")
		get_tree().quit(1)
		return
	cooldown.start()
	if player.can_dash() or input_comp.can_dash():
		printerr("TEST FAILED: can_dash true with running cooldown.")
		get_tree().quit(1)
		return
	cooldown.stop()
	if not player.can_dash() or not input_comp.can_dash():
		printerr("TEST FAILED: can_dash false after cooldown stopped.")
		get_tree().quit(1)
		return
	if not enemy.can_dash():
		printerr("TEST FAILED: enemy without cooldown timer must always be dash-ready.")
		get_tree().quit(1)
		return
	print("Cooldown gating verified (running blocks, stopped/null allows).")


func test_part_4_request_state_api(sm: StateMachine) -> void:
	print("\n>>> PART 4: Shared request_state() API")
	await get_tree().physics_frame
	if sm.request_state("NoSuchState"):
		printerr("TEST FAILED: request_state accepted a missing state.")
		get_tree().quit(1)
		return
	if not sm.request_state("PlayerRun"):
		printerr("TEST FAILED: request_state rejected existing PlayerRun.")
		get_tree().quit(1)
		return
	if sm.state.name != "PlayerRun":
		printerr("TEST FAILED: request_state did not transition. State: ", sm.state.name)
		get_tree().quit(1)
		return
	print("request_state() validates (false on missing) and transitions (true).")


func test_part_5_player_orders(player: Character, input_comp: PlayerInputComponent, sm: StateMachine, cooldown: Timer) -> void:
	print("\n>>> PART 5: PlayerController orders")
	cooldown.stop()
	sm.request_state("PlayerRun")
	if not input_comp.order_attack():
		printerr("TEST FAILED: order_attack from PlayerRun returned false.")
		get_tree().quit(1)
		return
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: order_attack did not enter PlayerAttack. State: ", sm.state.name)
		get_tree().quit(1)
		return
	# Dash-cancel path is wired on attack states: order_dash must work from PlayerAttack.
	if not input_comp.order_dash():
		printerr("TEST FAILED: order_dash from PlayerAttack returned false.")
		get_tree().quit(1)
		return
	if sm.state.name != "PlayerDash":
		printerr("TEST FAILED: order_dash did not enter PlayerDash. State: ", sm.state.name)
		get_tree().quit(1)
		return
	# PlayerDash wires no attack_state: ordering an attack from mid-dash must fail.
	if input_comp.order_attack():
		printerr("TEST FAILED: order_attack from PlayerDash should return false.")
		get_tree().quit(1)
		return
	# Cooldown gate: running cooldown blocks dash orders from PlayerRun.
	sm.request_state("PlayerRun")
	cooldown.start()
	if input_comp.order_dash():
		printerr("TEST FAILED: order_dash ignored running cooldown.")
		cooldown.stop()
		get_tree().quit(1)
		return
	if sm.state.name != "PlayerRun":
		printerr("TEST FAILED: blocked order_dash changed state. State: ", sm.state.name)
		cooldown.stop()
		get_tree().quit(1)
		return
	cooldown.stop()
	# Consume any bridge-set flags so later phases start clean.
	player.consume_attack_request()
	player.consume_dash_request()
	print("PlayerController orders drive transitions through the shared API.")


## Proof that the player stab state plugs into an enemy: the AI orders the shared
## attack onto an enemy body, an AI-raised attack intent chains a test-only
## combo_next through the real queue window, and an AI-raised dash intent
## dash-cancels (dash_cancel/dash_state wired test-only, scenes untouched).
func test_part_6_enemy_shared_attack() -> void:
	print("\n>>> PART 6: Enemy shared-attack proof")
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100.0, 1.0, 100.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)

	var enemy: Character = MeleeEnemyScene.instantiate() as Character
	add_child(enemy)
	enemy.global_position = Vector3(0.0, 1.0, 5.0)
	var mind_sm: AIStateMachine = enemy.ai_state_machine as AIStateMachine
	var body_sm: StateMachine = enemy.state_machine
	mind_sm.set_physics_process(false)
	for i: int in range(120):
		await get_tree().physics_frame
		if enemy.is_on_floor() and body_sm.state.name == "EnemyMove":
			break
	if body_sm.state.name != "EnemyMove":
		printerr("TEST FAILED: Proof enemy did not settle in EnemyMove.")
		get_tree().quit(1)
		return

	var move_node: CharacterState = body_sm.get_node("EnemyMove") as CharacterState
	var attack_node: CharacterAttack = body_sm.get_node("EnemyAttack") as CharacterAttack
	var chain := CharacterAttack.new()
	chain.name = "ProofChainAttack"
	chain.character = enemy
	chain.attack_animation_name = "MeleeAttack"
	var chain_next: Array[CharacterState] = [move_node]
	chain.next_states = chain_next
	body_sm.add_child(chain)
	attack_node.combo_next = chain
	attack_node.queued_attack_time = 0.05
	attack_node.dash_cancel = true
	attack_node.dash_state = move_node

	if not mind_sm.order_attack("EnemyAttack") or body_sm.state.name != "EnemyAttack":
		printerr("TEST FAILED: AI order_attack did not enter shared EnemyAttack. State: ", body_sm.state.name)
		get_tree().quit(1)
		return
	print("AI order_attack entered the shared attack on the enemy body.")

	mind_sm.command_attack()
	var chained := false
	for i: int in range(120):
		await get_tree().physics_frame
		if body_sm.state.name == "ProofChainAttack":
			chained = true
			break
	if not chained:
		printerr("TEST FAILED: AI attack intent did not chain combo_next. State: ", body_sm.state.name)
		get_tree().quit(1)
		return
	print("AI attack intent chained combo_next through the queue window.")
	chain.finish_attack("MeleeAttack")
	if body_sm.state.name != "EnemyMove":
		printerr("TEST FAILED: Chain did not return to EnemyMove. State: ", body_sm.state.name)
		get_tree().quit(1)
		return

	if not mind_sm.order_attack("EnemyAttack") or body_sm.state.name != "EnemyAttack":
		printerr("TEST FAILED: AI order_attack (cancel setup) failed. State: ", body_sm.state.name)
		get_tree().quit(1)
		return
	mind_sm.command_dash()
	var cancelled := false
	for i: int in range(120):
		await get_tree().physics_frame
		if body_sm.state.name == "EnemyMove":
			cancelled = true
			break
	if not cancelled:
		printerr("TEST FAILED: AI dash intent did not cancel to EnemyMove. State: ", body_sm.state.name)
		get_tree().quit(1)
		return
	print("AI dash intent dash-cancelled the shared attack.")
