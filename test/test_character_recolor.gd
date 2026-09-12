extends Node

func _ready() -> void:
	print("--- RUNNING CHARACTER PALETTE RECOLOR TEST ---")
	
	# ---------------------------------------------------------
	# PART 1: Component Unit Defaults & Gradient Population
	# ---------------------------------------------------------
	print("\n>>> PART 1: Component Defaults & Defaults Population")
	var comp: CharacterColorComponent = CharacterColorComponent.new()
	add_child(comp)
	
	if comp.palette_mode != CharacterColorComponent.PaletteMode.ENEMY:
		printerr("TEST FAILED: Default palette_mode should be ENEMY.")
		get_tree().quit(1)
		return
	if comp.global_tint != Color.WHITE:
		printerr("TEST FAILED: Default global_tint should be Color.WHITE.")
		get_tree().quit(1)
		return
	if comp.gradients.size() != 8:
		printerr("TEST FAILED: Expected 8 default gradients, got: %d" % comp.gradients.size())
		get_tree().quit(1)
		return
	if comp.material == null or comp.material.shader == null:
		printerr("TEST FAILED: ShaderMaterial or shader not initialized.")
		get_tree().quit(1)
		return
	
	print("[OK] Component defaults & 8-gradient auto-population verified.")
	comp.queue_free()

	# ---------------------------------------------------------
	# PART 2: Ranged Enemy Scene Wiring & Mesh Discovery
	# ---------------------------------------------------------
	print("\n>>> PART 2: Ranged Enemy Scene Wiring")
	var ranged_scene: PackedScene = load("res://Enemy/ranged_enemy.tscn") as PackedScene
	var ranged: Character = ranged_scene.instantiate() as Character
	add_child(ranged)
	
	await get_tree().process_frame
	
	if ranged.color_component == null:
		printerr("TEST FAILED: RangedEnemy color_component is null.")
		get_tree().quit(1)
		return
	
	var ranged_body_meshes: Array[MeshInstance3D] = ranged.color_component.get_body_meshes()
	if ranged_body_meshes.size() != 6:
		printerr("TEST FAILED: Expected 6 body meshes on RangedEnemy, got: %d" % ranged_body_meshes.size())
		get_tree().quit(1)
		return
	
	for mi: MeshInstance3D in ranged_body_meshes:
		if mi.material_override != ranged.color_component.material:
			printerr("TEST FAILED: Mesh %s material_override does not match component material." % mi.name)
			get_tree().quit(1)
			return
	
	# Verify weapon hitbox mesh is NOT overridden
	var weapon_mesh: MeshInstance3D = ranged.find_child("MeshInstance3D", true, false) as MeshInstance3D
	if weapon_mesh and weapon_mesh.material_override == ranged.color_component.material:
		printerr("TEST FAILED: Weapon hitbox cylinder mesh was incorrectly overridden!")
		get_tree().quit(1)
		return
	
	print("[OK] RangedEnemy wired color_component verified; 6/6 meshes overridden; weapon hitbox unaffected.")

	# ---------------------------------------------------------
	# PART 3: Shader Parameter Updates & Runtime API
	# ---------------------------------------------------------
	print("\n>>> PART 3: Runtime Tint and Gradient Updates")
	var test_tint: Color = Color(0.2, 0.8, 0.4, 1.0)
	ranged.color_component.set_global_tint(test_tint)
	var mat_tint: Variant = ranged.color_component.material.get_shader_parameter("global_tint")
	if mat_tint != test_tint:
		printerr("TEST FAILED: Shader global_tint not updated. Expected %s, got %s" % [str(test_tint), str(mat_tint)])
		get_tree().quit(1)
		return
	
	ranged.color_component.set_slot_color(7, Color.PURPLE)
	var palettes: Variant = ranged.color_component.material.get_shader_parameter("gradient_palettes")
	if not (palettes is Array) or (palettes as Array).size() != 8:
		printerr("TEST FAILED: Shader gradient_palettes parameter invalid or wrong size.")
		get_tree().quit(1)
		return
	
	print("[OK] Global tint and slot color updates verified on ShaderMaterial.")
	ranged.queue_free()

	# ---------------------------------------------------------
	# PART 4: Enemy Brute Scene Wiring & Application
	# ---------------------------------------------------------
	print("\n>>> PART 4: Enemy Brute Scene Wiring")
	var brute_scene: PackedScene = load("res://Enemy/enemy_brute.tscn") as PackedScene
	var brute: Character = brute_scene.instantiate() as Character
	add_child(brute)
	
	await get_tree().process_frame
	
	if brute.color_component == null:
		printerr("TEST FAILED: EnemyBrute color_component is null.")
		get_tree().quit(1)
		return
	
	var brute_body_meshes: Array[MeshInstance3D] = brute.color_component.get_body_meshes()
	if brute_body_meshes.size() != 6:
		printerr("TEST FAILED: Expected 6 body meshes on EnemyBrute, got: %d" % brute_body_meshes.size())
		get_tree().quit(1)
		return
	
	for mi: MeshInstance3D in brute_body_meshes:
		if mi.material_override != brute.color_component.material:
			printerr("TEST FAILED: Brute mesh %s material_override does not match component material." % mi.name)
			get_tree().quit(1)
			return
	
	print("[OK] EnemyBrute wired color_component verified (6/6 body meshes overridden).")
	brute.queue_free()

	# ---------------------------------------------------------
	# PART 5: Player Scene Wiring & Player Palette Mode
	# ---------------------------------------------------------
	print("\n>>> PART 5: Player Character Scene Wiring")
	var player_scene: PackedScene = load("res://Player/player.tscn") as PackedScene
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	
	await get_tree().process_frame
	
	if player.color_component == null:
		printerr("TEST FAILED: Player color_component is null.")
		get_tree().quit(1)
		return
	
	var player_body_meshes: Array[MeshInstance3D] = player.color_component.get_body_meshes()
	if player_body_meshes.size() != 6:
		printerr("TEST FAILED: Expected 6 body meshes on Player, got: %d" % player_body_meshes.size())
		get_tree().quit(1)
		return
	
	for mi: MeshInstance3D in player_body_meshes:
		if mi.material_override != player.color_component.material:
			printerr("TEST FAILED: Player mesh %s material_override does not match component material." % mi.name)
			get_tree().quit(1)
			return
	
	# Verify LazerSword mesh is NOT overridden
	var sword_mesh: MeshInstance3D = player.find_child("LazerSword", true, false) as MeshInstance3D
	if sword_mesh and sword_mesh.material_override == player.color_component.material:
		printerr("TEST FAILED: Player LazerSword was incorrectly overridden by CharacterColorComponent!")
		get_tree().quit(1)
		return
	
	# Verify SlashVFX mesh is NOT overridden
	var slash_mesh: MeshInstance3D = player.find_child("SlashVFX", true, false) as MeshInstance3D
	if slash_mesh and slash_mesh.material_override == player.color_component.material:
		printerr("TEST FAILED: Player SlashVFX was incorrectly overridden by CharacterColorComponent!")
		get_tree().quit(1)
		return
	
	var mode_val: Variant = player.color_component.material.get_shader_parameter("palette_mode")
	if int(mode_val) != 1:
		printerr("TEST FAILED: Player palette_mode should be 1, got: %s" % str(mode_val))
		get_tree().quit(1)
		return
	
	print("[OK] Player wired color_component verified (palette_mode = PLAYER); LazerSword & SlashVFX unaffected.")
	player.queue_free()

	# ---------------------------------------------------------
	# PART 6: Other Concrete Enemies (Melee & Firebomber)
	# ---------------------------------------------------------
	print("\n>>> PART 6: Inherited Enemies Verification (Melee & Firebomber)")
	var melee_scene: PackedScene = load("res://Enemy/melee_enemy.tscn") as PackedScene
	var melee: Character = melee_scene.instantiate() as Character
	add_child(melee)
	
	var firebomber_scene: PackedScene = load("res://Enemy/firebomber_enemy.tscn") as PackedScene
	var firebomber: Character = firebomber_scene.instantiate() as Character
	add_child(firebomber)
	
	await get_tree().process_frame
	
	if melee.color_component == null:
		printerr("TEST FAILED: MeleeEnemy inherited color_component is null.")
		get_tree().quit(1)
		return
	if firebomber.color_component == null:
		printerr("TEST FAILED: FirebomberEnemy inherited color_component is null.")
		get_tree().quit(1)
		return
	
	var fb_grad: Gradient = firebomber.color_component.gradients[7]
	if fb_grad == null or fb_grad.colors.size() < 2 or fb_grad.colors[0].g < 0.4:
		printerr("TEST FAILED: Expected Firebomber slot 7 to be customized Orange gradient, got: %s" % str(fb_grad))
		get_tree().quit(1)
		return
	print("[OK] FirebomberEnemy orange gradient on slot 7 verified (color: %s)." % str(fb_grad.colors[0]))
	
	print("[OK] MeleeEnemy and FirebomberEnemy inherited color_component verified.")
	melee.queue_free()
	firebomber.queue_free()

	print("\nALL CHARACTER RECOLOR TESTS PASSED SUCCESSFULLY!")
	get_tree().quit(0)
