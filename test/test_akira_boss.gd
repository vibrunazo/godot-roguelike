## Automated verification suite for the Akira boss.
## Verifies brute-based bigger body, grounded collision fit (no float/sink),
## mesh scale preserved while turning, 100% fire immunity (no damage, stun,
## or burn from his own fire traps), backpack riders with hidden legs and
## melee-equal swords with player-like fire slash VFX, oversized firebombs
## with larger traps, difficulty 12, and a difficulty-20 regular-spawn gate
## (boss-arena spawn bypasses the gate).
extends Node3D

## Ankle joint height above the boot sole for the 1.32-scaled large rig,
## from bind-pose geometry (ankle -1.60, sole -1.98). Rigid boots keep this
## offset in every pose, so live soles = live ankle - FOOT_HEIGHT.
const FOOT_HEIGHT: float = 0.38

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
	await _part9_fire_immunity()
	if _failed:
		return
	await _part10_scale_preserved()
	if _failed:
		return
	await _part11_ability_hyper_armor()
	if _failed:
		return
	await _part12_gameplay_tags_and_gating()
	if _failed:
		return
	await _part13_throw_riders_ability()
	if _failed:
		return
	await _part14_summon_helpers_ability()
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


## Live ankle height (foot-bone global) for the large rig, relative to the
## body origin. Bones track the posed skeleton; unposed mesh bounds only ever
## report the bind pose, so they must not be used for grounding checks. Uses
## the direct skeleton path so waist-rider feet never contaminate the reading.
func _boss_ankle_level(boss: Character) -> float:
	var skel: Skeleton3D = boss.get_node_or_null("AnimationAnchor/AnimatedBrute/Enemy_Large/Rig_Large/Skeleton3D") as Skeleton3D
	if skel == null:
		return INF
	var foot: BoneAttachment3D = skel.get_node_or_null("LeftFootBone") as BoneAttachment3D
	if foot == null:
		return INF
	return foot.global_position.y - boss.global_position.y


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
	var ankle_total: float = 0.0
	var ankle_frames: int = 0
	for frame: int in range(45):
		await get_tree().physics_frame
		var ankle: float = _boss_ankle_level(boss)
		if ankle < INF:
			ankle_total += ankle
			ankle_frames += 1
	if ankle_frames <= 0:
		_fail("Boss large-rig foot bone missing.")
		boss.queue_free()
		return
	var sole_est: float = boss.global_position.y + ankle_total / float(ankle_frames) - FOOT_HEIGHT
	if absf(sole_est) > 0.15:
		_fail("Boss boot soles (est %.3f) should touch the floor, not float or sink." % sole_est)
		boss.queue_free()
		return
	print("Boss grounded: origin %.3f, soles est %.3f." % [boss.global_position.y, sole_est])
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1


## Waits up to timeout_frames physics frames for a body state. Returns true
## once the machine rests in the named state (used to clear landing stun).
func _wait_body_state(body: Character, state_name: String, timeout_frames: int) -> bool:
	for frame: int in range(timeout_frames):
		await get_tree().physics_frame
		if body == null or not is_instance_valid(body):
			return false
		if body.state_machine != null and body.state_machine.state != null and body.state_machine.state.name == state_name:
			return true
	return false


