extends Node
## TEST ONLY: pretends to be the network so you can click through every menu screen.
## Host a game -> room with fake players -> READY -> START MATCH -> loading -> results.
## Delete this script and the demo scene when your networking code drives MenuRoot.

@export var menus: MenuRoot

var _is_host := true
var _players := [
	{"id": 1, "name": "You", "ready": false, "host": true, "ping": 0},
	{"id": 2, "name": "Mira", "ready": true, "host": false, "ping": 42},
	{"id": 3, "name": "Jonas", "ready": true, "host": false, "ping": 57},
]


func _ready() -> void:
	menus.host_requested.connect(_on_host)
	menus.join_requested.connect(_on_join)
	menus.ready_toggled.connect(_on_ready_toggled)
	menus.start_requested.connect(_on_start)
	menus.leave_lobby_requested.connect(func() -> void: menus.show_lobby_connect())
	menus.back_to_lobby_requested.connect(_refresh_room)
	menus.retry_requested.connect(func() -> void: print("retry requested"))


func _on_host(player_name: String, _port: int) -> void:
	_is_host = true
	_players[0]["name"] = player_name
	_players[0]["host"] = true
	_refresh_room()


func _on_join(player_name: String, address: String, _port: int) -> void:
	menus.set_lobby_busy(true)
	menus.set_lobby_status("CONNECTING TO %s ..." % address)
	menus.set_connection("connecting")
	await get_tree().create_timer(1.2).timeout
	menus.set_connection("connected")
	_is_host = false
	_players[0]["name"] = player_name
	_players[0]["host"] = false
	_players[1]["host"] = true
	_refresh_room()


func _on_ready_toggled(is_ready: bool) -> void:
	_players[0]["ready"] = is_ready
	_refresh_room()


func _refresh_room() -> void:
	menus.show_lobby_room(_players, 1, _is_host)


func _on_start() -> void:
	menus.show_loading("GENERATING THE BUILDING")
	for i in range(1, 11):
		await get_tree().create_timer(0.25).timeout
		menus.set_loading_progress(i / 10.0)
		if i == 6:
			menus.set_loading_status("WAITING FOR PLAYERS   3 / 3")
	await get_tree().create_timer(0.5).timeout
	menus.show_results({
		"local_id": 1,
		"players": [
			{"id": 1, "name": _players[0]["name"], "rank": 1, "outcome": "escaped", "points": 5},
			{"id": 2, "name": "Mira", "rank": 2, "outcome": "escaped", "points": 2},
			{"id": 3, "name": "Jonas", "rank": 3, "outcome": "eliminated", "points": 0},
		],
		"stats": [
			{"label": "Rounds", "value": "07"}, {"label": "Doors passed", "value": "12"},
			{"label": "Points spent", "value": "09"}, {"label": "Time", "value": "14:32"},
		],
	})
