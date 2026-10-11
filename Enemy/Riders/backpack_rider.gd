## One enemy riding in a backpack boss's backpack (one big character carrying
## riders on its back, see BackpackRiders): a torso-up visual of that enemy
## that attacks on its own while aboard, and the enemy it becomes when it
## leaves. It is not a Character (no body, health or mind): the carrier's
## BackpackRiders drives it, every hit and payload it deals is credited to the
## carrier, and it shows or hides as the riders board and leave.
## A melee rider hits with its weapon slot's hitbox, whose window the attack
## animation keys. A ranged rider releases payload_scene straight at its
## target when the attack animation fires the slot's ranged_attack signal.
## Either way the attack runs in the rider's own AnimationTree and returns to
## idle by itself. A new kind of rider is a scene with different data, not
## new code; a rider scene without its own CharacterColorComponent takes its
## carrier's palette.
class_name BackpackRider
extends Node3D

@export_group("Visual")
## The rider's AnimationTree.
@export var animation_tree: MannequinAnimationTree
## AnimationTree state the rider idles in.
@export var idle_state: StringName = &"WalkSpace"
## What shows while the rider is aboard and hides once it has left: its rig
## and weapon (the backpack stays on the carrier).
@export var body: Node3D
## Degrees per second the body turns in its seat toward the carrier's foe
## (and back to its seated facing without one). 0.0 keeps it as seated.
@export var turn_speed: float = 0.0

@export_group("Attack")
## AnimationTree state that plays the attack; it returns to idle_state by
## itself when it ends.
@export var attack_state: StringName = &"SideSlash"
## The rider's weapon slot. A melee rider's attack animation keys its hit
## window; a ranged rider's fires its ranged_attack signal, and the payload
## leaves from it.
@export var weapon_slot: WeaponSlot
## Closest distance, in meters from the rider to its target, it attacks at.
@export var min_range: float = 0.0
## Farthest distance, in meters from the rider to its target, it attacks at.
@export var max_range: float = 2.8
## Whether the rider only attacks along a clear straight line from its weapon
## slot to the target (Character.has_clear_shot()): for shooters.
@export var require_clear_shot: bool = false
## Seconds between the starts of two attacks.
@export var cooldown: float = 1.6
## Payload a ranged rider releases straight at its target's center (a
## projectile), through PayloadSpawner and credited to the carrier. Null for
## a melee rider.
@export var payload_scene: PackedScene
## Scale the payload's damage by the carrier's attack stat.
@export var scale_with_attack: bool = true

@export_group("Leaving")
## The lobbed projectile (a LobbedSpawnProjectile) this rider flies as when
## it leaves the backpack, thrown at a foe or dropped by a summon: it carries
## the rider's look and spawns the enemy the rider becomes.
@export var lob_scene: PackedScene

## The character carrying this rider (set by its BackpackRiders).
var carrier: Character = null

var _cooldown_left: float = 0.0
var _aboard: bool = true
## The foe the attack in progress aims at (a ranged rider's release target).
var _target: Character = null
## The body's yaw in its seat, which it turns back to without a foe.
var _seated_yaw: float = 0.0


func _ready() -> void:
	if animation_tree == null:
		push_error("%s: animation_tree is not set." % name)
	if body == null:
		push_error("%s: body is not set." % name)
	else:
		_seated_yaw = body.rotation.y
	if weapon_slot == null:
		push_error("%s: weapon_slot is not set." % name)
	elif payload_scene != null:
		weapon_slot.ranged_attack.connect(_release_payload)
	if lob_scene == null:
		push_error("%s: lob_scene is not set." % name)
	_go_idle()


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


## Called by the carrier's BackpackRiders every physics tick while the riders
## are aboard, with the foe they fight (null for none): the rider turns toward
## it and attacks when it may (can_attack()).
func engage(target: Character, delta: float) -> void:
	_turn_toward(target, delta)
	if target != null and can_attack(target):
		attack(target)


## Whether the rider would attack target now: aboard, off cooldown, not
## already attacking, the target alive within [min_range, max_range] of the
## rider and, with require_clear_shot, in a clear line.
func can_attack(target: Character) -> bool:
	if not _aboard or _cooldown_left > 0.0 or is_attacking():
		return false
	if target == null or not target.is_alive() or not target.is_inside_tree() or not is_inside_tree():
		return false
	var distance_sq: float = global_position.distance_squared_to(target.global_position)
	if distance_sq > max_range * max_range or distance_sq < min_range * min_range:
		return false
	return not require_clear_shot or (carrier != null and carrier.has_clear_shot(_shot_origin(), target))