func _part9_fire_immunity() -> void:
	print("\n>>> PART 9: Immune to fire (no damage, stun, or burn)")
	var boss: Character = _boss()
	if boss == null:
		return
	add_child(boss)
	await get_tree().physics_frame
	await get_tree().process_frame
	if not await _wait_body_state(boss, "EnemyMove", 90):
		_fail("Boss should settle into EnemyMove after landing.")
		boss.queue_free()
		return
	var attrs: AttributeComponent = boss.attribute_component
	if attrs == null:
		_fail("Boss AttributeComponent missing.")
		boss.queue_free()
		return
	if not is_equal_approx(attrs.get_current(AttributeComponent.STAT_FIRE_RESISTANCE), 1.0):
		_fail("Boss fire resistance should be 1.0 (immune), got: %.2f" % attrs.get_current(AttributeComponent.STAT_FIRE_RESISTANCE))
		boss.queue_free()
		return
	print("Boss fire resistance reads 1.0.")
	var hurtbox: Hurtbox = boss.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox == null:
		_fail("Boss Hurtbox missing.")
		boss.queue_free()
		return
	var struck: Array[float] = []
	hurtbox.struck.connect(func(damage: float) -> void: struck.append(damage))
	var full_health: float = attrs.get_current(AttributeComponent.POOL_HEALTH)
	# Fire hits are fully ignored: no damage, no hit reaction, no stun state.
	if hurtbox.receive_hit(10.0, Vector3.ZERO, &"fire"):
		_fail("Fire receive_hit on the immune boss should return false.")
		boss.queue_free()
		return
	if not is_equal_approx(attrs.get_current(AttributeComponent.POOL_HEALTH), full_health):
		_fail("Fire hit should not damage the immune boss.")
		boss.queue_free()
		return
	if not struck.is_empty():
		_fail("Fire hit should not emit struck on the immune boss.")
		boss.queue_free()
		return
	if boss.state_machine != null and boss.state_machine.state != null and boss.state_machine.state.name == "EnemyStun":
		_fail("Fire hit should not stun the immune boss.")
		boss.queue_free()
		return
	print("Fire hit ignored: health steady, no struck, no stun.")
	# Physical hits still land relatively, with exactly one hit reaction.
	if not hurtbox.receive_hit(10.0, Vector3.ZERO, &"physical"):
		_fail("Physical receive_hit on the boss should return true.")
		boss.queue_free()
		return
	if not is_equal_approx(attrs.get_current(AttributeComponent.POOL_HEALTH), full_health - 10.0):
		_fail("Physical hit should damage the boss relatively.")
		boss.queue_free()
		return
	if struck.size() != 1:
		_fail("Physical hit should emit struck exactly once, got: %d" % struck.size())
		boss.queue_free()
		return
	print("Physical hit lands relatively with one struck.")
	# The shared burn is rejected while immune...
	var burn: GameplayEffect = load("res://Components/effect_fire_burn.tres") as GameplayEffect
	if burn == null:
		_fail("Could not load effect_fire_burn.tres.")
		boss.queue_free()
		return
	if attrs.apply_effect(burn) != &"":
		_fail("Burn effect should be rejected on the immune boss.")
		boss.queue_free()
		return
	# ...and burns once the attribute is lowered, proving the stat drives it.
	attrs.set_base(AttributeComponent.STAT_FIRE_RESISTANCE, 0.0)
	if attrs.apply_effect(burn) == &"":
		_fail("Burn effect should apply once fire resistance is lowered.")
		boss.queue_free()
		return
	var burning_from: float = attrs.get_current(AttributeComponent.POOL_HEALTH)
	for frame: int in range(65):
		await get_tree().physics_frame
	if not (attrs.get_current(AttributeComponent.POOL_HEALTH) < burning_from):
		_fail("Accepted burn should tick damage over time.")
		boss.queue_free()
		return
	print("Burn rejected while immune, ticks once resistance is lowered.")
	boss.queue_free()
	await get_tree().process_frame
	# End to end: a live fire trap harms a normal enemy but not the boss.
	var fresh: Character = _boss()
	if fresh == null:
		return
	add_child(fresh)
	fresh.position = Vector3(0.0, 3.0, 0.0)
	if fresh.ai_state_machine != null:
		fresh.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	var melee_scene: PackedScene = load("res://Enemy/melee_enemy.tscn") as PackedScene
	if melee_scene == null:
		_fail("Could not load melee_enemy.tscn.")
		fresh.queue_free()
		return
	var control: Character = melee_scene.instantiate() as Character
	add_child(control)
	control.position = Vector3(2.0, 3.0, 0.0)
	if control.ai_state_machine != null:
		control.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	var trap_scene: PackedScene = load("res://Hazards/fire_trap.tscn") as PackedScene
	if trap_scene == null:
		_fail("Could not load fire_trap.tscn.")
		fresh.queue_free()
		control.queue_free()
		return
	var trap: FireTrap = trap_scene.instantiate() as FireTrap
	add_child(trap)
	await get_tree().physics_frame
	trap.set_trap_size(Vector2(4.0, 2.0))
	trap.damage_interval = 0.1
	trap.position = Vector3(1.0, 1.0, 0.0)
	var fresh_struck: Array[float] = []
	var fresh_hurtbox: Hurtbox = fresh.get_node_or_null("Hurtbox") as Hurtbox
	if fresh_hurtbox != null:
		fresh_hurtbox.struck.connect(func(damage: float) -> void: fresh_struck.append(damage))
	if not await _wait_body_state(fresh, "EnemyMove", 120):
		_fail("Boss should settle into EnemyMove before trap exposure.")
		fresh.queue_free()
		control.queue_free()
		trap.queue_free()
		return
	var boss_full: float = fresh.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var control_full: float = control.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	fresh_struck.clear()
	for frame: int in range(30):
		await get_tree().physics_frame
	if not is_equal_approx(fresh.attribute_component.get_current(AttributeComponent.POOL_HEALTH), boss_full):
		_fail("Live fire trap should not damage the immune boss.")
		fresh.queue_free()
		control.queue_free()
		trap.queue_free()
		return
	if not fresh_struck.is_empty():
		_fail("Live fire trap should not trigger hit reactions on the immune boss.")
		fresh.queue_free()
		control.queue_free()
		trap.queue_free()
		return
	if fresh.state_machine != null and fresh.state_machine.state != null and fresh.state_machine.state.name == "EnemyStun":
		_fail("Live fire trap should not stun the immune boss.")
		fresh.queue_free()
		control.queue_free()
		trap.queue_free()
		return
	if not (control.attribute_component.get_current(AttributeComponent.POOL_HEALTH) < control_full):
		_fail("Live fire trap should damage the non-immune control enemy.")
		fresh.queue_free()
		control.queue_free()
		trap.queue_free()
		return
	print("Live fire trap: boss unharmed and unstunned, control burned.")
	fresh.queue_free()
	control.queue_free()
	trap.queue_free()
	await get_tree().process_frame
	_passed += 1


