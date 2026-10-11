## Backpack boss attack that throws its riders (BackpackRiders) at its target:
## throw_delay into the attack the riders leave the backpack and each flies as
## its own lob (BackpackRider.launch()) from its seat to a landing point
## beside the target, spread across the throw so they never cross, where it
## deals area damage and becomes the enemy it carries. Gate it on the rider
## tag (required_tags) so it only runs with riders aboard.
class_name ThrowRidersAttack
extends CharacterAttack

## The riders this attack throws.
@export var backpack: BackpackRiders
## Seconds into the attack the riders leave (the throw in the animation).
@export var throw_delay: float = 0.45
## Area damage each thrown rider deals where it lands.
@export var impact_damage: float = 20.0
## Radius in meters of the landing damage.
@export var impact_radius: float = 3.0
## Knockback impulse of the landing damage, away from the landing point.
@export var impact_knockback: float = 15.0
## Meters between neighboring riders' landing points, across the throw.
@export var landing_spread: float = 3.0
## Meters ahead the riders land when the attack aims only a direction (no
## target to throw at).
@export var throw_distance: float = 8.0

var _throw_timer: SceneTreeTimer


func _ready() -> void:
	super._ready()
	if backpack == null:
		push_error("%s: backpack is not set." % name)


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	super.enter(_previous_state_path, _data)
	_throw_timer = get_tree().create_timer(maxf(throw_delay, 0.0), true, true)
	_throw_timer.timeout.connect(_throw_riders)


## Committed until the throw: no order may cut the attack short before the
## riders leave (it would spend the throw for nothing).
func accepts_orders() -> bool:
	return _throw_timer == null


func exit() -> void:
	if _throw_timer != null:
		disconnect_safe(_throw_timer.timeout, _throw_riders)
		_throw_timer = null
	super.exit()


## Sends every rider flying at the throw target: they leave the backpack
## (BackpackRiders.unboard_riders()), and each lands on its own point (on the
## navigation mesh) spread across the throw, in the order the riders sit
## across it.
func _throw_riders() -> void:
	_throw_timer = null
	if character == null or not character.is_alive() or backpack == null or not backpack.has_riders():
		return
	var target: Vector3 = _throw_target_position()
	var throw_direction: Vector3 = target - character.global_position
	throw_direction.y = 0.0
	var across: Vector3 = throw_direction.normalized().cross(Vector3.UP)
	if across.is_zero_approx():
		across = Vector3.RIGHT
	var thrown: Array[BackpackRider] = []
	for rider: BackpackRider in backpack.riders:
		if rider != null:
			thrown.append(rider)
	var center: Vector3 = character.global_position
	thrown.sort_custom(func(a: BackpackRider, b: BackpackRider) -> bool:
		return (a.global_position - center).dot(across) < (b.global_position - center).dot(across))
	var seats: Array[Vector3] = []
	for rider: BackpackRider in thrown:
		seats.append(rider.global_position)
	backpack.unboard_riders()
	for index: int in thrown.size():
		var offset: float = (float(index) - float(thrown.size() - 1) * 0.5) * landing_spread
		var landing: Vector3 = backpack.landing_point(target + across * offset)
		thrown[index].launch(seats[index], landing, true, impact_damage, impact_radius, impact_knockback)


## Where the riders are thrown: the attack's aimed floor point (its target's
## feet), or throw_distance ahead along the aim when the attack only has a
## direction.
func _throw_target_position() -> Vector3:
	var aim: AimTarget = release_aim()
	if aim != null and aim.has_point:
		return aim.floor_point
	return character.get_feet_position() + aim_direction * throw_distance
