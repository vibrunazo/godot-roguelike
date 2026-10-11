## Backpack boss attack that calls its riders back (BackpackRiders):
## summon_delay into the attack, for every rider helpers_per_rider lobs of its
## kind (BackpackRider.launch()) drop from the sky beside the boss, on that
## rider's side, and become enemies of its kind, and one more drops into its
## backpack. Once every backpack lob has landed the riders board again
## (BackpackRiders.board_riders()). Gate it on the rider tag (blocked_tags)
## so it only runs while the riders are away.
class_name SummonRidersAttack
extends CharacterAttack

## The riders this attack calls back.
@export var backpack: BackpackRiders
## Seconds into the attack the summoned lobs drop (the flex in the animation).
@export var summon_delay: float = 1.0
## Enemies dropped beside the boss per rider, each of that rider's kind.
@export var helpers_per_rider: int = 1
## Meters to the side of the boss (each rider's own side) its helpers land.
@export var helper_side_offset: float = 3.0
## Meters ahead of the boss the first helper of each rider lands.
@export var helper_forward_offset: float = 1.5
## Meters between helpers of the same rider, each further one farther ahead.
@export var helper_spacing: float = 2.0
## Meters above its landing point each summoned lob starts its fall.
@export var drop_height: float = 10.0
## Horizontal meters each summoned lob travels on its way down (a lob needs
## some run; it falls for drop_drift / its speed seconds).
@export var drop_drift: float = 1.0

var _summon_timer: SceneTreeTimer
## Backpack lobs of the last summon still in the air.
var _backpack_lobs_left: int = 0


func _ready() -> void:
	super._ready()
	if backpack == null:
		push_error("%s: backpack is not set." % name)


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	super.enter(_previous_state_path, _data)
	_summon_timer = get_tree().create_timer(maxf(summon_delay, 0.0), true, true)
	_summon_timer.timeout.connect(_summon)


## Committed until the summon: no order may cut the attack short before the
## lobs drop (it would spend the summon for nothing).
func accepts_orders() -> bool:
	return _summon_timer == null


func exit() -> void:
	if _summon_timer != null:
		disconnect_safe(_summon_timer.timeout, _summon)
		_summon_timer = null
	super.exit()


## Drops each rider's helpers beside the boss and one lob into each backpack.
func _summon() -> void:
	_summon_timer = null
	if character == null or not character.is_alive() or backpack == null or backpack.has_riders():
		return
	var facing: Vector3 = _flat_facing()
	var across: Vector3 = facing.cross(Vector3.UP)
	var feet: Vector3 = character.get_feet_position()
	_backpack_lobs_left = 0
	for rider: BackpackRider in backpack.riders:
		if rider == null:
			continue
		var side: Vector3 = across if (rider.global_position - character.global_position).dot(across) >= 0.0 else -across
		for index: int in helpers_per_rider:
			var landing: Vector3 = backpack.landing_point(feet + side * helper_side_offset + facing * (helper_forward_offset + helper_spacing * index))
			rider.launch(_drop_start(landing, facing), landing, true)
		if rider.launch(_drop_start(rider.global_position, facing), rider.global_position, false, 0.0, 0.0, 0.0, _on_backpack_lob_landed) != null:
			_backpack_lobs_left += 1


## Where a summoned lob landing on landing starts its fall: drop_height above
## it, drop_drift behind it.
func _drop_start(landing: Vector3, facing: Vector3) -> Vector3:
	return landing + Vector3.UP * drop_height - facing * drop_drift


## Boards the riders once the last backpack lob has landed (while the boss
## lives).
func _on_backpack_lob_landed(_landing: Vector3) -> void:
	_backpack_lobs_left -= 1
	if _backpack_lobs_left > 0 or character == null or not is_instance_valid(character) or not character.is_alive():
		return
	if not backpack.has_riders():
		backpack.board_riders()


## The boss's horizontal facing (its mesh_mount's front).
func _flat_facing() -> Vector3:
	var front: Vector3 = character.mesh_mount.global_basis.z if character.mesh_mount != null else Vector3.BACK
	front.y = 0.0
	return front.normalized() if not front.is_zero_approx() else Vector3.BACK
