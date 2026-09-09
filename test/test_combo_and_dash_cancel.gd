extends Node

const TestUtils = preload("res://test/test_utils.gd")

func _ready() -> void:
	print("--- RUNNING 3-HIT COMBO & DASH CANCEL TEST ---")
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	var player: Player = level.get_node("Player") as Player
	var dummy: CollisionObject3D = TestUtils.find_dummy(level, player)
	var health_comp: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	
	var initial_health: float = health_comp.current_health
	print("Dummy initial health: ", initial_health)
	
	# Wait for initial spawn/navigation repositioning timer (1.0s) to settle, then for player to land on floor
	await get_tree().create_timer(1.1).timeout
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break
			
	if sm.state.name != "PlayerRun":
		printerr("TEST FAILED: Player did not enter PlayerRun.")
		get_tree().quit(1)
		return
		
	# Position player facing dummy
	player.global_position = Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z - 1.3)
	var dir: Vector3 = Vector3(0, 0, 1)
	var target: Transform3D = player.player_root.global_transform.looking_at(player.player_root.global_position + dir, Vector3.UP, true)
	player.player_root.global_transform = target
	
	for i: int in range(60):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break
	
	# =========================================================================
	# PART 1: FULL 3-HIT COMBO & DAMAGE SCALING (Slash -> Stab -> Spin)
	# =========================================================================
	print("\n>>> PART 1: Testing Full 3-Hit Combo (Slash -> Stab -> Spin)")
	
	# 1. Trigger Attack 1 (Slash)
	var click := InputEventAction.new()
	click.action = "click"
	click.pressed = true
	sm._unhandled_input(click)
	
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: Did not enter PlayerAttack.")
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack (Attack 1: Slash)")
	
	# Wait for Attack 1 to hit
	for i: int in range(30):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 8.0:
			break
	if health_comp.current_health != initial_health - 8.0:
		printerr("TEST FAILED: Attack 1 damage mismatch. Expected: ", initial_health - 8.0, ", got: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Attack 1 hit confirmed! Dummy health: ", health_comp.current_health, " (-8.0 damage)")
	
	# Queue Attack 2
	sm._unhandled_input(click)
	
	# Wait for transition to PlayerAttack2 (Stab)
	var in_attack2 := false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack2":
			in_attack2 = true
			break
	if not in_attack2:
		printerr("TEST FAILED: Did not transition to PlayerAttack2.")
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack2 (Attack 2: Stab)")
	
	# Wait for Attack 2 to hit
	for i: int in range(50):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 22.0:
			break
	if health_comp.current_health != initial_health - 22.0:
		printerr("TEST FAILED: Attack 2 damage mismatch. Expected: ", initial_health - 22.0, ", got: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Attack 2 hit confirmed! Dummy health: ", health_comp.current_health, " (-14.0 damage)")
	
	# Queue Attack 3 (Spin)
	sm._unhandled_input(click)
	
	# Wait for transition to PlayerAttack3 (Spin)
	var in_attack3 := false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack3":
			in_attack3 = true
			break
	if not in_attack3:
		printerr("TEST FAILED: Did not transition to PlayerAttack3.")
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack3 (Attack 3: Spin)")
	player.global_position = Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z - 1.0)
	
	# Wait for Attack 3 (Spin) first hit
	for i: int in range(40):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 32.0:
			break
	if health_comp.current_health != initial_health - 32.0:
		printerr("TEST FAILED: Attack 3 first hit damage mismatch. Expected: ", initial_health - 32.0, ", got: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Attack 3 first hit confirmed! Dummy health: ", health_comp.current_health, " (-10.0 damage)")
	
	# Ensure player stays within range for second slash of spin attack
	player.global_position = Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z - 1.0)
	
	# Wait for Attack 3 (Spin) second hit (rehit_interval = 0.32s)
	for i: int in range(40):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 42.0:
			break
	if health_comp.current_health != initial_health - 42.0:
		printerr("TEST FAILED: Attack 3 second hit damage mismatch. Expected: ", initial_health - 42.0, ", got: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Attack 3 second hit confirmed via rehit_interval! Dummy health: ", health_comp.current_health, " (-10.0 damage, 20.0 total)")
	
	# Wait for Attack 3 to finish and return to PlayerRun
	var back_to_run := false
	for i: int in range(120):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			back_to_run = true
			break
	if not back_to_run:
		printerr("TEST FAILED: Did not return to PlayerRun after combo finish.")
		get_tree().quit(1)
		return
	print("Combo completed! Successfully returned to PlayerRun.")
	
	# =========================================================================
	# PART 2: DASH CANCEL ON ATTACK 1 (dash_cancel = true)
	# =========================================================================
	print("\n>>> PART 2: Testing Dash Cancel on Attack 1 (dash_cancel = true)")
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Press movement key so player has movement direction required by can_dash()
	Input.action_press("move_forward")
	await get_tree().physics_frame
	
	# Trigger Attack 1
	sm._unhandled_input(click)
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: Did not enter PlayerAttack for dash cancel test.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Entered PlayerAttack...")
	
	# Immediately send dash input
	var dash_event := InputEventAction.new()
	dash_event.action = "dash"
	dash_event.pressed = true
	sm._unhandled_input(dash_event)
	
	if sm.state.name != "PlayerDash":
		printerr("TEST FAILED: Dash cancel did not transition to PlayerDash! State: ", sm.state.name)
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Dash cancel SUCCESS! Interrupted PlayerAttack directly into PlayerDash.")

	# Verify DashRoot and shader setup (Lecture 75)
	if player.dash_root == null:
		printerr("TEST FAILED: player.dash_root is null.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	var dash_mesh: MeshInstance3D = player.dash_root.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if dash_mesh == null:
		printerr("TEST FAILED: DashRoot missing MeshInstance3D child.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	if dash_mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or dash_mesh.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
		printerr("TEST FAILED: Dash MeshInstance3D cast_shadow or gi_mode invalid.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	var quad: QuadMesh = dash_mesh.mesh as QuadMesh
	if quad == null or quad.size != Vector2(3, 2):
		printerr("TEST FAILED: Dash mesh is not QuadMesh(3, 2).")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	var dash_mat: ShaderMaterial = dash_mesh.material_override as ShaderMaterial
	if dash_mat == null or dash_mat.shader == null:
		printerr("TEST FAILED: Dash MeshInstance3D ShaderMaterial or shader missing.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	if not (dash_mat.get_shader_parameter("NoiseTexture") is NoiseTexture2D) or not (dash_mat.get_shader_parameter("GradientParameter") is GradientTexture1D):
		printerr("TEST FAILED: Dash shader parameters NoiseTexture or GradientParameter invalid.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("DashRoot, QuadMesh, and ShaderMaterial verified.")

	# Verify Dash AnimationPlayer & cross-section MeshInstance3D2 (Lecture 76)
	if player.dash_animation_player == null:
		printerr("TEST FAILED: player.dash_animation_player is null.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	if not player.dash_animation_player.has_animation(&"dash") or not player.dash_animation_player.has_animation(&"RESET"):
		printerr("TEST FAILED: dash_animation_player missing 'dash' or 'RESET' animation.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	if player.dash_animation_player.autoplay != &"RESET":
		printerr("TEST FAILED: dash_animation_player autoplay is not RESET.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	var dash_anim: Animation = player.dash_animation_player.get_animation(&"dash")
	if not is_equal_approx(dash_anim.length, 0.5):
		printerr("TEST FAILED: dash animation length expected 0.5, got: ", dash_anim.length)
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	var dash_mesh2: MeshInstance3D = player.dash_root.get_node_or_null("MeshInstance3D2") as MeshInstance3D
	if dash_mesh2 == null:
		printerr("TEST FAILED: DashRoot missing MeshInstance3D2 child.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	var quad2: QuadMesh = dash_mesh2.mesh as QuadMesh
	if quad2 == null or quad2.size != Vector2(5, 1):
		printerr("TEST FAILED: Dash MeshInstance3D2 mesh is not QuadMesh(5, 1).")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	if dash_mesh2.material_override != dash_mat:
		printerr("TEST FAILED: MeshInstance3D2 does not share ShaderMaterial with MeshInstance3D.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Dash AnimationPlayer and cross-section MeshInstance3D2 verified.")

	# Wait for dash to finish and return to PlayerRun
	back_to_run = false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			back_to_run = true
			break
	if not back_to_run:
		printerr("TEST FAILED: Did not return to PlayerRun after dash.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Dash completed and returned to PlayerRun.")
	
	# Wait for dash cooldown so player can dash again
	for i: int in range(60):
		await get_tree().physics_frame
		if player.can_dash():
			break
			
	# =========================================================================
	# PART 3: NO DASH CANCEL ON ATTACK 3 (dash_cancel = false / committed)
	# =========================================================================
	print("\n>>> PART 3: Testing Dash Cancel Forbidden on Attack 3 (Spin Attack)")
	
	# Chain to Attack 3 while still pressing move_forward
	var c1 := InputEventAction.new()
	c1.action = "click"
	c1.pressed = true
	sm._unhandled_input(c1) # Trigger Attack 1
	for i: int in range(20):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack":
			break
			
	var c2 := InputEventAction.new()
	c2.action = "click"
	c2.pressed = true
	sm._unhandled_input(c2) # Queue Attack 2
	
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack2":
			break
			
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var c3 := InputEventAction.new()
	c3.action = "click"
	c3.pressed = true
	sm._unhandled_input(c3) # Queue Attack 3
	
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack3":
			break
			
	if sm.state.name != "PlayerAttack3":
		printerr("TEST FAILED: Could not reach PlayerAttack3 for commitment test. Current state: ", sm.state.name)
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Entered PlayerAttack3 (SpinAttack)...")
	
	# Send dash input during SpinAttack (movement is held, so can_dash() is true, but dash_cancel is false)
	sm._unhandled_input(dash_event)
	await get_tree().physics_frame
	
	# Verify that the player is STILL in PlayerAttack3 and was NOT allowed to dash
	if sm.state.name == "PlayerDash":
		printerr("TEST FAILED: Player was able to dash cancel out of PlayerAttack3!")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	if sm.state.name != "PlayerAttack3":
		printerr("TEST FAILED: Unexpected state during spin attack: ", sm.state.name)
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Commitment verified! Dash cancel was correctly rejected during SpinAttack.")
	Input.action_release("move_forward")
	
	# Wait for spin to finish cleanly
	back_to_run = false
	for i: int in range(120):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			back_to_run = true
			break
	if not back_to_run:
		printerr("TEST FAILED: Did not return to PlayerRun after final spin.")
		get_tree().quit(1)
		return
		
	# =========================================================================
	# PART 4: SWORD SLASH VFX (Lecture 79)
	# =========================================================================
	print("\n>>> PART 4: Testing Sword Slash VFX Setup")
	var slash_vfx: MeshInstance3D = player.get_node_or_null("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot/LazerSword/SlashVFX") as MeshInstance3D
	if slash_vfx == null:
		printerr("TEST FAILED: SlashVFX MeshInstance3D not found under LazerSword.")
		get_tree().quit(1)
		return
	if slash_vfx.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		printerr("TEST FAILED: SlashVFX cast_shadow is not OFF.")
		get_tree().quit(1)
		return
	if slash_vfx.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
		printerr("TEST FAILED: SlashVFX gi_mode is not DISABLED.")
		get_tree().quit(1)
		return
	var slash_quad: QuadMesh = slash_vfx.mesh as QuadMesh
	if slash_quad == null or slash_quad.size != Vector2(4, 2):
		printerr("TEST FAILED: SlashVFX mesh is not QuadMesh(4, 2).")
		get_tree().quit(1)
		return
	if not is_equal_approx(slash_vfx.position.x, -2.0):
		printerr("TEST FAILED: SlashVFX position.x expected -2.0, got: ", slash_vfx.position.x)
		get_tree().quit(1)
		return
	var slash_mat: ShaderMaterial = slash_vfx.material_override as ShaderMaterial
	if slash_mat == null:
		printerr("TEST FAILED: SlashVFX material_override is not ShaderMaterial.")
		get_tree().quit(1)
		return
	if not slash_mat.get_shader_parameter("NoiseTexture") is NoiseTexture2D:
		printerr("TEST FAILED: SlashVFX NoiseTexture is not NoiseTexture2D.")
		get_tree().quit(1)
		return
	if not slash_mat.get_shader_parameter("GradientParameter") is GradientTexture1D:
		printerr("TEST FAILED: SlashVFX GradientParameter is not GradientTexture1D.")
		get_tree().quit(1)
		return
	var slash_speed: float = slash_mat.get_shader_parameter("Speed") as float
	if not is_equal_approx(slash_speed, 3.0):
		printerr("TEST FAILED: SlashVFX Speed expected 3.0, got: ", slash_speed)
		get_tree().quit(1)
		return

	# Verify slash_vfx script, weapon_slot reference, and attack_type
	if slash_vfx.get_script() == null:
		printerr("TEST FAILED: SlashVFX does not have a script attached.")
		get_tree().quit(1)
		return
	if slash_vfx.get("weapon_slot") == null:
		printerr("TEST FAILED: SlashVFX weapon_slot export is null.")
		get_tree().quit(1)
		return
	if slash_vfx.get("attack_type") != WeaponSlot.mode.SLASH:
		printerr("TEST FAILED: SlashVFX attack_type is not WeaponSlot.mode.SLASH (1). Got: ", slash_vfx.get("attack_type"))
		get_tree().quit(1)
		return

	# Test dynamic visibility & threshold updates driven by WeaponSlot
	var weapon_slot: WeaponSlot = slash_vfx.get("weapon_slot") as WeaponSlot
	weapon_slot.attack_mode = WeaponSlot.mode.NONE
	weapon_slot.vfx_threshold = 0.8
	await get_tree().process_frame
	if slash_vfx.visible:
		printerr("TEST FAILED: SlashVFX visible should be false when attack_mode is NONE.")
		get_tree().quit(1)
		return

	weapon_slot.attack_mode = WeaponSlot.mode.SLASH
	weapon_slot.vfx_threshold = 0.3
	await get_tree().process_frame
	if not slash_vfx.visible:
		printerr("TEST FAILED: SlashVFX visible should be true when attack_mode is slash.")
		get_tree().quit(1)
		return
	var current_threshold: float = slash_mat.get_shader_parameter("Threshold") as float
	if not is_equal_approx(current_threshold, 0.3):
		printerr("TEST FAILED: SlashVFX Threshold not updated from weapon_slot. Expected 0.3, got: ", current_threshold)
		get_tree().quit(1)
		return
	print("SlashVFX script reactivity (visibility and shader threshold) verified.")

	# Verify animation easings on Melee_1H_Attack_Slice_Horizontal
	var slice_anim: Animation = load("res://Assets/KayKit_Assets/KayKit_Character_Animations_1.0/Animations/gltf/Rig_Medium/Animations/Melee_1H_Attack_Slice_Horizontal.res")
	for i: int in range(slice_anim.get_track_count()):
		if str(slice_anim.track_get_path(i)) == "Rig_Medium/Skeleton3D/WeaponSlot:vfx_threshold":
			var t0: float = slice_anim.track_get_key_transition(i, 0)
			var t1: float = slice_anim.track_get_key_transition(i, 1)
			if not is_equal_approx(t0, 0.5):
				printerr("TEST FAILED: Slice horizontal key 0 transition expected 0.5 (ease out), got: ", t0)
				get_tree().quit(1)
				return
			if not is_equal_approx(t1, 2.0):
				printerr("TEST FAILED: Slice horizontal key 1 transition expected 2.0 (ease in), got: ", t1)
				get_tree().quit(1)
				return
			print("Slice horizontal animation vfx_threshold easing (ease out: 0.5, ease in: 2.0) verified.")

	print("Sword Slash VFX (QuadMesh, ShaderMaterial, transform, script & easings) verified successfully!")

	# =========================================================================
	# PART 5: DASH CANCEL OVERRIDES QUEUED ATTACK & NO-WASD DASH FALLBACK
	# =========================================================================
	print("\n>>> PART 5: Testing Stationary Dash & Dash Cancel Overriding Queued Attack")
	# Ensure dash cooldown has reset
	for i: int in range(60):
		await get_tree().physics_frame
		if player.can_dash() and sm.state.name == "PlayerRun":
			break

	# 1. Test stationary dash (no WASD pressed)
	if not player.can_dash():
		printerr("TEST FAILED: player.can_dash() returned false when stationary with cooldown stopped.")
		get_tree().quit(1)
		return
	var stationary_dash := InputEventAction.new()
	stationary_dash.action = "dash"
	stationary_dash.pressed = true
	sm._unhandled_input(stationary_dash)

	if sm.state.name != "PlayerDash":
		printerr("TEST FAILED: Stationary dash did not transition to PlayerDash. State: ", sm.state.name)
		get_tree().quit(1)
		return
	print("Stationary dash (no-WASD) successfully entered PlayerDash!")

	# Wait for stationary dash to finish and cooldown to reset
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun" and player.can_dash():
			break

	# 2. Test queuing Attack 3 during Attack 2, then dash cancelling Attack 2
	var click_event := InputEventAction.new()
	click_event.action = "click"
	click_event.pressed = true

	# Enter Attack 1
	sm._unhandled_input(click_event)
	for i: int in range(20):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack":
			break

	# Queue Attack 2
	sm._unhandled_input(click_event)
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack2":
			break

	if sm.state.name != "PlayerAttack2":
		printerr("TEST FAILED: Failed to enter PlayerAttack2 for queue-override test. State: ", sm.state.name)
		get_tree().quit(1)
		return
	print("Entered PlayerAttack2 (Stab)...")

	# Queue Attack 3 (spam click)
	sm._unhandled_input(click_event)
	var attack2_node: PlayerState = sm.state
	if not attack2_node.get("queued_attack"):
		printerr("TEST FAILED: Attack 3 was not queued in PlayerAttack2.")
		get_tree().quit(1)
		return
	print("Attack 3 successfully queued in PlayerAttack2 (queued_attack = true).")

	# Dash cancel out of Attack 2 before it reaches Attack 3
	sm._unhandled_input(stationary_dash)

	if sm.state.name != "PlayerDash":
		printerr("TEST FAILED: Dash cancel failed to interrupt PlayerAttack2 with queued attack! State: ", sm.state.name)
		get_tree().quit(1)
		return
	print("Dash cancel SUCCESS! PlayerAttack2 was interrupted directly into PlayerDash despite queued Attack 3.")

	# Wait past the 0.5s queued attack window (60 frames = 1.0s) and verify player NEVER enters PlayerAttack3
	var entered_attack3 := false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack3":
			entered_attack3 = true
			break
	if entered_attack3:
		printerr("TEST FAILED: Queued Attack 3 triggered after dash cancel!")
		get_tree().quit(1)
		return
	print("Verified that queued Attack 3 was cancelled and never triggered.")

	# Wait for dash to return to PlayerRun
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			break
	if sm.state.name != "PlayerRun":
		printerr("TEST FAILED: Did not return to PlayerRun after dash cancel. State: ", sm.state.name)
		get_tree().quit(1)
		return
	print("Clean return to PlayerRun verified.")

	print("\n====================================================================")
	print("  ALL 3-HIT COMBO & DASH CANCEL TESTS PASSED!                      ")
	print("  1. Combo Damage: Slash (8) -> Stab (14) -> Spin (10 x 2 = 20)")
	print("  2. Dash Cancel on Attack 1: Cancelled into PlayerDash successfully")
	print("  3. Dash Cancel on Attack 3: Correctly blocked / committed to spin")
	print("  4. State recovery: Clean return to PlayerRun in all scenarios     ")
	print("  5. Sword Slash VFX: QuadMesh(4, 2), ShaderMaterial & transform ok")
	print("  6. SlashVFX tool script: weapon_slot reactivity & anim easings ok")
	print("  7. Stationary Dash & Queued Attack Override: Verified successfully")
	print("====================================================================")
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().quit(0)
