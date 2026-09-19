## In-game heads-up display overlay showing run statistics such as gold currency.
class_name HUD
extends CanvasLayer

@onready var gold_label: Label = $MarginContainer/HBoxContainer/GoldLabel


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
		gold_label.text = "Gold: %d" % amount
		gold_label.visible = amount > 0
