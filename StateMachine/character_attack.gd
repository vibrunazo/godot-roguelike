## Melee attack state for all characters (player combo hits and enemy attacks),
## built on CharacterAction (cooldown, tags, animation, aim, cancel window,
## gravity, lifecycle events). This adds the melee half: the weapon slot's
## hitbox and its AttackComponent, the combo queue, the forward lunge and the
## attacker's hitstop. Player chains use combo_next (ordered); enemies use
## next_states random-pick.
class_name CharacterAttack
extends CharacterAction

## Amount of damage dealt to health components caught in this attack.
@export var damage: float = 10.0
## Knockback impulse applied to entities hit by this attack.
@export var knockback: float = 15.0
## Next attack state in the combo chain when an attack intent is queued (null = no chain).
@export var combo_next: CharacterState
## Time window (in seconds) after the attack starts to queue the next attack.
@export var queued_attack_time: float = 0.5
## Weapon slot this attack strikes with (sword, feet, fists, ...). Its hitbox's
## AttackComponent deals the hits, and the slot's enabled track (keyed by the
## attack animation) opens the hit window. Attacks that hit through something
## else (ranged attacks firing projectiles) leave it empty.
@export var weapon_slot: WeaponSlot = null
## Minimum interval (in seconds) before the same target can be hit again during this attack state.
@export var rehit_interval: float = 0.0
## Forward lunge speed applied from the attack's active phase. Leave at 0.0 to disable the lunge.
@export var dash_speed: float = 0.0
## Duration (in seconds) of the forward lunge. Leave at 0.0 to disable the lunge.
@export var dash_duration: float = 0.0
## Steers the forward lunge away from ending over a pit when that looks like a
## mistake (see LandingAssist). Null lunges exactly along the aim.
@export var lunge_landing_assist: LandingAssist
## GameplayEffects applied to each victim when a hit lands (slow, burn, ...).
## Copied to the AttackComponent on enter, which applies them on every
## confirmed hit. Re-hitting a victim refreshes matching effects instead of
## stacking them.
@export var effects_to_apply: Array[GameplayEffect] = []
## Time scale applied to this character when one of its hits lands (self hitstop).
## Values near 0.0 almost freeze the attacker for a sense of impact weight.
@export var self_hitstop_scale: float = 0.05
## Duration (in seconds, real time) of the self slowmo after landing a hit.
## Keep under 0.1 for a snappy hitstop feel. Values <= 0.0 disable the effect.
@export var self_hitstop_duration: float = 0.1

var queued_attack: bool = false
var attack_timer: SceneTreeTimer
var lunging: bool = false
var lunge_direction: Vector3 = Vector3.ZERO
var _lunge_base_velocity: Vector3 = Vector3.ZERO
var lunge_timer: SceneTreeTimer
var lunge_slot: WeaponSlot
## WeaponSlot whose slash signal reports this attack's ACTIVE lifecycle event.
var _active_phase_slot: WeaponSlot
## Remaining self-hitstop time in seconds (real time). Above 0.0 means the
## attacker is slowed by self_hitstop_scale after landing a hit.
var hitstop_time_remaining: float = 0.0
## Attack animation TimeScale value to restore when hitstop ends.
var hitstop_base_timescale: float = 1.0
## Whether the current attack animation exposes a TimeScale node for slowdown.
var hitstop_has_timescale: bool = false


func _before_motion(delta: float) -> void:
	_update_hitstop(delta)


## The lunge while it runs, the steered movement otherwise; both slowed
## during hitstop.
func _planar_velocity() -> Vector3:
	var motion_scale: float = clampf(self_hitstop_scale, 0.0, 1.0) if is_in_hitstop() else 1.0
	if lunging:
		return (_lunge_base_velocity + lunge_direction * dash_speed) * motion_scale
	return character.move_direction * movement_speed * motion_scale


func _can_turn() -> bool:
	return not is_in_hitstop()


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	_reset_attack_state()
	if character != null:
		_arm_attack_component()
	super.enter(_previous_state_path, _data)
	if character == null:
		return
	_cache_hitstop_timescale()
	# Gameplay windows run on the physics clock (process_in_physics) so their
	# length in game time never depends on the render frame rate.
	attack_timer = get_tree().create_timer(queued_attack_time, true, true)
	attack_timer.timeout.connect(attempt_queue_attack)
	_arm_lunge()
	_active_phase_slot = get_weapon_slot()
	if _active_phase_slot != null:
		connect_one_shot(_active_phase_slot.slash, _broadcast_active_phase)


