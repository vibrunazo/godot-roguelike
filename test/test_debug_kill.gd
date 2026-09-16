## Committed test for the `debug_kill` action (keyboard K): verifies the
## InputMap binding and that pressing it damages every living enemy through
## Hurtbox.receive_hit() while leaving the player untouched.
extends Node

const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")


func _ready() -> void:
	print("--- RUNNING DEBUG KILL TEST ---")

	# ---------------------------------------------------------
	# PART 1: InputMap Verification for "debug_kill"
	# ---------------------------------------------------------
	print("\n>>> PART 1: InputMap Action Verification")
	if not InputMap.has_action("debug_kill"):
		printerr("TEST FAILED: 'debug_kill' action is not registered in InputMap.")
		get_tree().quit(1)
		return
	print("Action 'debug_kill' exists in InputMap.")

	var events: Array[InputEvent] = InputMap.action_get_events("debug_kill")
	var has_k_key: bool = false
	for event: InputEvent in events:
		if event is InputEventKey:
			var key_event: InputEventKey = event as InputEventKey
			if key_event.physical_keycode == KEY_K or key_event.keycode == KEY_K:
				has_k_key = true
	if not has_k_key:
		printerr("TEST FAILED: 'debug_kill' action does not have key K assigned.")
		get_tree().quit(1)
		return
	print("Verified 'debug_kill' is mapped to key 'K'.")

	if not is_equal_approx(UI.DEBUG_KILL_DAMAGE, 50.0):
		printerr("TEST FAILED: UI.DEBUG_KILL_DAMAGE should be 50.0, got: ", UI.DEBUG_KILL_DAMAGE)
		get_tree().quit(1)
		return
	print("Verified UI.DEBUG_KILL_DAMAGE is 50.0.")

	# ---------------------------------------------------------
	# PART 2: debug_kill_enemies() damages all enemies via Hurtbox
	# ---------------------------------------------------------
	print("\n>>> PART 2: debug_kill_enemies() damages all enemies")
	var enemy_a: Character = MELEE_SCENE.instantiate() as Character
	var enemy_b: Character = MELEE_SCENE.instantiate() as Character
	var player: Character = PLAYER_SCENE.instantiate() as Character
	add_child(enemy_a)
	add_child(enemy_b)
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame

	if not enemy_a.is_in_group("enemy") or not enemy_b.is_in_group("enemy"):
		printerr("TEST FAILED: Spawned melee enemies should be in the 'enemy' group.")
		get_tree().quit(1)
		return

	var hurtbox_a: Hurtbox = enemy_a.get_node_or_null("Hurtbox") as Hurtbox
	var hurtbox_b: Hurtbox = enemy_b.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox_a == null or hurtbox_b == null:
		printerr("TEST FAILED: Melee enemies should wire a Hurtbox.")
		get_tree().quit(1)
		return

	var struck_hits: Array[float] = []
	hurtbox_a.struck.connect(func(damage: float) -> void: struck_hits.append(damage))
	hurtbox_b.struck.connect(func(damage: float) -> void: struck_hits.append(damage))

	var attrs_a: AttributeComponent = enemy_a.get_node("AttributeComponent") as AttributeComponent
	var attrs_b: AttributeComponent = enemy_b.get_node("AttributeComponent") as AttributeComponent
	var player_attrs: AttributeComponent = player.get_node("AttributeComponent") as AttributeComponent
	var before_a: float = attrs_a.get_current(AttributeComponent.POOL_HEALTH)
	var before_b: float = attrs_b.get_current(AttributeComponent.POOL_HEALTH)
	var before_player: float = player_attrs.get_current(AttributeComponent.POOL_HEALTH)

	UI.debug_kill_enemies()

	var expected_a: float = maxf(0.0, before_a - UI.DEBUG_KILL_DAMAGE)
	var expected_b: float = maxf(0.0, before_b - UI.DEBUG_KILL_DAMAGE)
	if not is_equal_approx(attrs_a.get_current(AttributeComponent.POOL_HEALTH), expected_a):
		printerr("TEST FAILED: Enemy A health should drop relatively by the debug damage.")
		get_tree().quit(1)
		return
	if not is_equal_approx(attrs_b.get_current(AttributeComponent.POOL_HEALTH), expected_b):
		printerr("TEST FAILED: Enemy B health should drop relatively by the debug damage.")
		get_tree().quit(1)
		return
	if struck_hits.size() != 2:
		printerr("TEST FAILED: Both enemies should emit Hurtbox.struck (hit-reaction path), got: ", struck_hits.size())
		get_tree().quit(1)
		return
	if not is_equal_approx(player_attrs.get_current(AttributeComponent.POOL_HEALTH), before_player):
		printerr("TEST FAILED: debug_kill must not damage the player.")
		get_tree().quit(1)
		return
	print("debug_kill_enemies() verified: all enemies damaged via Hurtbox, player untouched.")

	# ---------------------------------------------------------
	# PART 3: Simulated K key press routes through _unhandled_key_input
	# ---------------------------------------------------------
	print("\n>>> PART 3: Key Input Event Simulation (K Key)")
	attrs_a.restore_pool(AttributeComponent.POOL_HEALTH, UI.DEBUG_KILL_DAMAGE)
	attrs_b.restore_pool(AttributeComponent.POOL_HEALTH, UI.DEBUG_KILL_DAMAGE)
	var healed_a: float = attrs_a.get_current(AttributeComponent.POOL_HEALTH)
	var healed_b: float = attrs_b.get_current(AttributeComponent.POOL_HEALTH)

	var key_event_k: InputEventKey = InputEventKey.new()
	key_event_k.physical_keycode = KEY_K
	key_event_k.pressed = true
	UI._unhandled_key_input(key_event_k)

	if not is_equal_approx(attrs_a.get_current(AttributeComponent.POOL_HEALTH), maxf(0.0, healed_a - UI.DEBUG_KILL_DAMAGE)):
		printerr("TEST FAILED: Simulated K key press did not damage enemy A.")
		get_tree().quit(1)
		return
	if not is_equal_approx(attrs_b.get_current(AttributeComponent.POOL_HEALTH), maxf(0.0, healed_b - UI.DEBUG_KILL_DAMAGE)):
		printerr("TEST FAILED: Simulated K key press did not damage enemy B.")
		get_tree().quit(1)
		return
	print("Simulated 'K' key successfully damaged all enemies.")

	enemy_a.queue_free()
	enemy_b.queue_free()
	player.queue_free()
	await get_tree().process_frame

	print("\n====================================================================")
	print("  ALL DEBUG KILL TESTS PASSED!                                      ")
	print("====================================================================")
	get_tree().quit(0)
