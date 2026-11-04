class_name LobbyMenu
extends Control
## Multiplayer lobby. Two states:
##   connect : name + address + HOST / JOIN
##   room    : the list of players, READY, and (for the host) START
## Presentation only: it emits what the player asked for; your networking code does it
## and then calls show_room() / set_status() to move the screen on.

signal host_requested(player_name: String, port: int)
signal join_requested(player_name: String, address: String, port: int)
signal ready_toggled(ready: bool)
signal start_requested
signal leave_requested       # leave the room (you are connected)
signal back_requested        # back to the main menu (not connected)

@export var row_scene: PackedScene
@export var min_players_to_start := 2

@onready var connect_panel: Control = %ConnectPanel
@onready var room_panel: Control = %RoomPanel
@onready var name_edit: LineEdit = %NameEdit
@onready var address_edit: LineEdit = %AddressEdit
@onready var port_edit: LineEdit = %PortEdit
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var room_info_label: Label = %RoomInfoLabel
@onready var rows: VBoxContainer = %PlayerRows
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var hint_label: Label = %HintLabel
@onready var back_button: Button = %BackButton

var _in_room := false
var _is_host := false
var _local_ready := false


func _ready() -> void:
	host_button.pressed.connect(func() -> void: host_requested.emit(_player_name(), _port()))
	join_button.pressed.connect(func() -> void: join_requested.emit(_player_name(), _address(), _port()))
	ready_button.toggled.connect(_on_ready_toggled)
	start_button.pressed.connect(start_requested.emit)
	back_button.pressed.connect(_on_back)
	visibility_changed.connect(func() -> void:
		if visible and not _in_room:
			name_edit.text = GameSettings.get_value("player", "name"))


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()


## Show the connect form. status: optional message ("" clears it).
func show_connect(status := "") -> void:
	_in_room = false
	connect_panel.visible = true
	room_panel.visible = false
	back_button.text = "BACK"
	set_busy(false)
	set_status(status, false)


## Show the room. players: see lobby_player_row.gd. Call again whenever the list changes.
func show_room(players: Array, local_id: int, is_host: bool) -> void:
	_in_room = true
	_is_host = is_host
	connect_panel.visible = false
	room_panel.visible = true
	back_button.text = "LEAVE LOBBY"

	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var all_ready := true
	for p: Dictionary in players:
		var row := row_scene.instantiate() as LobbyPlayerRow
		rows.add_child(row)
		row.set_data(p, p.get("id", -2) == local_id)
		if p.get("id", -2) == local_id:
			_local_ready = p.get("ready", false)
		if not p.get("ready", false):
			all_ready = false
	ready_button.set_pressed_no_signal(_local_ready)
	room_info_label.text = "LOBBY   /   %d PLAYER%s" % [players.size(), "" if players.size() == 1 else "S"]

	start_button.visible = is_host
	var can_start := players.size() >= min_players_to_start and all_ready
	start_button.disabled = not can_start
	if is_host:
		hint_label.text = "" if can_start else "WAITING FOR AT LEAST %d PLAYERS, ALL READY" % min_players_to_start
	else:
		hint_label.text = "WAITING FOR THE HOST TO START"


## Disables the form while a connection attempt is running.
func set_busy(busy: bool) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	name_edit.editable = not busy
	address_edit.editable = not busy
	port_edit.editable = not busy


func set_status(text: String, is_error := false) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", UIStyle.RED if is_error else UIStyle.TEXT_MUTED)


func _on_ready_toggled(on: bool) -> void:
	_local_ready = on
	ready_toggled.emit(on)


func _on_back() -> void:
	if _in_room:
		leave_requested.emit()
	else:
		back_requested.emit()


func _player_name() -> String:
	var n := name_edit.text.strip_edges()
	if n != "":
		GameSettings.set_value("player", "name", n)
		GameSettings.save()
	return n if n != "" else "Player"


func _address() -> String:
	var a := address_edit.text.strip_edges()
	return a if a != "" else "127.0.0.1"


func _port() -> int:
	var p := port_edit.text.strip_edges()
	return int(p) if p.is_valid_int() else 7777
