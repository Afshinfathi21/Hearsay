class_name BidPanel
extends CanvasLayer
## The secret bid entry. Keyboard driven so the mouse can stay captured for looking around:
##   digits type the amount, Backspace deletes, Up/Down = +-10, Left/Right = +-1,
##   M = all your points, Z = 0, Enter = lock in. The buttons work if the mouse is free.
## Pure presentation: it only reports the locked-in amount (bid_chosen).

signal bid_chosen(amount: int)

var input_enabled := true

var value := 0
var max_value := 0
var locked := false
var _open := false

var _root: PanelContainer
var _value_label: Label
var _info_label: Label
var _warn_label: Label
var _timer_bar: ProgressBar
var _timer_label: Label
var _hint_label: Label
var _lock_button: Button


func _ready() -> void:
	layer = 8
	_root = PanelContainer.new()
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_root.anchor_left = 0.5
	_root.anchor_right = 0.5
	_root.offset_left = -270.0
	_root.offset_right = 270.0
	_root.offset_top = -300.0
	_root.offset_bottom = -60.0
	_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.05, 0.92)
	style.border_color = Color(1.0, 0.72, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_root.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "PLACE YOUR SECRET BID"
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.2))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_timer_label = Label.new()
	head.add_child(_timer_label)

	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 8)
	box.add_child(_timer_bar)

	_value_label = Label.new()
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.add_theme_font_size_override("font_size", 54)
	box.add_child(_value_label)

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info_label)

	_warn_label = Label.new()
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	box.add_child(_warn_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	for entry in [["0", 0.0], ["25%", 0.25], ["50%", 0.5], ["MAX", 1.0]]:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_fraction.bind(float(entry[1])))
		buttons.add_child(b)
	_lock_button = Button.new()
	_lock_button.text = "LOCK IN  [ENTER]"
	_lock_button.focus_mode = Control.FOCUS_NONE
	_lock_button.pressed.connect(_lock_in)
	buttons.add_child(_lock_button)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.modulate = Color(1, 1, 1, 0.6)
	_hint_label.text = "type digits  ·  ↑↓ ±10  ·  ←→ ±1  ·  M = max  ·  Z = 0  ·  nobody sees your bid until the reveal"
	box.add_child(_hint_label)


func open(points: int, penalty: int, fatal_next_loss: bool) -> void:
	max_value = points
	value = 0
	locked = false
	_open = true
	_root.visible = true
	_lock_button.disabled = false
	_info_label.text = "YOUR POINTS  %d      ROUND PENALTY  -%d" % [points, penalty]
	_warn_label.text = "NEXT LOSS IS FATAL: you cannot pay the penalty" if fatal_next_loss else ""
	_refresh()


func close() -> void:
	_open = false
	_root.visible = false


func show_locked(amount: int) -> void:
	locked = true
	value = amount
	_lock_button.disabled = true
	_hint_label.text = "BID LOCKED — waiting for the other players"
	_refresh()


func set_time(left: float, total: float) -> void:
	_timer_bar.max_value = maxf(total, 1.0)
	_timer_bar.value = left
	_timer_label.text = "%d s" % int(ceil(left))
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25) if left <= 5.0 else Color.WHITE)
	if not locked and left <= 5.0 and _open:
		_warn_label.text = "NOTHING SUBMITTED = A BID OF 0"


func is_open() -> bool:
	return _open


func _input(event: InputEvent) -> void:
	if not _open or locked or not input_enabled:
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	var key := event as InputEventKey
	var handled := true
	match key.keycode:
		KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, \
		KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9:
			if not key.echo:
				var digit := (key.keycode - KEY_0) if key.keycode <= KEY_9 else (key.keycode - KEY_KP_0)
				value = mini(value * 10 + digit, max_value)
		KEY_BACKSPACE:
			value = value / 10
		KEY_UP:
			value = mini(value + 10, max_value)
		KEY_DOWN:
			value = maxi(value - 10, 0)
		KEY_RIGHT:
			value = mini(value + 1, max_value)
		KEY_LEFT:
			value = maxi(value - 1, 0)
		KEY_M:
			value = max_value
		KEY_Z:
			value = 0
		KEY_ENTER, KEY_KP_ENTER:
			if not key.echo:
				_lock_in()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
		_refresh()


func _set_fraction(fraction: float) -> void:
	if locked:
		return
	value = int(round(max_value * fraction))
	_refresh()


func _lock_in() -> void:
	if locked or not _open:
		return
	bid_chosen.emit(value)


func _refresh() -> void:
	_value_label.text = str(value)