## Starts an attack at target whatever the range (can_attack() is the gate
## engage() applies): plays attack_state, gives a melee rider's hitbox a fresh
## hit window and starts the cooldown.
func attack(target: Character) -> void:
	if animation_tree == null or not animation_tree.is_inside_tree():
		return
	_target = target
	# The rider runs no CharacterAttack that would reset its hit exceptions,
	# so without this only its first swing could ever land.
	var component: AttackComponent = _attack_component()
	if component != null:
		component.reset_exceptions()
	animation_tree.change_immediate(attack_state)
	_cooldown_left = cooldown


## Whether the rider plays its attack (from the tree's next physics step
## after attack()).
func is_attacking() -> bool:
	return animation_tree != null and animation_tree.playback != null and animation_tree.playback.get_current_node() == attack_state


## Whether the rider's cooldown has run out.
func is_ready() -> bool:
	return _cooldown_left <= 0.0


## Whether the rider is aboard (shown, attacking) rather than gone.
func is_aboard() -> bool:
	return _aboard


## Shows the rider aboard (true) or gone (false). Either way it drops what it
## was doing: back to idle in its seated facing, hit window closed, so a
## rider that leaves mid-swing never finishes it.
func set_aboard(aboard: bool) -> void:
	_aboard = aboard
	_target = null
	_go_idle()
	if weapon_slot != null:
		weapon_slot.enabled = false
	if body != null:
		body.visible = aboard
		body.rotation.y = _seated_yaw


## Sends this rider's lob (lob_scene) flying from from to land on landing,
## credited to the carrier. Where it lands it deals landing_damage (when above
## 0) to everyone within landing_radius but the carrier, with
## landing_knockback away from the landing point, spawns the enemy it carries
## when spawns_enemy, and calls on_landed with its landing point. Returns the
## lob, or null when it could not spawn.
func launch(from: Vector3, landing: Vector3, spawns_enemy: bool, landing_damage: float = 0.0, landing_radius: float = 0.0, landing_knockback: float = 0.0, on_landed: Callable = Callable()) -> LobbedSpawnProjectile:
	var lob: LobbedSpawnProjectile = PayloadSpawner.spawn(lob_scene, carrier, from, Vector3.ZERO, [], 1.0, false, landing) as LobbedSpawnProjectile
	if lob == null:
		push_error("%s: lob_scene must be a LobbedSpawnProjectile." % name)
		return null
	lob.spawn_enemy_on_land = spawns_enemy
	lob.deal_area_damage = landing_damage > 0.0
	lob.area_damage = landing_damage
	lob.area_radius = landing_radius
	lob.area_knockback = landing_knockback
	lob.landing_callback = on_landed
	return lob


## Releases payload_scene from the weapon slot straight at the attack's
## target, credited to the carrier. Fired by the weapon slot's ranged_attack
## signal (keyed in the attack animation); a rider that left, a dead carrier
## or a dead target releases nothing.
func _release_payload() -> void:
	if not _aboard or carrier == null or not is_instance_valid(carrier) or not carrier.is_alive():
		return
	if _target == null or not is_instance_valid(_target) or not _target.is_alive():
		return
	var origin: Vector3 = _shot_origin()
	var direction: Vector3 = _target.global_position - origin
	if direction.is_zero_approx():
		return
	PayloadSpawner.spawn(payload_scene, carrier, origin, direction.normalized(), [], 1.0, scale_with_attack)


## Where shots leave from: the weapon slot.
func _shot_origin() -> Vector3:
	return weapon_slot.global_position if weapon_slot != null else global_position


## The AttackComponent under the weapon slot's hitbox (a melee rider's), or
## null for a rider without a hitbox.
func _attack_component() -> AttackComponent:
	if weapon_slot == null or weapon_slot.hitbox == null:
		return null
	return weapon_slot.hitbox.get_node_or_null("AttackComponent") as AttackComponent


## Turns the body in its seat toward target, or back to its seated facing
## without one, at turn_speed.
func _turn_toward(target: Character, delta: float) -> void:
	if turn_speed <= 0.0 or body == null:
		return
	var desired: float = _seated_yaw
	var seat: Node3D = body.get_parent_node_3d()
	if target != null and seat != null:
		var to_target: Vector3 = seat.global_transform.affine_inverse() * target.global_position - body.position
		if not Vector2(to_target.x, to_target.z).is_zero_approx():
			desired = atan2(to_target.x, to_target.z)
	body.rotation.y = rotate_toward(body.rotation.y, desired, deg_to_rad(turn_speed) * delta)


func _go_idle() -> void:
	if animation_tree != null and animation_tree.is_inside_tree():
		animation_tree.change_immediate(idle_state)
