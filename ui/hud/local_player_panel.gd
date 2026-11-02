class_name LocalPlayerPanel
extends PanelContainer
## The local player's name, status and points (bottom-left of the screen).
## Presentation only.
##   points > threshold : white number
##   1..threshold       : amber number that pulses (warning)
##   0                  : red number

@export var low_points_threshold := 3

@onready var initial_label: Label = %InitialLabel
@onready var name_label: Label = %NameLabel
@onready var status_label: Label = %StatusLabel
@onready var points_label: Label = %PointsLabel
@onready var delta_label: Label = %DeltaLabel
@onready var points_bar: ProgressBar = %PointsBar

var _points := 0
var _max_points := 1
var _alive := true
var _has_value := false
var _count_tween: Tween
var _pulse_tween: Tween
var _delta_tween: Tween


func _ready() -> void:
	delta_label.modulate.a = 0.0


func set_player(player_name: String) -> void:
	name_label.text = player_name.to_upper()
	initial_label.text = player_name.substr(0, 1).to_upper()


## The points the player started with: the full length of the bar.
func set_max_points(value: int) -> void:
	_max_points = maxi(value, 1)
	points_bar.max_value = _max_points


func set_alive(alive: bool) -> void:
	_alive = alive
	status_label.text = "ALIVE" if alive else "ELIMINATED"
	if alive:
		status_label.remove_theme_color_override("font_color")
	else:
		status_label.add_theme_color_override("font_color", UIStyle.RED)
	_update_state()


func set_points(value: int) -> void:
	value = maxi(value, 0)
	if _has_value and value == _points:
		return
	var old := _points
	var first := not _has_value
	_has_value = true
	_points = value

	if _count_tween:
		_count_tween.kill()
	if first:
		points_label.text = str(value)
		points_bar.value = value
	else:
		_count_tween = create_tween().set_parallel(true)
		_count_tween.tween_method(_show_number, float(old), float(value), UIStyle.DUR_NORMAL)
		_count_tween.tween_property(points_bar, "value", float(value), UIStyle.DUR_NORMAL)
		_show_delta(value - old)
		_punch()
	_update_state()


func _show_number(v: float) -> void:
	points_label.text = str(roundi(v))


func _show_delta(delta: int) -> void:
	delta_label.text = ("+%d" % delta) if delta > 0 else ("-%d" % absi(delta))
	delta_label.add_theme_color_override("font_color", UIStyle.AMBER if delta > 0 else UIStyle.TEXT)
	delta_label.modulate.a = 1.0
	if _delta_tween:
		_delta_tween.kill()
	_delta_tween = create_tween()
	_delta_tween.tween_interval(0.6)
	_delta_tween.tween_property(delta_label, "modulate:a", 0.0, UIStyle.DUR_SLOW)


## A tiny scale pop on the number whenever it changes.
func _punch() -> void:
	points_label.pivot_offset = points_label.size / 2.0
	var t := create_tween()
	t.tween_property(points_label, "scale", Vector2.ONE * 1.1, UIStyle.DUR_FAST)
	t.tween_property(points_label, "scale", Vector2.ONE, UIStyle.DUR_FAST)


func _update_state() -> void:
	var zero := _points <= 0
	var low := not zero and _points <= low_points_threshold
	var colour := UIStyle.TEXT
	if zero:
		colour = UIStyle.RED
	elif low:
		colour = UIStyle.AMBER
	points_label.add_theme_color_override("font_color", colour)
	points_bar.theme_type_variation = &"ProgressBarDanger" if zero else &""

	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	points_label.modulate.a = 1.0
	if low and _alive:
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(points_label, "modulate:a", 0.45, 0.5).set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(points_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
