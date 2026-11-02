class_name RoundInfo
extends PanelContainer
## Round number, phase name and decision timer.
## Presentation only: the authoritative host sends the values, this node shows them.
## The countdown ticks locally between host updates (cosmetic); every call to
## set_timer() re-syncs it with the host.

@export var urgent_seconds := 10.0

@onready var round_label: Label = %RoundLabel
@onready var phase_label: Label = %PhaseLabel
@onready var timer_box: Control = %TimerBox
@onready var time_label: Label = %TimeLabel
@onready var timer_bar: ProgressBar = %TimerBar

var _round := -1
var _phase := ""
var _time_left := -1.0
var _time_total := -1.0
var _urgent := false


func set_round(round_number: int, phase: String) -> void:
	phase = phase.to_upper()
	if round_number != _round:
		_round = round_number
		round_label.text = "ROUND %02d" % round_number
		_fade_in(round_label)
	if phase != _phase:
		_phase = phase
		phase_label.text = phase
		_fade_in(phase_label)


## Pass total <= 0 when the round has no timer: the timer part is hidden.
func set_timer(time_left: float, time_total: float) -> void:
	_time_left = time_left
	_time_total = time_total
	timer_box.visible = time_total > 0.0
	_refresh_timer()


func _process(delta: float) -> void:
	if _time_total > 0.0 and _time_left > 0.0:
		_time_left = maxf(0.0, _time_left - delta)
		_refresh_timer()


func _refresh_timer() -> void:
	if _time_total <= 0.0:
		return
	var secs := ceili(_time_left)
	time_label.text = "%02d:%02d" % [int(secs / 60.0), secs % 60]
	timer_bar.max_value = _time_total
	timer_bar.value = _time_left

	var urgent := _time_left <= urgent_seconds
	if urgent != _urgent:
		_urgent = urgent
		timer_bar.theme_type_variation = &"ProgressBarDanger" if urgent else &""
		time_label.theme_type_variation = &"LabelDanger" if urgent else &"LabelMono"


func _fade_in(label: Label) -> void:
	label.modulate.a = 0.0
	create_tween().tween_property(label, "modulate:a", 1.0, UIStyle.DUR_NORMAL)
