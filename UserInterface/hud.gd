## In-game heads-up display overlay showing run statistics such as gold currency.
class_name HUD
extends CanvasLayer

@onready var gold_label: Label = $MarginContainer/HBoxContainer/GoldLabel

## Pop-in scale factor the gold label reaches at the peak of its bounce.
@export var gold_bounce_peak_scale: Vector2 = Vector2(1.35, 1.35)
## Seconds the gold label takes to grow up to the peak of the bounce.
@export var gold_bounce_up_duration: float = 0.1
## Seconds the gold label takes to settle back down after the peak.
@export var gold_bounce_down_duration: float = 0.22
## Pixels the gold label drops below its resting position when gold is lost.
@export var gold_dip_distance: float = 10.0
## Seconds the gold label takes to sink down during a gold-loss dip.
@export var gold_dip_down_duration: float = 0.12
## Seconds the gold label takes to rise back up after a gold-loss dip.
@export var gold_dip_up_duration: float = 0.2

## Last gold amount rendered, used to detect gains (vs. spends/resets).
var _last_gold_amount: int = -1
## Active gain-bounce tween, killed and restarted when gold is gained again mid-bounce.
var _gold_bounce_tween: Tween = null
## Active loss-dip tween, killed and restarted when gold is lost again mid-dip.
var _gold_dip_tween: Tween = null
## The gold label's unanimated Y position, captured lazily so repeated dips
## triggered mid-dip cannot accumulate a permanent offset.
var _gold_resting_y: float = -1.0


func _ready() -> void:
	add_to_group("hud")
	if UI != null and not UI.overlays_enabled:
		visible = false
	if ProgressionState != null:
		if not ProgressionState.currency_gold_changed.is_connected(_on_gold_changed):
			ProgressionState.currency_gold_changed.connect(_on_gold_changed)
		_update_gold_display(ProgressionState.currency_gold)


func _exit_tree() -> void:
	if ProgressionState != null and ProgressionState.currency_gold_changed.is_connected(_on_gold_changed):
		ProgressionState.currency_gold_changed.disconnect(_on_gold_changed)


func _on_gold_changed(new_amount: int) -> void:
	_update_gold_display(new_amount)


func _update_gold_display(amount: int) -> void:
	if gold_label != null:
		var previous_amount: int = _last_gold_amount
		_last_gold_amount = amount
		gold_label.text = "Gold: %d" % amount
		gold_label.visible = amount > 0
		if amount > previous_amount and amount > 0:
			_play_gold_bounce()
		elif amount < previous_amount and amount > 0:
			_play_gold_dip()


## Plays a quick up-and-down bounce on the gold label whenever gold is gained.
## Restarting the tween (instead of queueing) keeps rapid pickups responsive.
func _play_gold_bounce() -> void:
	if _gold_bounce_tween != null and _gold_bounce_tween.is_valid():
		_gold_bounce_tween.kill()
	# Scale around the label's bottom-center so it grows upward, then settles down.
	gold_label.pivot_offset = Vector2(gold_label.size.x / 2.0, gold_label.size.y)
	gold_label.scale = Vector2.ONE
	_gold_bounce_tween = create_tween()
	_gold_bounce_tween.tween_property(gold_label, "scale", gold_bounce_peak_scale, gold_bounce_up_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_gold_bounce_tween.tween_property(gold_label, "scale", Vector2.ONE, gold_bounce_down_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Plays a quick dip-and-recover animation on the gold label whenever gold is
## lost: the label sinks down, then rises back to its resting position.
## Restarting the tween (instead of queueing) keeps rapid spends responsive.
func _play_gold_dip() -> void:
	if _gold_dip_tween != null and _gold_dip_tween.is_valid():
		_gold_dip_tween.kill()
	else:
		# Only re-capture the resting position while the label is actually at
		# rest; mid-dip retriggering must reuse the cached value to avoid drift.
		_gold_resting_y = gold_label.position.y
	_gold_dip_tween = create_tween()
	_gold_dip_tween.tween_property(gold_label, "position:y", _gold_resting_y + gold_dip_distance, gold_dip_down_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_gold_dip_tween.tween_property(gold_label, "position:y", _gold_resting_y, gold_dip_up_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