func _part10_scale_preserved() -> void:
	print("\n>>> PART 10: Mesh scale preserved while turning")
	var boss: Character = _boss()
	if boss == null:
		return
	add_child(boss)
	if boss.ai_state_machine != null:
		boss.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame
	await get_tree().process_frame
	var anchor: Node3D = boss.get_node_or_null("AnimationAnchor") as Node3D
	if anchor == null:
		_fail("Boss AnimationAnchor missing.")
		boss.queue_free()
		return
	var healthy_scale: Vector3 = anchor.scale
	if healthy_scale.is_equal_approx(Vector3.ONE):
		_fail("Boss anchor should start scaled up, got: %s" % str(healthy_scale))
		boss.queue_free()
		return
	var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3(1.0, 0.0, 1.0).normalized()]
	for dir: Vector3 in dirs:
		for frame: int in range(12):
			boss.look_toward_direction(dir, 1.0 / 60.0)
			await get_tree().physics_frame
		boss.look_at_target(boss.global_position + dir * 5.0, 1.0 / 60.0)
		if not anchor.scale.is_equal_approx(healthy_scale):
			_fail("Turning should preserve mesh scale (got %s, want %s)." % [str(anchor.scale), str(healthy_scale)])
			boss.queue_free()
			return
	print("Mesh scale preserved while turning: %s." % str(anchor.scale))
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1


