class_name InventoryBar
extends HBoxContainer
## The player's reward items as numbered slots (bottom centre). Presentation only: the host sends the items
## with set_items(), and a click or the number keys 1..4 only REQUEST to use a slot via use_requested.
## The host decides whether the item can be used and what happens.
##
## items = [{ "slot": 0, "name": "TRAP SCAN", "text": "tooltip", "category": 0 }, ...]   (filled slots only)

signal use_requested(slot: int)

@export var slot_count := 4

var enabled := true

var _buttons: Array[Button] = []
var _armed_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UIStyle.SP_2)
	_armed_label = Label.new()
	_armed_label.add_theme_font_size_override("font_size", UIStyle.FONT_CAPTION)
	_armed_label.add_theme_color_override("font_color", UIStyle.AMBER)
	_armed_label.visible = false
	add_child(_armed_label)
	for i in slot_count:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE                # keys and clicks never steal player input
		b.custom_minimum_size = Vector2(124, 36)
		b.add_theme_font_size_override("font_size", UIStyle.FONT_CAPTION)
		b.pressed.connect(_on_slot_pressed.bind(i))
		add_child(b)
		_buttons.append(b)
	set_items([], [])


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var slot: int = event.physical_keycode - KEY_1
		if slot >= 0 and slot < _buttons.size() and not _buttons[slot].disabled:
			use_requested.emit(slot)
			get_viewport().set_input_as_handled()


func set_items(items: Array, armed_names: Array) -> void:
	for i in _buttons.size():
		_buttons[i].text = "[%d]  -" % (i + 1)
		_buttons[i].disabled = true
		_buttons[i].tooltip_text = ""
	for item: Dictionary in items:
		var slot: int = item.get("slot", -1)
		if slot < 0 or slot >= _buttons.size():
			continue
		_buttons[slot].text = "[%d]  %s" % [slot + 1, str(item.get("name", "?"))]
		_buttons[slot].tooltip_text = str(item.get("text", ""))
		_buttons[slot].disabled = false
	_armed_label.visible = not armed_names.is_empty()
	_armed_label.text = "ARMED: " + ", ".join(armed_names)


## Number of slots that hold an item.
func filled_count() -> int:
	var n := 0
	for b in _buttons:
		if not b.disabled:
			n += 1
	return n


func set_enabled(value: bool) -> void:
	enabled = value
	for b in _buttons:
		b.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE


func _on_slot_pressed(slot: int) -> void:
	if enabled:
		use_requested.emit(slot)