## Clears everything a previous run of this attack may have left behind.
func _reset_attack_state() -> void:
	queued_attack = false
	lunging = false
	lunge_direction = Vector3.ZERO
	lunge_slot = null
	hitstop_time_remaining = 0.0
	hitstop_has_timescale = false


## Loads this attack's damage, knockback, rehit rule and hit effects into the
## weapon slot's AttackComponent and listens for its hits.
func _arm_attack_component() -> void:
	var component: AttackComponent = get_attack_component()
	if component == null:
		return
	component.reset_exceptions()
	component.damage = damage * character.get_damage_modifier()
	var facing: Vector3 = character.mesh_mount.global_basis.z if character.mesh_mount != null else character.global_basis.z
	component.knockback = facing * knockback
	component.rehit_interval = rehit_interval
	component.effects_to_apply = effects_to_apply
	if not component.hit_landed.is_connected(_on_hit_landed):
		component.hit_landed.connect(_on_hit_landed)


## The AttackComponent under the weapon slot's hitbox, or null for attacks
## without a slot. A slot whose hitbox has no AttackComponent is a wiring error.
func get_attack_component() -> AttackComponent:
	if weapon_slot == null or weapon_slot.hitbox == null:
		return null
	var slot_component: AttackComponent = weapon_slot.hitbox.get_node_or_null("AttackComponent") as AttackComponent
	if slot_component == null:
		push_error("CharacterAttack '%s': weapon_slot '%s' has no AttackComponent under its hitbox." % [name, weapon_slot.name])
	return slot_component


## The WeaponSlot driving this attack's hit window, or null for attacks without
## one (they then skip lunge timing and slot cleanup).
func get_weapon_slot() -> WeaponSlot:
	return weapon_slot


## Arms the forward lunge when dash exports are set. The lunge starts when the
## weapon slot signals the attack's active phase via its slash signal (emitted
## exactly when the slot enables the hitbox), so no polling or hub is needed.
func _arm_lunge() -> void:
	if dash_speed <= 0.0 or dash_duration <= 0.0:
		return
	lunge_slot = get_weapon_slot()
	if lunge_slot != null:
		connect_one_shot(lunge_slot.slash, _begin_lunge)


## Reports this attack's ACTIVE lifecycle event, fired by the weapon slot's
## slash signal (exactly when the hit window opens). Attacks without a weapon
## slot never report ACTIVE; they still report STARTED/ENDED from enter/exit.
func _broadcast_active_phase() -> void:
	broadcast_ability_event(AbilityEvent.Phase.ACTIVE, {}, aim_direction)


## Starts the forward lunge along the locked aim direction.
## The aim vector is pixel-scaled (never normalized upstream), so it must be
## normalized here or dash_speed would scale with screen pixels.
func _begin_lunge() -> void:
	if character == null or not character.is_inside_tree():
		return
	lunge_direction = aim_direction
	if lunge_direction.is_zero_approx() and character.mesh_mount != null:
		lunge_direction = character.mesh_mount.global_basis.z.normalized()
	if lunge_direction.is_zero_approx():
		lunge_direction = Vector3.FORWARD
	lunge_direction = lunge_direction.normalized()
	if lunge_landing_assist != null:
		lunge_direction = lunge_landing_assist.steer(character, lunge_direction, dash_speed * dash_duration)
	_lunge_base_velocity = Vector3(character.velocity.x, 0.0, character.velocity.z)
	lunging = true
	lunge_timer = get_tree().create_timer(dash_duration, true, true)
	lunge_timer.timeout.connect(_end_lunge)


## Ends the forward lunge window; normal attack motion resumes.
func _end_lunge() -> void:
	lunging = false


## Clears all lunge state: motion flag, timer wiring, and slot signal wiring.
func _clear_lunge() -> void:
	lunging = false
	_lunge_base_velocity = Vector3.ZERO
	if lunge_timer != null:
		disconnect_safe(lunge_timer.timeout, _end_lunge)
		lunge_timer = null
	if lunge_slot != null:
		disconnect_safe(lunge_slot.slash, _begin_lunge)
		lunge_slot = null