func _part11_ability_hyper_armor() -> void:
	print("\n>>> PART 11: Punch & firebomb share slam hyper-armor and stun cancel")
	var boss: Character = _boss()
	if boss == null:
		return
	add_child(boss)
	await get_tree().physics_frame
	await get_tree().process_frame
	var body_sm: StateMachine = boss.state_machine
	var mind: AIStateMachine = boss.ai_state_machine
	if body_sm == null or mind == null:
		_fail("Boss StateMachine or AIStateMachine missing.")
		boss.queue_free()
		return
	# Freeze the mind so scripted body states are never stolen mid-check; the
	# stun-cancel path below is driven through order_attack directly.
	mind.process_mode = Node.PROCESS_MODE_DISABLED
	var slam: CharacterAttack = body_sm.get_node_or_null("EnemyAttack") as CharacterAttack
	var punch: CharacterAttack = body_sm.get_node_or_null("EnemyPunch") as CharacterAttack
	var firebomb: CharacterAttack = body_sm.get_node_or_null("EnemyFirebomb") as CharacterAttack
	if slam == null or punch == null or firebomb == null:
		_fail("Boss StateMachine missing an ability state (slam/punch/firebomb).")
		boss.queue_free()
		return
	if not slam.uninterruptable:
		_fail("Boss slam (EnemyAttack) should stay uninterruptable.")
		boss.queue_free()
		return
	if not punch.uninterruptable:
		_fail("Boss punch (EnemyPunch) should be uninterruptable like the slam.")
		boss.queue_free()
		return
	if not firebomb.uninterruptable:
		_fail("Boss firebomb (EnemyFirebomb) should be uninterruptable like the slam.")
		boss.queue_free()
		return
	print("Slam, punch, and firebomb all uninterruptable.")
	var ai_slam: AIConditionalAttack = mind.get_node_or_null("AISlam") as AIConditionalAttack
	var ai_firebomb: AIConditionalAttack = mind.get_node_or_null("AIFirebomb") as AIConditionalAttack
	var pursue: AIPursue = mind.get_node_or_null("AIPursue") as AIPursue
	if ai_slam == null or ai_firebomb == null or pursue == null:
		_fail("Boss AIStateMachine missing an ability mind state.")
		boss.queue_free()
		return
	if pursue.attack_state_name != "EnemyPunch":
		_fail("Boss AIPursue should order EnemyPunch, got: " + pursue.attack_state_name)
		boss.queue_free()
		return
	if not ai_slam.can_break_stun:
		_fail("AISlam should keep breaking stun.")
		boss.queue_free()
		return
	if not ai_firebomb.can_break_stun:
		_fail("AIFirebomb should break stun like AISlam.")
		boss.queue_free()
		return
	if not pursue.can_break_stun:
		_fail("Boss AIPursue should break stun into punch like AISlam.")
		boss.queue_free()
		return
	print("Slam, firebomb, and punch orders all break stun.")
	# Hits during any ability damage the boss without stunning him out of it.
	var hurtbox: Hurtbox = boss.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox == null:
		_fail("Boss Hurtbox missing.")
		boss.queue_free()
		return
	var abilities: Array[String] = ["EnemyAttack", "EnemyPunch", "EnemyFirebomb"]
	for i: int in range(abilities.size()):
		var ability: String = abilities[i]
		body_sm.request_state(ability)
		await get_tree().physics_frame
		await get_tree().physics_frame
		if body_sm.state == null or body_sm.state.name != ability:
			_fail("Boss could not enter %s for hyper-armor check." % ability)
			boss.queue_free()
			return
		var hp_before: float = boss.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
		if not hurtbox.receive_hit(10.0, Vector3.ZERO):
			_fail("Hit should land during %s hyper-armor." % ability)
			boss.queue_free()
			return
		await get_tree().physics_frame
		await get_tree().process_frame
		if body_sm.state == null or body_sm.state.name != ability:
			var stayed: String = body_sm.state.name if body_sm.state != null else "null"
			_fail("Boss was stunned out of %s (hyper-armor broken, now %s)." % [ability, stayed])
			boss.queue_free()
			return
		if not is_equal_approx(boss.attribute_component.get_current(AttributeComponent.POOL_HEALTH), hp_before - 10.0):
			_fail("Boss should still take damage during %s hyper-armor." % ability)
			boss.queue_free()
			return
	print("Hits during slam, punch, and firebomb damage without stunning.")
	# Each ability cancels a live stun through the real order path, using the
	# mind state's own configured flag (not a hardcoded true).
	var cancel_names: Array[String] = ["EnemyAttack", "EnemyPunch", "EnemyFirebomb"]
	var cancel_flags: Array[bool] = [ai_slam.can_break_stun, pursue.can_break_stun, ai_firebomb.can_break_stun]
	for i: int in range(cancel_names.size()):
		var target_ability: String = cancel_names[i]
		body_sm.request_state("EnemyStun")
		await get_tree().physics_frame
		await get_tree().physics_frame
		if body_sm.state == null or body_sm.state.name != "EnemyStun":
			_fail("Boss could not enter EnemyStun for cancel check.")
			boss.queue_free()
			return
		if not mind.order_attack(target_ability, cancel_flags[i]):
			_fail("Boss stun should cancel into %s." % target_ability)
			boss.queue_free()
			return
		await get_tree().physics_frame
		if body_sm.state == null or body_sm.state.name != target_ability:
			var landed: String = body_sm.state.name if body_sm.state != null else "null"
			_fail("Boss did not enter %s after stun cancel (now %s)." % [target_ability, landed])
			boss.queue_free()
			return
	print("Stun cancels into slam, punch, and firebomb through order_attack.")
	boss.queue_free()
	await get_tree().process_frame
	# Live end to end: a stunned boss with the player in punch range breaks
	# out into an ability on its own (mind enabled this time).
	var player_scene: PackedScene = load("res://Player/player.tscn") as PackedScene
	var live: Character = _boss()
	var player: Character = (player_scene.instantiate() as Character) if player_scene != null else null
	if live == null or player == null:
		_fail("Could not spawn boss and player for live cancel check.")
		if live != null:
			live.queue_free()
		if player != null:
			player.queue_free()
		return
	add_child(live)
	add_child(player)
	live.global_position = Vector3(0.0, 2.5, 0.0)
	player.global_position = Vector3(2.0, 1.0, 0.0)
	if not await _wait_body_state(live, "EnemyMove", 120):
		_fail("Live boss should settle into EnemyMove before stun cancel.")
		player.queue_free()
		live.queue_free()
		return
	var live_mind: AIStateMachine = live.ai_state_machine
	if live_mind == null or live_mind.state == null or live_mind.state.name != "AIPursue":
		_fail("Live boss mind should wait in AIPursue for the cancel check.")
		player.queue_free()
		live.queue_free()
		return
	live.state_machine.request_state("EnemyStun")
	var broke_out: bool = false
	for frame: int in range(300):
		await get_tree().physics_frame
		if live.state_machine == null or live.state_machine.state == null:
			break
		var now: String = live.state_machine.state.name
		if now == "EnemyAttack" or now == "EnemyPunch" or now == "EnemyFirebomb":
			broke_out = true
			break
		if now == "EnemyMove":
			# Stun expired before an order landed: re-apply so the observed
			# ability still has to break out of a live stun.
			live.state_machine.request_state("EnemyStun")
	if not broke_out:
		_fail("Stunned live boss never broke out into an ability.")
		player.queue_free()
		live.queue_free()
		return
	print("Stunned live boss broke out into %s on its own." % live.state_machine.state.name)
	player.queue_free()
	live.queue_free()
	await get_tree().process_frame
	_passed += 1


