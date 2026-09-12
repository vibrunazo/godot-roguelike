## Floor hazard that triggers when a player steps on it.
## After a configurable dodge-window delay, spikes thrust upward via AnimationPlayer,
## dealing damage and knockback to any character (player or enemy) in the damage hitbox.
## Resets back to idle after an active duration and cooldown.
class_name SpikesHazard
extends Node3D

enum State {
	IDLE,
	TRIGGERED,
	ACTIVE,
	RETRACTING,
	COOLDOWN,
}

## Delay in seconds between the player stepping into the trigger and the spikes thrusting up.
## Provides the player a reaction window to dodge roll away.
@export var trigger_delay: float = 0.4

## Duration in seconds that the spikes remain extended and dangerous.
@export var active_duration: float = 1.6

## Cooldown duration in seconds after spikes finish retracting before the trap can re-trigger.
@export var reset_cooldown: float = 1.0

## Damage dealt to any character (player or enemy) standing on the spikes.
@export var damage: float = 5.0

## Vertical knockback impulse applied to damaged characters.
@export var knockback_force: float = 4.0

var current_state: int = State.IDLE


func is_idle() -> bool:
	return current_state == State.IDLE


func is_triggered() -> bool:
	return current_state == State.TRIGGERED


func is_active() -> bool:
	return current_state == State.ACTIVE


func is_cooldown() -> bool:
	return current_state == State.COOLDOWN


@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var trigger_area: Area3D = $TriggerArea
@onready var damage_hitbox: Area3D = $DamageHitbox
@onready var attack_component: AttackComponent = $DamageHitbox/AttackComponent
@onready var delay_timer: Timer = $DelayTimer
@onready var active_timer: Timer = $ActiveTimer
@onready var cooldown_timer: Timer = $CooldownTimer
@onready var spike_audio: AudioStreamPlayer3D = $SpikeAudio


func _ready() -> void:
	trigger_area.body_entered.connect(_on_trigger_area_body_entered)
	delay_timer.timeout.connect(_on_delay_timer_timeout)
	active_timer.timeout.connect(_on_active_timer_timeout)
	cooldown_timer.timeout.connect(_on_cooldown_timer_timeout)
	if animation_player != null:
		animation_player.animation_finished.connect(_on_animation_finished)
	_sync_attack_component()
	current_state = State.IDLE
	damage_hitbox.monitoring = false
	damage_hitbox.monitorable = false


func _sync_attack_component() -> void:
	if attack_component != null:
		attack_component.damage = damage
		attack_component.knockback = Vector3(0.0, knockback_force, 0.0)


func _on_trigger_area_body_entered(body: Node3D) -> void:
	if current_state != State.IDLE:
		return
	if _is_trigger_character(body):
		trigger()


func _is_trigger_character(node: Node) -> bool:
	if node is Character:
		return (node as Character).is_alive()
	return node.is_in_group("player") or node.is_in_group("enemy")


## Arms and begins the trigger delay countdown before emerging.
func trigger() -> void:
	if current_state != State.IDLE:
		return
	current_state = State.TRIGGERED
	if trigger_delay <= 0.0:
		_emerge_spikes()
	else:
		delay_timer.wait_time = trigger_delay
		delay_timer.start()


func _on_delay_timer_timeout() -> void:
	if current_state != State.TRIGGERED:
		return
	_emerge_spikes()


func _emerge_spikes() -> void:
	current_state = State.ACTIVE
	_sync_attack_component()
	if attack_component != null:
		attack_component.reset_exceptions()
	damage_hitbox.monitoring = true
	if animation_player != null and animation_player.has_animation("spring"):
		animation_player.play("spring")
	if spike_audio != null and not spike_audio.playing:
		spike_audio.play()
	# Immediately strike any character already inside the hitbox
	if attack_component != null:
		attack_component.deal_damage()
	active_timer.wait_time = active_duration
	active_timer.start()


func _on_active_timer_timeout() -> void:
	if current_state != State.ACTIVE:
		return
	_retract_spikes()


func _retract_spikes() -> void:
	current_state = State.RETRACTING
	damage_hitbox.monitoring = false
	if animation_player != null and animation_player.has_animation("retract"):
		animation_player.play("retract")
	else:
		_on_retract_completed()


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"retract":
		_on_retract_completed()


func _on_retract_completed() -> void:
	current_state = State.COOLDOWN
	cooldown_timer.wait_time = reset_cooldown
	cooldown_timer.start()


func _on_cooldown_timer_timeout() -> void:
	current_state = State.IDLE
	# Re-trigger if any living character is still standing inside the trigger area
	for body: Node3D in trigger_area.get_overlapping_bodies():
		if _is_trigger_character(body):
			trigger()
			break
