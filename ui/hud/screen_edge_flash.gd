class_name ScreenEdgeFlash
extends Panel
## A thin coloured frame around the whole screen that flashes once for critical events.
## It only draws the border, so the 3D world stays fully visible.

var _frame: StyleBoxFlat
var _tween: Tween


func _ready() -> void:
	_frame = get_theme_stylebox("panel") as StyleBoxFlat
	modulate.a = 0.0


func flash(colour: Color) -> void:
	_frame.border_color = colour
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.08)
	_tween.tween_property(self, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
