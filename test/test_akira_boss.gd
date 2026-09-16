## Automated verification suite for the Akira boss.
## Verifies brute-based bigger body, grounded collision fit (no float/sink),
## backpack riders with hidden legs and melee-equal swords with player-like
## fire slash VFX, oversized firebombs with larger traps, difficulty 12, and
## a difficulty-20 regular-spawn gate (boss-arena spawn bypasses the gate).
extends Node3D

var _passed: int = 0
var _failed: bool = false


func _ready() -> void:
	print("====================================================")
	print("  STARTING AKIRA BOSS VERIFICATION SUITE")
	print("====================================================")
	_setup_stage()
	await get_tree().physics_frame
	await get_tree().process_frame
	await _part1_registration()
	if _failed:
		return
	await _part2_body_and_scale()
	if _failed:
		return
	await get_tree().physics_frame
	await _part3_backpacks_and_riders()
	if _failed:
		return
	await _part4_firebomb_projectile()
	if _failed:
		return
	await _part5_states_and_ai()
	if _failed:
		return
	await _part6_rider_attack()
	if _failed:
		return
	await _part7_boss_trap()
	if _failed:
		return
	await _part8_grounding()
	if _failed:
		return
	print("====================================================")
	print("  ALL AKIRA BOSS TESTS PASSED (%d checks)" % _passed)
	print("====================================================")
	get_tree().quit(0)


func _fail(msg: String) -> void:
	_failed = true
	printerr("TEST FAILED: ", msg)
	get_tree().quit(1)


func _setup_stage() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	add_child(light)
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0.0, -1.0, 0.0)
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(50.0, 2.0, 50.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)
	add_child(floor_body)


func _boss() -> Character:
	var scene: PackedScene = load("res://Enemy/akira_boss.tscn") as PackedScene
	if scene == null:
		_fail("Could not load res://Enemy/akira_boss.tscn")
		return null
	var boss: Character = scene.instantiate() as Character
	return boss


func _part1_registration() -> void:
	print("\n>>> PART 1: GlobalVars registration, difficulty 12 & spawn gate 20")
	var boss_scene: PackedScene = load("res://Enemy/akira_boss.tscn") as PackedScene
	if boss_scene == null:
		_fail("Could not load akira_boss.tscn")
		return
	var boss_res: EnemyResource = GlobalVars.get_enemy_resource(boss_scene)
	if boss_res == null:
		_fail("GlobalVars.enemies does not contain akira boss resource.")
		return
	if boss_res.difficulty_level != 12:
		_fail("Akira boss difficulty expected 12, got: %d" % boss_res.difficulty_level)
		return
	if boss_res.minimum_spawn_difficulty != 20:
		_fail("Akira boss minimum_spawn_difficulty expected 20, got: %d" % boss_res.minimum_spawn_difficulty)
		return
	print("Boss registered at difficulty 12, regular-spawn gate 20.")
	var wave := WaveObjective.new()
	add_child(wave)
	await get_tree().process_frame
	var pool: Dictionary = wave.build_difficulty_pool(wave._get_default_enemy_resources())
	if not pool.has(12) or not (pool[12] as Array[EnemyResource]).has(boss_res):
		wave.queue_free()
		_fail("WaveObjective ungated difficulty pool tier 12 missing akira boss.")
		return
	print("WaveObjective ungated tier 12 contains akira boss.")
	var gated_early: Dictionary = wave.build_difficulty_pool(wave._get_default_enemy_resources(), 15)
	if gated_early.has(12) and (gated_early[12] as Array[EnemyResource]).has(boss_res):
		wave.queue_free()
		_fail("Akira boss must be gated out of the regular pool below difficulty 20.")
		return
	print("Akira boss gated out of the regular pool at difficulty 15.")
	var gated_open: Dictionary = wave.build_difficulty_pool(wave._get_default_enemy_resources(), 20)
	if not gated_open.has(12) or not (gated_open[12] as Array[EnemyResource]).has(boss_res):
		wave.queue_free()
		_fail("Akira boss must join the regular pool at difficulty 20.")
		return
	wave.queue_free()
	print("Akira boss joins the regular pool at difficulty 20.")
	_passed += 1


