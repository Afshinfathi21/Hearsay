class_name VictoryScreen
extends Control
## Shown when the local player escapes through the real exit. A calm, confident
## sequence: the world dims, the panel fades in, a line draws under "ESCAPED", the
## remaining points count up and the stats appear one by one. Presentation only.
##
## info = {
##   "points": 5,                      # points remaining
##   "place": 1,                       # optional: 1 = first to escape
##   "total_players": 6,               # optional
##   "headline": "ESCAPED",            # optional
##   "can_spectate": true,             # optional: show the "WATCH OTHERS" button
##   "stats": [ {"label": "Rounds", "value": "07"}, {"label": "Doors passed", "value": "12"} ],
## }

signal continue_pressed
signal spectate_pressed
signal closed

@export var stat_row_scene: PackedScene

@onready var scrim: ColorRect = %Scrim
@onready var panel: PanelContainer = %Panel
@onready var headline_label: Label = %HeadlineLabel
@onready var rule: ColorRect = %Rule
@onready var sub_label: Label = %SubLabel
@onready var points_label: Label = %PointsLabel
@onready var stats: VBoxContainer = %Stats
@onready var buttons: HBoxContainer = %Buttons
@onready var spectate_button: Button = %SpectateButton
@onready var continue_button: Button = %ContinueButton

var is_open := false

var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _tween: Tween


func _ready() -> void:
	visible = false
	panel.resized.connect(_update_pivots)
	rule.resized.connect(_update_pivots)
	continue_button.pressed.connect(_on_continue)
	spectate_button.pressed.connect(_on_spectate)


func show_victory(info: Dictionary) -> void:
	assert(stat_row_scene != null, "VictoryScreen: assign Stat Row Scene in the Inspector.")
	if is_open:
		return
	is_open = true
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	headline_label.text = str(info.get("headline", "ESCAPED"))
	sub_label.text = _sub_text(info.get("place", 0), info.get("total_players", 0))
	sub_label.visible = sub_label.text != ""
	points_label.text = "00"
	spectate_button.visible = info.get("can_spectate", false)
	_fill_stats(info.get("stats", []))

	visible = true
	_update_pivots()
	_animate(info.get("points", 0))
	continue_button.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	Input.mouse_mode = _previous_mouse_mode
	closed.emit()


func _on_continue() -> void:
	continue_pressed.emit()
	close()


func _on_spectate() -> void:
	spectate_pressed.emit()    # first, so there is no gap between the two screens
	close()


func _fill_stats(list: Array) -> void:
	for c in stats.get_children():
		stats.remove_child(c)
		c.queue_free()
	for s: Dictionary in list:
		var row := stat_row_scene.instantiate() as ResultStatRow
		stats.add_child(row)
		row.set_data(str(s.get("label", "")), str(s.get("value", "")))
		row.modulate.a = 0.0


func _animate(points: int) -> void:
	scrim.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	rule.scale = Vector2(0.0, 1.0)
	buttons.modulate.a = 0.0

	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(scrim, "modulate:a", 1.0, UIStyle.DUR_SLOW)
	_tween.tween_property(panel, "modulate:a", 1.0, UIStyle.DUR_SLOW)
	_tween.tween_property(panel, "scale", Vector2.ONE, UIStyle.DUR_SLOW) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(rule, "scale:x", 1.0, 0.5).set_delay(0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_show_points, 0.0, float(points), 0.9).set_delay(0.5)
	var i := 0
	for row in stats.get_children():
		_tween.tween_property(row, "modulate:a", 1.0, UIStyle.DUR_NORMAL).set_delay(0.9 + 0.07 * i)
		i += 1
	_tween.tween_property(buttons, "modulate:a", 1.0, UIStyle.DUR_NORMAL).set_delay(1.0 + 0.07 * i)


func _show_points(v: float) -> void:
	points_label.text = "%02d" % roundi(v)


func _update_pivots() -> void:
	panel.pivot_offset = panel.size / 2.0
	rule.pivot_offset = rule.size / 2.0


func _sub_text(place: int, total: int) -> String:
	if place <= 0:
		return ""
	var text := "%s TO ESCAPE" % _ordinal(place)
	if total > 0:
		text += "   /   %d PLAYERS" % total
	return text


func _ordinal(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 13:
		return "%dTH" % n
	match n % 10:
		1: return "%dST" % n
		2: return "%dND" % n
		3: return "%dRD" % n
	return "%dTH" % n
