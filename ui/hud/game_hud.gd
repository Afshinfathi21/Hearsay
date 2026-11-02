class_name GameHUD
extends Control
## Root of the gameplay HUD. Presentation only.
## The authoritative host owns the game state; each time it changes, call
## apply_state() with the new snapshot. The HUD never changes game state.
##
## state = {
##   "local_id": 1,                   # id of the player on this machine
##   "round": 2,
##   "phase": "Decision",
##   "time_left": 24.0,               # seconds; leave out (or use -1) when there is no timer
##   "time_total": 60.0,
##   "starting_points": 10,           # optional, sets the length of the points bar
##   "players": [
##       { "id": 1, "name": "Kai", "points": 7, "alive": true, "room": "03" },
##       ...
##   ],
## }

@export var starting_points := 10

@onready var round_info: RoundInfo = %RoundInfo
@onready var local_panel: LocalPlayerPanel = %LocalPlayerPanel
@onready var player_list: PlayerList = %PlayerList
@onready var door_prompt: DoorPrompt = %DoorPrompt

var _local_points := 0


func _ready() -> void:
	local_panel.set_max_points(starting_points)


func apply_state(state: Dictionary) -> void:
	if state.has("starting_points"):
		local_panel.set_max_points(state["starting_points"])

	var players: Array = state.get("players", [])
	var local_id: int = state.get("local_id", -1)

	for p: Dictionary in players:
		if p.get("id", -2) == local_id:
			local_panel.set_player(str(p.get("name", "")))
			local_panel.set_alive(p.get("alive", true))
			local_panel.set_points(p.get("points", 0))
			_local_points = p.get("points", 0)

	round_info.set_round(state.get("round", 0), str(state.get("phase", "")))
	round_info.set_timer(state.get("time_left", -1.0), state.get("time_total", -1.0))
	player_list.set_players(players, local_id)


## Call every frame (or whenever it changes) while the player looks at a door.
## info: see door_prompt.gd. The prompt compares the cost with the local points.
func show_door_prompt(info: Dictionary) -> void:
	door_prompt.show_for_door(info, _local_points)


func hide_door_prompt() -> void:
	door_prompt.hide_prompt()
