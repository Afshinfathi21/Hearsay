extends Node
## Main menu entry point. Creates a local test lobby until Steam matchmaking is ready.

@export_file("*.tscn") var level_path := ""
@export var menus: MenuRoot

var _players: Array[Dictionary] = []


func _ready() -> void:
	menus.host_requested.connect(_on_host)
	menus.join_requested.connect(_on_join)
	menus.ready_toggled.connect(_on_ready_toggled)
	menus.start_requested.connect(_on_start)
	menus.leave_lobby_requested.connect(_on_leave_lobby)
	menus.quit_requested.connect(func() -> void: get_tree().quit())


func _on_host(player_name: String) -> void:
	_players = [{
		"id": 1,
		"name": player_name,
		"ready": false,
		"host": true,
		"ping": -1
	}]
	_show_room()
	menus.set_lobby_status("LOCAL TEST LOBBY — STEAM IS NOT REQUIRED")


func _on_join(_player_name: String, _lobby_id: String) -> void:
	menus.set_lobby_status("JOINING REAL STEAM LOBBIES IS NOT AVAILABLE YET.", true)


func _on_ready_toggled(is_ready: bool) -> void:
	if _players.is_empty():
		return
	_players[0]["ready"] = is_ready
	_show_room()


func _show_room() -> void:
	menus.show_lobby_room(_players, 1, true, "LOCAL TEST")


func _on_leave_lobby() -> void:
	_players.clear()
	menus.show_lobby_connect()


func _on_start() -> void:
	if _players.is_empty() or not _players[0].get("ready", false):
		return
	if level_path == "":
		push_error("StartScene: set Level Path in the Inspector.")
		return
	menus.show_loading("LOADING")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(level_path)
