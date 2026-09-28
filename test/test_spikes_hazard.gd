## Spikes trap:
## - any living character stepping on it (player or enemy) triggers it,
## - nobody is hurt during trigger_delay (the dodge window); then the spikes
##   emerge and hurt whoever stands on them for the trap's damage,
## - stepping off during the dodge window avoids the hit,
## - after active_duration the spikes retract, the hitbox switches off, and
##   after reset_cooldown the trap re-arms and triggers again.
## Delays and damage are read from the hazard itself.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const SPIKES_SCENE: PackedScene = preload("res://Hazards/spikes_hazard.tscn")
## Physics ticks a body may take to be detected by the trigger area.
const DETECT_FRAMES: int = 10
## Where the trap sits, away from the arena's spawn markers.
const TRAP_SPOT: Vector3 = Vector3(8.0, 0.0, -8.0)

var _arena: Node3D
var _trap: SpikesHazard


func before_each() -> void:
	_arena = load_arena()
	_trap = spawn(SPIKES_SCENE, _arena, Vector3(TRAP_SPOT.x, arena_floor_top(_arena), TRAP_SPOT.z)) as SpikesHazard
	await wait_physics_frames(1)
	check(_trap.is_idle() and not _trap.damage_hitbox.monitoring, "setup: the trap should start idle and harmless")


func test_an_enemy_triggers_the_trap_and_is_hurt_only_after_the_dodge_window() -> void:
	var enemy: Character = spawn(MELEE_SCENE, _arena, _on_trap()) as Character
	disable_ai(enemy)
	await _check_triggers_then_hurts(enemy)


func test_the_player_triggers_the_trap_and_is_hurt_only_after_the_dodge_window() -> void:
	var player: Character = _spawn_player(_on_trap())
	await _check_triggers_then_hurts(player)


func test_stepping_off_during_the_dodge_window_avoids_the_hit() -> void:
	var player: Character = _spawn_player(_on_trap())
	if not await wait_until(func() -> bool: return _trap.is_triggered(), "setup: the player should trigger the trap", DETECT_FRAMES):
		return
	player.global_position = _on_trap() + Vector3(6.0, 0.0, 0.0)
	var health_before: float = _health(player)
	if not await wait_until(func() -> bool: return _trap.is_active(), "the spikes should emerge after the dodge window", _frames_for(_trap.trigger_delay)):
		return
	await wait_physics_frames(_frames_for(_trap.active_duration))
	check_approx(_health(player), health_before, "a player who stepped off in time should not be hurt")


func test_the_trap_retracts_and_rearms_after_its_cooldown() -> void:
	var enemy: Character = spawn(MELEE_SCENE, _arena, _on_trap()) as Character
	disable_ai(enemy)
	if not await wait_until(func() -> bool: return _trap.is_active(), "setup: the spikes should emerge", DETECT_FRAMES + _frames_for(_trap.trigger_delay)):
		return
	enemy.global_position = _on_trap() + Vector3(-6.0, 0.0, 0.0)
	# Test-owned cooldown, longer than the retract animation, so re-arming
	# early can only mean the cooldown was skipped.
	var retract_length: float = _trap.animation_player.get_animation(&"retract").length if _trap.animation_player.has_animation(&"retract") else 0.0
	_trap.reset_cooldown = retract_length + 0.5
	if not await wait_until(func() -> bool: return not _trap.is_active(), "the spikes should retract after active_duration", _frames_for(_trap.active_duration)):
		return
	check(not _trap.damage_hitbox.monitoring, "retracted spikes should not hurt")
	var rearm_ticks: Array[int] = [0]
	if not await wait_until(func() -> bool:
		rearm_ticks[0] += 1
		return _trap.is_idle(), "the trap should re-arm after retracting and reset_cooldown", _frames_for(retract_length + _trap.reset_cooldown)):
		return
	check(rearm_ticks[0] >= floori(_trap.reset_cooldown * Engine.physics_ticks_per_second), "the trap should not re-arm before reset_cooldown (took %d ticks)" % rearm_ticks[0])
	enemy.global_position = _on_trap()
	await wait_until(func() -> bool: return _trap.is_triggered(), "the re-armed trap should trigger again", DETECT_FRAMES)


## Checks the victim triggers the trap, stays unhurt for the whole dodge
## window, then takes the trap's damage when the spikes emerge.
func _check_triggers_then_hurts(victim: Character) -> void:
	if not await wait_until(func() -> bool: return not _trap.is_idle(), "stepping on the trap should trigger it", DETECT_FRAMES):
		return
	var health_before: float = _health(victim)
	var early_hit: Array[bool] = [false]
	var window_ticks: Array[int] = [0]
	if not await wait_until(func() -> bool:
		window_ticks[0] += 1
		early_hit[0] = early_hit[0] or (not _trap.is_active() and _health(victim) < health_before)
		return _trap.is_active(), "the spikes should emerge after trigger_delay", _frames_for(_trap.trigger_delay)):
		return
	check(not early_hit[0], "nobody should be hurt during the dodge window")
	check(window_ticks[0] >= floori(_trap.trigger_delay * Engine.physics_ticks_per_second), "the spikes should not emerge before trigger_delay (took %d ticks)" % window_ticks[0])
	var expected: float = _trap.attack_component.damage * victim.attribute_component.get_damage_multiplier(&"physical")
	await wait_until(func() -> bool: return _health(victim) < health_before, "the emerging spikes should hurt the victim", DETECT_FRAMES)
	check_approx(health_before - _health(victim), expected, "the spikes should deal the trap's damage")


func _spawn_player(at: Vector3) -> Character:
	var player: Character = spawn(PLAYER_SCENE, _arena, at) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	return player


## A standing spot on the trap.
func _on_trap() -> Vector3:
	return Vector3(TRAP_SPOT.x, arena_floor_top(_arena) + 1.0, TRAP_SPOT.z)


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## Physics frames covering the given game time, plus a small margin.
func _frames_for(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 5