## Returns true while the attacker is slowed after landing a hit.
func is_in_hitstop() -> bool:
	return hitstop_time_remaining > 0.0


## Slows this character briefly after one of its hits lands. Called on every
## AttackComponent.hit_landed emission, so multi-hit attacks refresh the window.
## Movement slowdown applies even when the attack animation has no TimeScale node.
func apply_self_hitstop() -> void:
	if self_hitstop_duration <= 0.0 or character == null or not character.is_inside_tree():
		return
	hitstop_time_remaining = self_hitstop_duration
	if hitstop_has_timescale and character.animation_tree != null:
		character.animation_tree.set(_get_timescale_param(), clampf(self_hitstop_scale, 0.0, 1.0))


## Counts the hitstop window down in real time and restores the attack
## animation speed when it expires.
func _update_hitstop(delta: float) -> void:
	if hitstop_time_remaining <= 0.0:
		return
	hitstop_time_remaining -= delta
	if hitstop_time_remaining <= 0.0:
		hitstop_time_remaining = 0.0
		_restore_hitstop_timescale()


## Restores the attack animation TimeScale captured at enter().
func _restore_hitstop_timescale() -> void:
	if not hitstop_has_timescale or character == null or character.animation_tree == null:
		return
	if not character.is_inside_tree():
		return
	character.animation_tree.set(_get_timescale_param(), hitstop_base_timescale)


## Clears an active hitstop without waiting for expiry. Runs on state exit
## (including dash-cancel and stun interruptions) so slowed animation speed
## never leaks into the next state.
func _clear_hitstop() -> void:
	if hitstop_time_remaining > 0.0:
		hitstop_time_remaining = 0.0
		_restore_hitstop_timescale()


## Reads the attack animation's base TimeScale once per attack. Attacks whose
## animation has no TimeScale node keep movement-only slowdown.
func _cache_hitstop_timescale() -> void:
	hitstop_has_timescale = false
	if character == null or character.animation_tree == null or animation_name.is_empty():
		return
	var current: Variant = character.animation_tree.get(_get_timescale_param())
	if current is float:
		hitstop_base_timescale = current as float
		hitstop_has_timescale = true


## AnimationTree parameter path of this attack's TimeScale node.
func _get_timescale_param() -> String:
	return "parameters/" + animation_name + "/TimeScale/scale"


## Each time the attack lands: slows this attacker (hitstop, not the victim)
## and reports the HIT lifecycle point with the struck hurtbox, so on-hit
## passives (HitEffectPassive) can act on it. Victim effects of the attack
## itself are applied by the AttackComponent on the confirmed hit.
func _on_hit_landed(target: Node) -> void:
	apply_self_hitstop()
	broadcast_ability_event(AbilityEvent.Phase.HIT, {"target": target})


## Queues a combo follow-up instead of transitioning (consumes the intent).
func check_attack() -> bool:
	if character == null:
		return false
	if not character.consume_attack_request():
		return false
	queued_attack = true
	return true


func exit() -> void:
	queued_attack = false
	_clear_lunge()
	_clear_hitstop()
	if attack_timer != null:
		disconnect_safe(attack_timer.timeout, attempt_queue_attack)
	var exit_component: AttackComponent = get_attack_component()
	if exit_component != null:
		disconnect_safe(exit_component.hit_landed, _on_hit_landed)
		exit_component.reset_exceptions()
	if _active_phase_slot != null:
		disconnect_safe(_active_phase_slot.slash, _broadcast_active_phase)
		_active_phase_slot = null
	var exit_slot: WeaponSlot = get_weapon_slot()
	if exit_slot != null and exit_slot.enabled:
		exit_slot.enabled = false
	super.exit()


## Chains combo_next when an attack intent was queued inside the queue window.
## A queued intent does NOT chain when the animation finishes: late presses
## are dropped.
func attempt_queue_attack() -> void:
	if combo_next == null or not queued_attack or character == null or character.state_machine == null:
		return
	var direction: Vector3 = character.move_direction
	if direction.is_zero_approx() and character.mesh_mount != null:
		direction = character.mesh_mount.global_basis.z.normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	character.state_machine.request_state(combo_next.name, {"direction": direction})