func _part2_body_and_scale() -> void:
	print("\n>>> PART 2: Bigger brute body")
	var boss: Character = _boss()
	if boss == null:
		return
	add_child(boss)
	await get_tree().physics_frame
	await get_tree().process_frame
	if not boss.is_in_group("enemy"):
		_fail("Akira boss not in 'enemy' group.")
		return
	if boss.collision_layer != 3:
		_fail("Boss collision_layer is %d, expected 3." % boss.collision_layer)
		boss.queue_free()
		return
	# Same brute model: Large rig present under AnimatedBrute.
	if boss.find_child("AnimatedBrute", true, false) == null:
		_fail("AnimatedBrute (Large rig) missing on boss.")
		boss.queue_free()
		return
	# Bigger than brute: collision capsule taller/wider than base 3.0 / 0.5.
	var cap: CapsuleShape3D = (boss.collision_shape_3d.shape as CapsuleShape3D) if boss.collision_shape_3d != null else null
	if cap == null:
		_fail("Boss CollisionShape3D capsule missing.")
		boss.queue_free()
		return
	var brute_scene: PackedScene = load("res://Enemy/enemy_brute.tscn") as PackedScene
	var brute: Character = (brute_scene.instantiate() as Character) if brute_scene != null else null
	var brute_h: float = 3.0
	var brute_r: float = 0.5
	if brute != null:
		add_child(brute)
		await get_tree().physics_frame
		var bcap: CapsuleShape3D = (brute.collision_shape_3d.shape as CapsuleShape3D) if brute.collision_shape_3d != null else null
		if bcap != null:
			brute_h = bcap.height
			brute_r = bcap.radius
		brute.queue_free()
	if cap.height <= brute_h or cap.radius <= brute_r:
		_fail("Boss capsule (h=%.2f r=%.2f) not bigger than brute (h=%.2f r=%.2f)." % [cap.height, cap.radius, brute_h, brute_r])
		boss.queue_free()
		return
	print("Boss capsule bigger than brute: h=%.2f r=%.2f." % [cap.height, cap.radius])
	# Tougher than brute via relative health comparison (no hardcoded values).
	var brute_hp: float = 100.0
	if brute_scene != null:
		var tmp: Character = brute_scene.instantiate() as Character
		if tmp != null and tmp.attribute_component != null:
			brute_hp = tmp.attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH)
		if tmp != null:
			tmp.queue_free()
	var boss_hp: float = boss.attribute_component.get_current(AttributeComponent.STAT_MAX_HEALTH)
	if boss_hp <= brute_hp:
		_fail("Boss max health (%.1f) should exceed brute (%.1f)." % [boss_hp, brute_hp])
		boss.queue_free()
		return
	print("Boss tougher than brute: %.1f > %.1f." % [boss_hp, brute_hp])
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1


