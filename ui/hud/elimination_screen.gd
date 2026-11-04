class_name EliminationScreen
extends Control
## Plays when the local player is eliminated: the world dims, a dark band opens across
## the middle of the screen with "ELIMINATED" and the reason, holds, then closes again.
## It never blocks the whole screen and it does not need any input. Presentation only.

signal finished

@export var hold_seconds := 3.5

@onready var scrim: ColorRect = %Scrim
@onready var band: ColorRect = %Band
@onready var title_label: Label = %TitleLabel
@onready var reason_label: Label = %ReasonLabel
@onready var final_label: Label = %FinalLabel

var is_playing := false
var _tween: Tween


func _ready() -> void:
	visible = false
	band.resized.connect(_update_pivot)


func play(reason: String, points: int) -> void:
	reason_label.text = reason.to_upper()
	final_label.text = "FINAL POINTS  %02d" % points
	is_playing = true
	visible = true
	_update_pivot()

	scrim.modulate.a = 0.0
	band.scale = Vector2(1.0, 0.0)
	for l in [title_label, reason_label, final_label]:
		(l as Label).modulate.a = 0.0

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(scrim, "modulate:a", 1.0, 0.4)
	_tween.parallel().tween_property(band, "scale:y", 1.0, 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(title_label, "modulate:a", 1.0, 0.15)
	_tween.tween_property(reason_label, "modulate:a", 1.0, 0.2)
	_tween.parallel().tween_property(final_label, "modulate:a", 1.0, 0.2)
	_tween.tween_interval(hold_seconds)
	_tween.tween_property(band, "scale:y", 0.0, 0.25)
	_tween.parallel().tween_property(scrim, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(_done)


func _update_pivot() -> void:
	band.pivot_offset = band.size / 2.0


func _done() -> void:
	is_playing = false
	visible = false
	finished.emit()
