class_name MiniGamePanel
extends PanelContainer
## The mini-game readout at the top centre of the screen. Presentation only: it shows what the host sends.
##
## state = {
##   "title": "DON'T BLINK",
##   "phase": "countdown" | "dark" | "watching" | "won" | "lost",
##   "countdown": 3,             # seconds, for "countdown"
##   "danger": 2, "max_danger": 5,
##   "time_left": -1.0,          # seconds; -1 = no time limit
##   "event": "THE EYE SAW YOU", # short message, "" = none
## }

var _title: Label
var _status: Label
var _event: Label
var _danger_bar: ProgressBar
var _danger_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UIStyle.box(UIStyle.HUD_BG, UIStyle.METAL, UIStyle.BORDER, UIStyle.SP_4, UIStyle.SP_3))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIStyle.SP_2)
	add_child(box)
	_title = _label(UIStyle.FONT_CAPTION, UIStyle.TEXT_MUTED)
	_status = _label(UIStyle.FONT_TITLE, UIStyle.TEXT)
	_event = _label(UIStyle.FONT_LABEL, UIStyle.RED)
	_danger_label = _label(UIStyle.FONT_CAPTION, UIStyle.TEXT_MUTED)
	_danger_bar = ProgressBar.new()
	_danger_bar.show_percentage = false
	_danger_bar.custom_minimum_size = Vector2(260, 10)
	_danger_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [_title, _status, _event, _danger_label, _danger_bar]:
		box.add_child(c)
	visible = false


func set_state(state: Dictionary) -> void:
	visible = true
	_title.text = str(state.get("title", "")).to_upper()
	var danger: int = state.get("danger", 0)
	var max_danger: int = maxi(state.get("max_danger", 1), 1)
	var colour := UIStyle.TEXT
	var text := ""
	match str(state.get("phase", "")):
		"countdown":
			text = "GET READY: %d" % int(state.get("countdown", 0))
			colour = UIStyle.AMBER
		"dark":
			text = "THE EYE IS SHUT: MOVE"
			colour = Color(0.35, 0.9, 0.45)
		"watching":
			text = "THE EYE IS WATCHING: FREEZE"
			colour = UIStyle.RED
		"won":
			text = "YOU MADE IT"
			colour = Color(0.35, 0.9, 0.45)
		"lost":
			text = "THE EYE FOUND YOU ALL"
			colour = UIStyle.RED
	var left: float = state.get("time_left", -1.0)
	if left >= 0.0 and str(state.get("phase", "")) in ["dark", "watching"]:
		text += "   (%d s)" % int(left)
	_status.text = text
	_status.add_theme_color_override("font_color", colour)
	_event.text = str(state.get("event", ""))
	_event.visible = _event.text != ""
	_danger_label.text = "DANGER %d / %d" % [danger, max_danger]
	_danger_bar.max_value = max_danger
	_danger_bar.value = danger
	_danger_bar.modulate = UIStyle.AMBER.lerp(UIStyle.RED, float(danger) / max_danger)


func clear() -> void:
	visible = false


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