func _part3_backpacks_and_riders() -> void:
	print("\n>>> PART 3: Bone-mounted backpacks, waist riders, hidden legs, melee swords, fire slash VFX")
	var boss: Character = _boss()
	add_child(boss)
	await get_tree().physics_frame
	await get_tree().process_frame
	var mount_names: Array[String] = ["RiderMountLeft", "RiderMountRight"]
	var pack_names: Array[String] = ["BackpackLeft", "BackpackRight"]
	for i: int in range(2):
		# Riders ride bone slots so they follow body animations.
		var mount: BoneAttachment3D = boss.find_child(mount_names[i], true, false) as BoneAttachment3D
		if mount == null:
			_fail("Missing bone mount node: " + mount_names[i])
			boss.queue_free()
			return
		if mount.bone_name != &"spine" and mount.bone_name != &"hips":
			_fail(mount_names[i] + " should attach to a waist bone (spine/hips), got: " + str(mount.bone_name))
			boss.queue_free()
			return
		var pack: Node3D = mount.find_child(pack_names[i], true, false) as Node3D
		if pack == null:
			_fail("Missing backpack node under " + mount_names[i])
			boss.queue_free()
			return
		var prim_count: int = 0
		for child: Node in pack.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi != null and (mi.mesh is BoxMesh or mi.mesh is CylinderMesh or mi.mesh is SphereMesh or mi.mesh is PrismMesh):
				prim_count += 1
		if prim_count <= 0:
			_fail(pack_names[i] + " has no Godot primitive meshes (Box/Cylinder/Sphere).")
			boss.queue_free()
			return
		# Backpacks stay small next to the boss bulk.
		var pack_body: MeshInstance3D = pack.find_child("PackBody", true, false) as MeshInstance3D
		if pack_body == null or not (pack_body.mesh is BoxMesh):
			_fail(pack_names[i] + " PackBody primitive missing.")
			boss.queue_free()
			return
		var pack_size: Vector3 = (pack_body.mesh as BoxMesh).size
		if pack_size.x >= 1.0 or pack_size.y >= 1.0 or pack_size.z >= 1.0:
			_fail(pack_names[i] + " should be small, got size: " + str(pack_size))
			boss.queue_free()
			return
	print("Both backpacks ride waist bones and stay small.")
	var rider_names: Array[String] = ["RiderLeft", "RiderRight"]
	for i: int in range(2):
		var rider: Node3D = boss.find_child(rider_names[i], true, false) as Node3D
		if rider == null:
			_fail("Missing rider node: " + rider_names[i])
			boss.queue_free()
			return
		# Riders sit low at the waist, near the ground, not up at the head.
		var dy: float = rider.global_position.y - boss.global_position.y
		if dy > 1.0 or dy < -1.5:
			_fail(rider_names[i] + " should ride near the waist, y-offset: %.2f" % dy)
			boss.queue_free()
			return
		# Legs hidden: both leg meshes invisible.
		for leg: String in ["Enemy_Medium_LegLeft", "Enemy_Medium_LegRight"]:
			var leg_node: MeshInstance3D = rider.find_child(leg, true, false) as MeshInstance3D
			if leg_node == null:
				_fail(rider_names[i] + " missing leg mesh " + leg)
				boss.queue_free()
				return
			if leg_node.visible:
				_fail(rider_names[i] + " leg mesh " + leg + " should be hidden (visible=false).")
				boss.queue_free()
				return
		# Torso up: head and body still visible above the pack.
		var head: MeshInstance3D = rider.find_child("Enemy_Medium_Head", true, false) as MeshInstance3D
		var body: MeshInstance3D = rider.find_child("Enemy_Medium_Body", true, false) as MeshInstance3D
		if head == null or body == null or not head.visible or not body.visible:
			_fail(rider_names[i] + " torso/head should stay visible above backpack.")
			boss.queue_free()
			return
		# Melee-equal sword: same orange unshaded cylinder the melee enemy
		# carries (child of HitboxArea), no custom box blades/handles left.
		var slot: Node = rider.find_child("WeaponSlot", true, false)
		if slot == null:
			_fail(rider_names[i] + " missing WeaponSlot.")
			boss.queue_free()
			return
		for stale: String in ["SwordBlade", "SwordGuard", "SwordHandle"]:
			if slot.find_child(stale, true, false) != null:
				_fail(rider_names[i] + " still carries custom sword node " + stale + ".")
				boss.queue_free()
				return
		var hitbox: Area3D = rider.find_child("HitboxArea", true, false) as Area3D
		if hitbox == null:
			_fail(rider_names[i] + " missing HitboxArea.")
			boss.queue_free()
			return
		var sword: MeshInstance3D = hitbox.find_child("Sword", true, false) as MeshInstance3D
		if sword == null or not (sword.mesh is CylinderMesh):
			_fail(rider_names[i] + " has no melee-style cylinder Sword under HitboxArea.")
			boss.queue_free()
			return
		var blade_mesh: CylinderMesh = sword.mesh as CylinderMesh
		if not is_equal_approx(blade_mesh.top_radius, 0.1) or not is_equal_approx(blade_mesh.bottom_radius, 0.1) or not is_equal_approx(blade_mesh.height, 2.0):
			_fail(rider_names[i] + " sword must equal the melee cylinder (r=0.1 h=2.0).")
			boss.queue_free()
			return
		var sword_mat: StandardMaterial3D = sword.material_override as StandardMaterial3D
		if sword_mat == null or sword_mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			_fail(rider_names[i] + " sword must use the melee unshaded material.")
			boss.queue_free()
			return
		if not sword_mat.albedo_color.is_equal_approx(Color(1.0, 0.5058824, 0.0, 1.0)):
			_fail(rider_names[i] + " sword must use the melee orange albedo, got: " + str(sword_mat.albedo_color))
			boss.queue_free()
			return
		# Player-like fire slash VFX on the side-slash: SlashVFX quad driven
		# by the slot's Slash attack_mode, plus fire-slash audio on slash.
		var vfx: MeshInstance3D = slot.find_child("SlashVFX", true, false) as MeshInstance3D
		if vfx == null or not (vfx.mesh is QuadMesh):
			_fail(rider_names[i] + " has no player-style SlashVFX quad under WeaponSlot.")
			boss.queue_free()
			return
		if not is_equal_approx((vfx.mesh as QuadMesh).size.x, 4.0) or not is_equal_approx((vfx.mesh as QuadMesh).size.y, 2.0):
			_fail(rider_names[i] + " SlashVFX quad must be 4x2 like the player, got: " + str((vfx.mesh as QuadMesh).size))
			boss.queue_free()
			return
		if vfx.get_script() == null or not str((vfx.get_script() as Resource).resource_path).ends_with("slash_vfx.gd"):
			_fail(rider_names[i] + " SlashVFX must run the player slash_vfx.gd driver.")
			boss.queue_free()
			return
		if int(vfx.get("attack_type")) != 1:
			_fail(rider_names[i] + " SlashVFX attack_type must be Slash (1).")
			boss.queue_free()
			return
		var vfx_mat: ShaderMaterial = vfx.material_override as ShaderMaterial
		if vfx_mat == null or vfx_mat.shader == null or not str((vfx_mat.shader as Resource).resource_path).ends_with("dash.tres"):
			_fail(rider_names[i] + " SlashVFX must use the player dash.tres fire shader.")
			boss.queue_free()
			return
		var audio: AudioStreamPlayer3D = slot.find_child("AttackAudio", true, false) as AudioStreamPlayer3D
		if audio == null or audio.stream == null or not str((audio.stream as Resource).resource_path).ends_with("fire-slash.ogg"):
			_fail(rider_names[i] + " side-slash must play the player fire-slash sound.")
			boss.queue_free()
			return
		if not (slot as WeaponSlot).is_connected(&"slash", Callable(audio, &"play")):
			_fail(rider_names[i] + " WeaponSlot.slash must trigger the fire-slash audio.")
			boss.queue_free()
			return
		# Rider hitbox masks player layer, carries damage, and covers a large zone.
		if hitbox == null or hitbox.collision_mask != 64:
			_fail(rider_names[i] + " HitboxArea must mask player layer 64.")
			boss.queue_free()
			return
		var zone_shape: CollisionShape3D = hitbox.find_child("CollisionShape3D", true, false) as CollisionShape3D
		if zone_shape == null or not (zone_shape.shape is BoxShape3D):
			_fail(rider_names[i] + " rider hitbox zone shape missing.")
			boss.queue_free()
			return
		if (zone_shape.shape as BoxShape3D).size.x < 2.5 or (zone_shape.shape as BoxShape3D).size.z < 2.5:
			_fail(rider_names[i] + " rider hitbox should be a large zone, got: " + str((zone_shape.shape as BoxShape3D).size))
			boss.queue_free()
			return
		# WeaponSlot hitbox wiring drives the animation-enabled sword window.
		var wslot: WeaponSlot = rider.find_child("WeaponSlot", true, false) as WeaponSlot
		if wslot == null or wslot.hitbox != hitbox:
			_fail(rider_names[i] + " WeaponSlot.hitbox must point at its HitboxArea.")
			boss.queue_free()
			return
		var att: AttackComponent = hitbox.get_node_or_null("AttackComponent") as AttackComponent
		if att == null or att.damage <= 0.0:
			_fail(rider_names[i] + " AttackComponent missing or damage <= 0.")
			boss.queue_free()
			return
	print("Riders torso-up with hidden legs, swords, and player-masking hitboxes.")
	var ctrl: Node = boss.get_node_or_null("RiderController")
	if ctrl == null:
		_fail("RiderController node missing on boss.")
		boss.queue_free()
		return
	print("RiderController present.")
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1