func _part12_gameplay_tags_and_gating() -> void:
	print("\n>>> PART 12: Gameplay tags, querying, signals, and attack gating")
	var boss: Character = _boss()
	if boss == null:
		_fail("Could not spawn boss for gameplay tags test.")
		return
	add_child(boss)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var attr: AttributeComponent = boss.attribute_component
	if attr == null:
		_fail("Boss AttributeComponent missing.")
		boss.queue_free()
		return

	# 1. Starts with has_riders tag
	if not attr.has_tag(&"has_riders"):
		_fail("Boss should start with 'has_riders' tag from initial_effects.")
		boss.queue_free()
		return
	if not boss.has_tag(&"has_riders"):
		_fail("Character.has_tag('has_riders') should return true.")
		boss.queue_free()
		return
	var req_tags: Array[StringName] = [&"has_riders"]
	if not boss.has_all_tags(req_tags):
		_fail("Character.has_all_tags([&'has_riders']) should return true.")
		boss.queue_free()
		return
	var test_any: Array[StringName] = [&"has_riders", &"nonexistent"]
	if not boss.has_any_tag(test_any):
		_fail("Character.has_any_tag should return true.")
		boss.queue_free()
		return

	# 2. Tag signals
	var signal_data: Array[StringName] = [&"", &""]
	attr.tag_added.connect(func(tag: StringName) -> void: signal_data[0] = tag)
	attr.tag_removed.connect(func(tag: StringName) -> void: signal_data[1] = tag)

	attr.add_tag(&"custom_test_tag")
	if signal_data[0] != &"custom_test_tag":
		_fail("tag_added signal was not emitted with the added tag.")
		boss.queue_free()
		return
	if not attr.has_tag(&"custom_test_tag"):
		_fail("Custom test tag was not added.")
		boss.queue_free()
		return

	attr.remove_tag(&"custom_test_tag")
	if signal_data[1] != &"custom_test_tag":
		_fail("tag_removed signal was not emitted with the removed tag.")
		boss.queue_free()
		return
	if attr.has_tag(&"custom_test_tag"):
		_fail("Custom test tag was not removed.")
		boss.queue_free()
		return

	# 3. Attack state gating
	var throw_attack: CharacterAttack = boss.state_machine.get_node_or_null("EnemyThrowRiders") as CharacterAttack
	var summon_attack: CharacterAttack = boss.state_machine.get_node_or_null("EnemySummonHelpers") as CharacterAttack
	if throw_attack == null or summon_attack == null:
		_fail("EnemyThrowRiders or EnemySummonHelpers state missing.")
		boss.queue_free()
		return

	throw_attack.cooldown_timer = 0.0
	summon_attack.cooldown_timer = 0.0

	# With has_riders: throw is allowed, summon is blocked
	if not throw_attack.can_activate():
		_fail("EnemyThrowRiders should be activatable when boss has 'has_riders'.")
		boss.queue_free()
		return
	if summon_attack.can_activate():
		_fail("EnemySummonHelpers should be blocked when boss has 'has_riders'.")
		boss.queue_free()
		return

	# Remove has_riders: throw is blocked, summon is enabled
	attr.remove_tag(&"has_riders")
	await get_tree().physics_frame

	if throw_attack.can_activate():
		_fail("EnemyThrowRiders should be blocked when boss lacks 'has_riders'.")
		boss.queue_free()
		return

	# Verify start_cooldown_on_enabled triggered on summon_attack
	if summon_attack.start_cooldown_on_enabled:
		if summon_attack.cooldown_timer <= 0.0:
			_fail("EnemySummonHelpers should start cooldown timer when enabled by tag transition.")
			boss.queue_free()
			return

	summon_attack.cooldown_timer = 0.0
	if not summon_attack.can_activate():
		_fail("EnemySummonHelpers should be activatable once cooldown is 0 and 'has_riders' is absent.")
		boss.queue_free()
		return

	# Re-add has_riders
	attr.add_tag(&"has_riders")
	if not throw_attack.can_activate():
		_fail("EnemyThrowRiders should be re-enabled when 'has_riders' is re-added.")
		boss.queue_free()
		return
	if summon_attack.can_activate():
		_fail("EnemySummonHelpers should be blocked again when 'has_riders' is re-added.")
		boss.queue_free()
		return

	print("Gameplay tags queried, signals emitted, and attacks gated properly.")
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1


