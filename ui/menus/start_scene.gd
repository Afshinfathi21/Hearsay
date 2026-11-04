extends Node
## The first scene of the game: shows the menus and loads your level.
## This version has no networking: HOST A GAME opens a room with just you, and START
## MATCH loads the level. When your network code exists, connect it to the same
## MenuRoot signals (host_requested, join_requested, start_requested ...) instead.

## The level to load when the host presses START MATCH.
@export_file("*.tscn") var level_path := ""
@export var menus: MenuRoot

var _players := [{"id": 1, "name": "Player", "ready": false, "host": true, "ping": 0}]


func _ready() -> void:
	menus.host_requested.connect(_on_host)
	menus.join_requested.connect(func(_n: String, _a: String, _p: int) -> void:
		menus.set_lobby_status("JOINING NEEDS YOUR NETWORK CODE", true))
	menus.ready_toggled.connect(_on_ready_toggled)
	menus.start_requested.connect(_on_start)
	menus.leave_lobby_requested.connect(func() -> void: menus.show_lobby_connect())
	menus.quit_requested.connect(func() -> void: get_tree().quit())


func _on_host(player_name: String, _port: int) -> void:
	_players[0]["name"] = player_name
	_players[0]["ready"] = false
	_show_room()


func _on_ready_toggled(is_ready: bool) -> void:
	_players[0]["ready"] = is_ready
	_show_room()


func _show_room() -> void:
	menus.show_lobby_room(_players, 1, true)


func _on_start() -> void:
	if level_path == "":
		push_error("StartScene: set Level Path in the Inspector.")
		return
	menus.show_loading("LOADING")
	await get_tree().process_frame     # let the loading screen draw before the level loads
	await get_tree().process_frame
	get_tree().change_scene_to_file(level_path)