func _part4_firebomb_projectile() -> void:
	print("\n>>> PART 4: Bigger, stronger firebombs, larger traps")
	var base_scene: PackedScene = load("res://Enemy/firebomb_projectile.tscn") as PackedScene
	var akira_scene: PackedScene = load("res://Enemy/akira_firebomb_projectile.tscn") as PackedScene
	if base_scene == null or akira_scene == null:
		_fail("Could not load base and akira firebomb scenes.")
		return
	var base_proj: FirebombProjectile = base_scene.instantiate() as FirebombProjectile
	var akira_proj: FirebombProjectile = akira_scene.instantiate() as FirebombProjectile
	add_child(base_proj)
	add_child(akira_proj)
	await get_tree().process_frame
	# Bigger: collision radius and bomb mesh larger than base.
	var base_col: CollisionShape3D = base_proj.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var akira_col: CollisionShape3D = akira_proj.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var base_r: float = (base_col.shape as SphereShape3D).radius if (base_col != null and base_col.shape is SphereShape3D) else 0.0
	var akira_r: float = (akira_col.shape as SphereShape3D).radius if (akira_col != null and akira_col.shape is SphereShape3D) else 0.0
	if akira_r <= base_r:
		_fail("Akira bomb collision (%.2f) not bigger than base (%.2f)." % [akira_r, base_r])
		base_proj.queue_free()
		akira_proj.queue_free()
		return
	var base_mesh: MeshInstance3D = base_proj.get_node_or_null("BombMesh") as MeshInstance3D
	var akira_mesh: MeshInstance3D = akira_proj.get_node_or_null("BombMesh") as MeshInstance3D
	var base_mr: float = (base_mesh.mesh as SphereMesh).radius if (base_mesh != null and base_mesh.mesh is SphereMesh) else 0.0
	var akira_mr: float = (akira_mesh.mesh as SphereMesh).radius if (akira_mesh != null and akira_mesh.mesh is SphereMesh) else 0.0
	if akira_mr <= base_mr:
		_fail("Akira bomb mesh (%.2f) not bigger than base (%.2f)." % [akira_mr, base_mr])
		base_proj.queue_free()
		akira_proj.queue_free()
		return
	# Stronger: direct and trap damage exceed base relatively.
	if akira_proj.damage <= base_proj.damage:
		_fail("Akira bomb damage (%.1f) should exceed base (%.1f)." % [akira_proj.damage, base_proj.damage])
		base_proj.queue_free()
		akira_proj.queue_free()
		return
	if akira_proj.trap_damage <= 0.0:
		_fail("Akira bomb trap_damage should be positive.")
		base_proj.queue_free()
		akira_proj.queue_free()
		return
	# Larger trap area than the firebomber's.
	var base_area: float = base_proj.trap_size.x * base_proj.trap_size.y
	var akira_area: float = akira_proj.trap_size.x * akira_proj.trap_size.y
	if akira_area <= base_area:
		_fail("Akira trap area (%.1f) should exceed base (%.1f)." % [akira_area, base_area])
		base_proj.queue_free()
		akira_proj.queue_free()
		return
	print("Bombs bigger/stronger; trap area %.1f > %.1f." % [akira_area, base_area])
	base_proj.queue_free()
	akira_proj.queue_free()
	await get_tree().process_frame
	# Boss spawner wired to the akira projectile like the firebomber pattern.
	var boss: Character = _boss()
	add_child(boss)
	await get_tree().physics_frame
	var spawner: ProjectileSpawnerComponent = boss.get_node_or_null("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	if spawner == null or spawner.projectile_scene == null:
		_fail("Boss ProjectileSpawnerComponent or projectile_scene missing.")
		boss.queue_free()
		return
	if (spawner.projectile_scene as PackedScene) != akira_scene and (spawner.projectile_scene as Resource).resource_path != "res://Enemy/akira_firebomb_projectile.tscn":
		_fail("Boss spawner should use the akira firebomb scene.")
		boss.queue_free()
		return
	if spawner.spawn_point == null or spawner.character != boss:
		_fail("Boss spawner spawn_point/character wiring invalid.")
		boss.queue_free()
		return
	print("Boss spawner wired to akira firebombs.")
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1


func _part5_states_and_ai() -> void:
	print("\n>>> PART 5: Firebomb state & ranged AI")
	var boss: Character = _boss()
	add_child(boss)
	await get_tree().physics_frame
	var fire_state: CharacterAttack = boss.state_machine.get_node_or_null("EnemyFirebomb") as CharacterAttack
	if fire_state == null:
		_fail("StateMachine missing EnemyFirebomb.")
		boss.queue_free()
		return
	var spawner: ProjectileSpawnerComponent = boss.get_node_or_null("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	# EnemyFirebomb uses the boss firebomb script (duck-typed to avoid class-cache ordering).
	if fire_state.get_script() == null or not (fire_state.get_script() as Script).resource_path.ends_with("akira_boss_firebomb_attack.gd"):
		_fail("EnemyFirebomb should use akira_boss_firebomb_attack.gd.")
		boss.queue_free()
		return
	if fire_state.get("projectile_spawner") == null and spawner != null:
		_fail("EnemyFirebomb spawner export should point at ProjectileSpawnerComponent.")
		boss.queue_free()
		return
	var ai_fire: AIState = boss.ai_state_machine.get_node_or_null("AIFirebomb") as AIState
	if ai_fire == null:
		_fail("AIStateMachine missing AIFirebomb.")
		boss.queue_free()
		return
	if not ("trigger_range" in ai_fire and "min_range" in ai_fire):
		_fail("AIFirebomb should expose trigger_range and min_range.")
		boss.queue_free()
		return
	if float(ai_fire.get("trigger_range")) <= float(ai_fire.get("min_range")):
		_fail("AIFirebomb trigger_range should exceed min_range (ranged band).")
		boss.queue_free()
		return
	print("EnemyFirebomb + ranged AIFirebomb band verified.")
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1


func _part6_rider_attack() -> void:
	print("\n>>> PART 6: Riders side-slash a large zone when player is close")
	var player_scene: PackedScene = load("res://Player/player.tscn") as PackedScene
	var boss: Character = _boss()
	if player_scene == null or boss == null:
		_fail("Could not load player and boss scenes.")
		return
	var player: Character = player_scene.instantiate() as Character
	add_child(boss)
	add_child(player)
	# Spawn off-center with feet exactly on the floor (no deep penetration).
	boss.global_position = Vector3(6.0, 2.5, 0.0)
	player.global_position = Vector3(6.0, 1.0, 6.0)
	# Freeze boss AI so only the riders act (deterministic health readings).
	boss.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	boss.move_direction = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().process_frame
	var ctrl: Node = boss.get_node_or_null("RiderController")
	if ctrl == null or not ctrl.has_method("force_rider_attack"):
		_fail("RiderController script missing.")
		player.queue_free()
		boss.queue_free()
		return
	# Settle spawn fall/land, then hold the body still.
	for frame: int in range(60):
		await get_tree().physics_frame
	boss.state_machine.request_state("EnemyMove")
	boss.move_direction = Vector3.ZERO
	var left_root: Node3D = ctrl.get("left_rider_root") as Node3D
	if left_root == null:
		_fail("RiderController left_rider_root missing.")
		player.queue_free()
		boss.queue_free()
		return
	# Riders idle in WalkSpace at rest (never stuck T-posing on Start).
	var left_tree: AnimationTree = ctrl.get("left_rider_tree") as AnimationTree
	if left_tree == null:
		_fail("RiderController left_rider_tree missing.")
		player.queue_free()
		boss.queue_free()
		return
	var idled: bool = false
	for frame: int in range(30):
		await get_tree().physics_frame
		var playback: AnimationNodeStateMachinePlayback = left_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback != null and playback.get_current_node() == &"WalkSpace":
			idled = true
			break
	if not idled:
		_fail("Rider should idle in WalkSpace at rest.")
		player.queue_free()
		boss.queue_free()
		return
	print("Riders idle in WalkSpace at rest.")
	# Park the player in front of the left rider's chest, inside the slash zone.
	var rider_fwd: Vector3 = -left_root.global_transform.basis.z
	rider_fwd.y = 0.0
	if rider_fwd.length_squared() < 0.01:
		rider_fwd = Vector3(0.0, 0.0, 1.0)
	rider_fwd = rider_fwd.normalized()
	player.global_position = left_root.global_position + rider_fwd * 1.1 + Vector3(0.0, 0.9, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rslot: WeaponSlot = left_root.find_child("WeaponSlot", true, false) as WeaponSlot
	if rslot == null:
		_fail("Rider WeaponSlot missing for animation window check.")
		player.queue_free()
		boss.queue_free()
		return
	# First forced side-slash must open its hitbox window and land.
	player.global_position = left_root.global_position + rider_fwd * 1.1 + Vector3(0.0, 0.9, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp_before_swing: float = player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	ctrl.call("force_rider_attack", true)
	if bool(ctrl.call("is_rider_ready", true)):
		_fail("Rider cooldown should start after forced swing.")
		player.queue_free()
		boss.queue_free()
		return
	# Fire slash VFX must show and sweep while the swing window is open.
	var vfx: MeshInstance3D = rslot.find_child("SlashVFX", true, false) as MeshInstance3D
	if vfx == null:
		_fail("Rider SlashVFX missing at swing time.")
		player.queue_free()
		boss.queue_free()
		return
	var vfx_shown: bool = false
	var min_threshold: float = 1.0
	for frame: int in range(90):
		await get_tree().physics_frame
		if rslot.enabled:
			var vfx_mat: ShaderMaterial = vfx.material_override as ShaderMaterial
			if vfx.visible:
				vfx_shown = true
			if vfx_mat != null:
				min_threshold = minf(min_threshold, float(vfx_mat.get_shader_parameter("Threshold")))
		elif vfx_shown:
			break
	if not vfx_shown:
		_fail("Rider fire SlashVFX never became visible during the swing window.")
		player.queue_free()
		boss.queue_free()
		return
	if min_threshold >= 1.0:
		_fail("Rider fire SlashVFX Threshold never swept below 1.0.")
		player.queue_free()
		boss.queue_free()
		return
	print("Rider fire SlashVFX fired and swept to %.2f." % min_threshold)
	# The swing may have landed while watching the VFX, so baseline from
	# before the swing and allow a short grace for hit latency.
	var first_landed: bool = player.attribute_component.get_current(AttributeComponent.POOL_HEALTH) < hp_before_swing
	for frame: int in range(15):
		if first_landed:
			break
		await get_tree().physics_frame
		if player.attribute_component.get_current(AttributeComponent.POOL_HEALTH) < hp_before_swing:
			first_landed = true
	if not first_landed:
		_fail("First rider side-slash missed the player in its zone.")
		player.queue_free()
		boss.queue_free()
		return
	var hp_after_first: float = player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	print("First side-slash landed, player HP: %.1f." % hp_after_first)
	# Let the swing finish and the cooldown elapse, then swing again: stale hit
	# exceptions must not protect the player, so the second slash lands too.
	for frame: int in range(210):
		await get_tree().physics_frame
	# Hits knock the player back, so re-park inside the zone before swinging.
	player.global_position = left_root.global_position + rider_fwd * 1.1 + Vector3(0.0, 0.9, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	ctrl.call("force_rider_attack", true)
	if not await _wait_rider_hit(player, rslot, 150):
		_fail("Second rider side-slash missed (stale hit exceptions?).")
		player.queue_free()
		boss.queue_free()
		return
	var hp_after_second: float = player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	if hp_after_second >= hp_after_first:
		_fail("Second side-slash dealt no damage.")
		player.queue_free()
		boss.queue_free()
		return
	print("Second side-slash landed: %.1f -> %.1f." % [hp_after_first, hp_after_second])
	player.queue_free()
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1


## Waits for the rider's animation-driven hitbox window to damage the player.
## Returns true once the player's health drops, false on timeout frames.
func _wait_rider_hit(player: Character, rslot: WeaponSlot, timeout_frames: int) -> bool:
	var hp_before: float = player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	for frame: int in range(timeout_frames):
		await get_tree().physics_frame
		if rslot.enabled:
			await get_tree().physics_frame
			await get_tree().physics_frame
		if player.attribute_component.get_current(AttributeComponent.POOL_HEALTH) < hp_before:
			return true
	return false


func _part7_boss_trap() -> void:
	print("\n>>> PART 7: Boss bomb spawns larger trap")
	var akira_scene: PackedScene = load("res://Enemy/akira_firebomb_projectile.tscn") as PackedScene
	if akira_scene == null:
		_fail("Could not load akira projectile.")
		return
	var proj: FirebombProjectile = akira_scene.instantiate() as FirebombProjectile
	add_child(proj)
	proj.global_position = Vector3(5.0, 1.5, 5.0)
	proj.initialize_trajectory(Vector3(5.0, 0.0, 8.0))
	var trap: FireTrap = null
	for frame: int in range(280):
		await get_tree().physics_frame
		for child: Node in get_children():
			if child is FireTrap and not child.is_queued_for_deletion():
				trap = child as FireTrap
				break
		if trap != null:
			break
	if trap == null:
		_fail("Akira firebomb did not spawn a FireTrap on ground impact.")
		return
	var base_scene: PackedScene = load("res://Enemy/firebomb_projectile.tscn") as PackedScene
	var base_proj: FirebombProjectile = base_scene.instantiate() as FirebombProjectile
	var base_area: float = base_proj.trap_size.x * base_proj.trap_size.y
	base_proj.queue_free()
	var got_area: float = trap.trap_size.x * trap.trap_size.y
	if got_area <= base_area:
		_fail("Spawned boss trap area (%.1f) should exceed base (%.1f)." % [got_area, base_area])
		trap.queue_free()
		return
	print("Boss trap spawned larger: area %.1f > base %.1f at %s." % [got_area, base_area, str(trap.global_position)])
	trap.queue_free()
	await get_tree().process_frame
	_passed += 1


## Lowest boot-sole height (large-rig leg meshes only) for grounding checks.
func _boss_sole_level(boss: Character) -> float:
	var best: float = INF
	var stack: Array[Node] = [boss]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D and (cur.name == &"Enemy_Large_LegLeft" or cur.name == &"Enemy_Large_LegRight"):
			var mi: MeshInstance3D = cur as MeshInstance3D
			var box: AABB = mi.global_transform * mi.get_aabb()
			best = minf(best, box.position.y)
		for child: Node in cur.get_children():
			stack.push_back(child)
	return best


func _part8_grounding() -> void:
	print("\n>>> PART 8: Grounded stance (capsule fit, no float/sink)")
	var boss: Character = _boss()
	if boss == null:
		return
	boss.position = Vector3(0.0, 3.0, 0.0)
	add_child(boss)
	if boss.ai_state_machine != null:
		boss.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	for frame: int in range(60):
		await get_tree().physics_frame
	if not boss.is_on_floor():
		_fail("Boss should rest on the floor after settling.")
		boss.queue_free()
		return
	if boss.collision_shape_3d == null or not (boss.collision_shape_3d.shape is CapsuleShape3D):
		_fail("Boss CollisionShape3D capsule missing.")
		boss.queue_free()
		return
	var cap: CapsuleShape3D = boss.collision_shape_3d.shape as CapsuleShape3D
	var rest_height: float = cap.height * 0.5 - boss.collision_shape_3d.position.y
	if absf(boss.global_position.y - rest_height) > 0.08:
		_fail("Boss origin (%.3f) should rest at capsule half-height (%.3f)." % [boss.global_position.y, rest_height])
		boss.queue_free()
		return
	var sole: float = _boss_sole_level(boss)
	if absf(sole) > 0.08:
		_fail("Boss boot soles (%.3f) should touch the floor, not float or sink." % sole)
		boss.queue_free()
		return
	print("Boss grounded: origin %.3f, soles %.3f." % [boss.global_position.y, sole])
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1