func _part13_throw_riders_ability() -> void:
	print("\n>>> PART 13: Throw riders ability, minion spawn, and rider detachment")
	var boss: Character = _boss()
	if boss == null:
		_fail("Could not spawn boss for throw riders test.")
		return
	add_child(boss)
	boss.global_position = Vector3(0.0, 1.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var throw_attack: AkiraBossThrowRidersAttack = boss.state_machine.get_node_or_null("EnemyThrowRiders") as AkiraBossThrowRidersAttack
	if throw_attack == null:
		_fail("EnemyThrowRiders is not an AkiraBossThrowRidersAttack instance.")
		boss.queue_free()
		return

	# Check exports and configuration
	if throw_attack.cooldown != 30.0:
		_fail("EnemyThrowRiders cooldown expected 30.0, got: %f" % throw_attack.cooldown)
		boss.queue_free()
		return
	if throw_attack.starting_cooldown != 30.0:
		_fail("EnemyThrowRiders starting_cooldown expected 30.0, got: %f" % throw_attack.starting_cooldown)
		boss.queue_free()
		return
	if throw_attack.attack_animation_name != "DualWieldSlash":
		_fail("EnemyThrowRiders animation expected 'DualWieldSlash', got: %s" % throw_attack.attack_animation_name)
		boss.queue_free()
		return
	if not throw_attack.uninterruptable:
		_fail("EnemyThrowRiders should be uninterruptable.")
		boss.queue_free()
		return
	if not throw_attack.required_tags.has(&"has_riders"):
		_fail("EnemyThrowRiders should require 'has_riders' tag.")
		boss.queue_free()
		return

	# AI state check
	var ai_throw: AIConditionalAttack = boss.ai_state_machine.get_node_or_null("AIThrowRiders") as AIConditionalAttack
	if ai_throw == null:
		_fail("AIThrowRiders node missing on AIStateMachine.")
		boss.queue_free()
		return
	if ai_throw.attack_state_name != "EnemyThrowRiders":
		_fail("AIThrowRiders attack_state_name expected 'EnemyThrowRiders', got: %s" % ai_throw.attack_state_name)
		boss.queue_free()
		return
	if ai_throw.priority != 10:
		_fail("AIThrowRiders priority expected 10, got: %d" % ai_throw.priority)
		boss.queue_free()
		return
	if not ai_throw.can_break_stun:
		_fail("AIThrowRiders should have can_break_stun = true.")
		boss.queue_free()
		return

	var riders_ctrl: AkiraBossRiders = boss.get_node_or_null("RiderController") as AkiraBossRiders
	if riders_ctrl == null:
		_fail("RiderController missing.")
		boss.queue_free()
		return
	if not riders_ctrl.has_riders():
		_fail("RiderController should initially have riders.")
		boss.queue_free()
		return

	# Spawn player in front of boss
	var player_scene: PackedScene = load("res://Player/player.tscn") as PackedScene
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	player.global_position = Vector3(0.0, 1.0, 5.0)
	boss.current_target = player

	# Execute throw ability
	throw_attack.cooldown_timer = 0.0
	throw_attack.throw_delay = 0.05
	boss.state_machine.request_state("EnemyThrowRiders")

	# Wait for throw to occur
	for _i: int in range(25):
		await get_tree().process_frame
		await get_tree().physics_frame
		if not riders_ctrl.has_riders():
			break

	if riders_ctrl.has_riders():
		_fail("Riders should be detached after throw.")
		player.queue_free()
		boss.queue_free()
		return
	if boss.has_tag(&"has_riders"):
		_fail("Boss should lose 'has_riders' tag after throw.")
		player.queue_free()
		boss.queue_free()
		return
	if riders_ctrl.left_rider_root.visible or riders_ctrl.right_rider_root.visible:
		_fail("Rider visuals should be hidden after detach.")
		player.queue_free()
		boss.queue_free()
		return

	# Wait for projectiles to land and spawn minions
	var spawned_minions: Array[Character] = []
	for _i: int in range(60):
		await get_tree().physics_frame
		var all_enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
		for e: Node in all_enemies:
			if e != boss and not spawned_minions.has(e) and e is Character:
				spawned_minions.append(e as Character)
		if spawned_minions.size() >= 2:
			break

	if spawned_minions.size() < 2:
		_fail("Throw riders should spawn 2 melee enemy minions upon landing (got %d)." % spawned_minions.size())
		for m: Character in spawned_minions:
			m.queue_free()
		player.queue_free()
		boss.queue_free()
		return

	print("Throw riders detached riders, hid meshes, and spawned 2 melee minions.")
	for m: Character in spawned_minions:
		m.queue_free()
	player.queue_free()
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1


func _part14_summon_helpers_ability() -> void:
	print("\n>>> PART 14: Summon helpers ability, minion spawn, and rider restoration")
	var boss: Character = _boss()
	if boss == null:
		_fail("Could not spawn boss for summon helpers test.")
		return
	add_child(boss)
	boss.global_position = Vector3(0.0, 1.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var summon_attack: AkiraBossSummonHelpersAttack = boss.state_machine.get_node_or_null("EnemySummonHelpers") as AkiraBossSummonHelpersAttack
	if summon_attack == null:
		_fail("EnemySummonHelpers is not an AkiraBossSummonHelpersAttack instance.")
		boss.queue_free()
		return

	# Check exports and configuration
	if summon_attack.cooldown != 20.0:
		_fail("EnemySummonHelpers cooldown expected 20.0, got: %f" % summon_attack.cooldown)
		boss.queue_free()
		return
	if summon_attack.starting_cooldown != 0.0:
		_fail("EnemySummonHelpers starting_cooldown expected 0.0, got: %f" % summon_attack.starting_cooldown)
		boss.queue_free()
		return
	if summon_attack.attack_animation_name != "Flexing":
		_fail("EnemySummonHelpers animation expected 'Flexing', got: %s" % summon_attack.attack_animation_name)
		boss.queue_free()
		return
	if not summon_attack.uninterruptable:
		_fail("EnemySummonHelpers should be uninterruptable.")
		boss.queue_free()
		return
	if not summon_attack.blocked_tags.has(&"has_riders"):
		_fail("EnemySummonHelpers should be blocked by 'has_riders' tag.")
		boss.queue_free()
		return
	if not summon_attack.start_cooldown_on_enabled:
		_fail("EnemySummonHelpers should have start_cooldown_on_enabled = true.")
		boss.queue_free()
		return

	# AI state check
	var ai_summon: AIConditionalAttack = boss.ai_state_machine.get_node_or_null("AISummonHelpers") as AIConditionalAttack
	if ai_summon == null:
		_fail("AISummonHelpers node missing on AIStateMachine.")
		boss.queue_free()
		return
	if ai_summon.attack_state_name != "EnemySummonHelpers":
		_fail("AISummonHelpers attack_state_name expected 'EnemySummonHelpers', got: %s" % ai_summon.attack_state_name)
		boss.queue_free()
		return
	if ai_summon.priority != 10:
		_fail("AISummonHelpers priority expected 10, got: %d" % ai_summon.priority)
		boss.queue_free()
		return
	if not ai_summon.can_break_stun:
		_fail("AISummonHelpers should have can_break_stun = true.")
		boss.queue_free()
		return

	var riders_ctrl: AkiraBossRiders = boss.get_node_or_null("RiderController") as AkiraBossRiders
	if riders_ctrl == null:
		_fail("RiderController missing.")
		boss.queue_free()
		return

	# Detach riders first so summon can be activated
	riders_ctrl.detach_riders()
	boss.attribute_component.remove_effect(&"has_riders")
	boss.attribute_component.remove_tag(&"has_riders")
	await get_tree().physics_frame

	if riders_ctrl.has_riders():
		_fail("Riders should be detached before summon.")
		boss.queue_free()
		return
	if boss.has_tag(&"has_riders"):
		_fail("Boss should not have 'has_riders' tag before summon.")
		boss.queue_free()
		return

	# Execute summon ability
	summon_attack.cooldown_timer = 0.0
	summon_attack.summon_delay = 0.05
	boss.state_machine.request_state("EnemySummonHelpers")

	# Wait for helpers to spawn and land
	var spawned_helpers: Array[Character] = []
	for _i: int in range(60):
		await get_tree().process_frame
		await get_tree().physics_frame
		var all_enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
		for e: Node in all_enemies:
			if e != boss and not spawned_helpers.has(e) and e is Character:
				spawned_helpers.append(e as Character)
		if spawned_helpers.size() >= 2 and riders_ctrl.has_riders():
			break

	if spawned_helpers.size() < 2:
		_fail("Summon helpers should spawn 2 ground melee minions (got %d)." % spawned_helpers.size())
		for h: Character in spawned_helpers:
			h.queue_free()
		boss.queue_free()
		return

	if not riders_ctrl.has_riders():
		_fail("Backpack helpers should restore riders upon landing.")
		for h: Character in spawned_helpers:
			h.queue_free()
		boss.queue_free()
		return

	if not boss.has_tag(&"has_riders"):
		_fail("Boss should regain 'has_riders' tag upon backpack helpers landing.")
		for h: Character in spawned_helpers:
			h.queue_free()
		boss.queue_free()
		return

	if not riders_ctrl.left_rider_root.visible or not riders_ctrl.right_rider_root.visible:
		_fail("Rider meshes should be visible again after restoration.")
		for h: Character in spawned_helpers:
			h.queue_free()
		boss.queue_free()
		return

	print("Summon helpers summoned 4 helpers: 2 ground minions spawned and 2 backpack riders restored.")
	for h: Character in spawned_helpers:
		h.queue_free()
	boss.queue_free()
	await get_tree().process_frame
	_passed += 1

