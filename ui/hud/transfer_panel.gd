class_name TransferPanel
extends Control
## Lets the local player give points to another living player.
## Presentation only: it never changes anyone's points. On confirm it emits
## transfer_requested(target_id, amount); the authoritative host validates and applies it,
## then sends the new state through GameHUD.apply_state().
##
## Keyboard: T opens/closes, Up/Down choose a player, Left/Right change the amount,
## Enter confirms, Esc cancels. Mouse works too (the cursor is shown while it is open).

signal transfer_requested(target_id: int, amount: int)
signal opened
signal closed

@export var row_scene: PackedScene
@export var low_points_threshold := 3
@export var open_action := &"transfer_points"

@onready var balance_label: Label = %BalanceLabel
@onready var rows: VBoxContainer = %Rows
@onready var minus_button: Button = %MinusButton
@onready var plus_button: Button = %PlusButton
@onready var max_button: Button = %MaxButton
@onready var amount_label: Label = %AmountLabel
@onready var you_value_label: Label = %YouValueLabel
@onready var target_name_label: Label = %TargetNameLabel
@onready var target_value_label: Label = %TargetValueLabel
@onready var warning_label: Label = %WarningLabel
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton

var is_open := false

var _local_alive := false
var _my_points := 0
var _others: Array = []          # living players other than the local one
var _amount := 1
var _selected: TransferTargetRow
var _group := ButtonGroup.new()
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _fade: Tween


func _ready() -> void:
	visible = false
	_ensure_open_action()
	minus_button.pressed.connect(_set_amount.bind(-1, true))
	plus_button.pressed.connect(_set_amount.bind(1, true))
	max_button.pressed.connect(func() -> void: _set_amount(_my_points, false))
	cancel_button.pressed.connect(close)
	confirm_button.pressed.connect(_confirm)


## Called by GameHUD every time the host sends a new state.
func set_players(players: Array, local_id: int) -> void:
	_others.clear()
	_local_alive = false
	_my_points = 0
	for p: Dictionary in players:
		if p.get("id", -2) == local_id:
			_local_alive = p.get("alive", true)
			_my_points = p.get("points", 0)
		elif p.get("alive", true):
			_others.append(p)

	if not is_open:
		return
	if not _local_alive or _my_points <= 0 or _others.is_empty():
		close()   # nothing left to give or nobody to give it to
	else:
		_rebuild_rows(_selected.player_id if _selected else -1)
		_refresh()


func open() -> void:
	if is_open or not _local_alive or _my_points <= 0 or _others.is_empty():
		return
	is_open = true
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_amount = 1
	visible = true
	modulate.a = 0.0
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, UIStyle.DUR_FAST)
	_rebuild_rows(-1)
	_refresh()
	if _selected:
		_selected.grab_focus()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	Input.mouse_mode = _previous_mouse_mode
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open and event.is_action_pressed(open_action):
		open()
		if is_open:
			get_viewport().set_input_as_handled()


# _input runs before the buttons see the keys, so Enter confirms instead of "pressing" a row.
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed(open_action):
		close()
	elif event.is_action_pressed("ui_accept"):
		_confirm()
	elif event.is_action_pressed("ui_left", true):
		_set_amount(-1, true)
	elif event.is_action_pressed("ui_right", true):
		_set_amount(1, true)
	else:
		return
	get_viewport().set_input_as_handled()


func _rebuild_rows(keep_id: int) -> void:
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	_selected = null
	for p: Dictionary in _others:
		var row := row_scene.instantiate() as TransferTargetRow
		rows.add_child(row)
		row.set_data(p)
		row.button_group = _group
		row.pressed.connect(_select.bind(row))
		row.focus_entered.connect(_select.bind(row))   # moving with the arrow keys selects
		if row.player_id == keep_id:
			_selected = row
	if _selected == null and rows.get_child_count() > 0:
		_selected = rows.get_child(0) as TransferTargetRow
	if _selected:
		_selected.button_pressed = true


func _select(row: TransferTargetRow) -> void:
	_selected = row
	row.button_pressed = true
	_refresh()


func _set_amount(value: int, relative: bool) -> void:
	_amount = _amount + value if relative else value
	_refresh()


func _refresh() -> void:
	_amount = clampi(_amount, 1, maxi(_my_points, 1))
	balance_label.text = "YOU HAVE %02d" % _my_points
	amount_label.text = "%02d" % _amount
	minus_button.disabled = _amount <= 1
	plus_button.disabled = _amount >= _my_points
	max_button.disabled = _amount >= _my_points
	if _selected == null:
		return

	# What this transfer will do, spelled out before the player confirms.
	var my_after := _my_points - _amount
	var target_after := _selected.points + _amount
	you_value_label.text = "%02d  →  %02d" % [_my_points, my_after]
	target_name_label.text = _selected.text
	target_value_label.text = "%02d  →  %02d" % [_selected.points, target_after]

	var danger := my_after <= 0
	var low := not danger and my_after <= low_points_threshold
	var colour := UIStyle.TEXT
	if danger:
		colour = UIStyle.RED
		warning_label.text = "THIS LEAVES YOU AT 0 POINTS. YOU WILL BE ELIMINATED."
	elif low:
		colour = UIStyle.AMBER
		warning_label.text = "THIS LEAVES YOU LOW ON POINTS."
	else:
		warning_label.text = ""
	you_value_label.add_theme_color_override("font_color", colour)
	warning_label.add_theme_color_override("font_color", colour)
	confirm_button.theme_type_variation = &"ButtonDanger" if danger else &"ButtonPrimary"


func _confirm() -> void:
	if _selected == null:
		return
	transfer_requested.emit(_selected.player_id, _amount)
	close()


## Creates the "transfer_points" action (key T) if it isn't in Project Settings > Input Map.
func _ensure_open_action() -> void:
	if InputMap.has_action(open_action):
		return
	InputMap.add_action(open_action)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_T
	InputMap.action_add_event(open_action, ev)
