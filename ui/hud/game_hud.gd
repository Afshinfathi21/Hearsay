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
##
## Other calls (all from the host's events):
##   show_door_prompt(info) / hide_door_prompt()   see door_prompt.gd
##   notify(event)                                  see notification_feed.gd
##   show_elimination({"reason": "...", "points": 0, "spectate": true})
##   show_victory(info)                             see victory_screen.gd

## The local player confirmed a transfer. Send it to the host; it validates and applies it.
signal transfer_requested(target_id: int, amount: int)
## A screen that takes over the player (transfer panel, elimination, spectating, victory)
## opened / closed. Use these to pause player movement and the camera.
signal modal_opened
signal modal_closed
## While spectating: the player to watch changed (-1 = nobody left).
signal spectate_target_changed(player_id: int)
## The player pressed Continue on the victory screen.
signal victory_continue
## From the pause menu.
signal leave_match_requested
signal quit_requested
## From the connection-lost dialog.
signal retry_connection_requested
signal connection_lost_menu_requested

@export var starting_points := 10

@onready var round_info: RoundInfo = %RoundInfo
@onready var local_panel: LocalPlayerPanel = %LocalPlayerPanel
@onready var player_list: PlayerList = %PlayerList
@onready var door_prompt: DoorPrompt = %DoorPrompt
@onready var transfer_panel: TransferPanel = %TransferPanel
@onready var notification_feed: NotificationFeed = %NotificationFeed
@onready var edge_flash: ScreenEdgeFlash = %EdgeFlash
@onready var elimination_screen: EliminationScreen = %EliminationScreen
@onready var spectator_bar: SpectatorBar = %SpectatorBar
@onready var victory_screen: VictoryScreen = %VictoryScreen
@onready var pause_menu: PauseMenu = %PauseMenu
@onready var connection_overlay: ConnectionOverlay = %ConnectionOverlay

var _local_points := 0
var _modal := false
var _spectate_after_elimination := true


func _ready() -> void:
	local_panel.set_max_points(starting_points)
	transfer_panel.transfer_requested.connect(transfer_requested.emit)
	transfer_panel.opened.connect(_refresh_modal)
	transfer_panel.closed.connect(_refresh_modal)
	notification_feed.critical_event.connect(edge_flash.flash)
	elimination_screen.finished.connect(_on_elimination_finished)
	spectator_bar.target_changed.connect(spectate_target_changed.emit)
	spectator_bar.started.connect(_refresh_modal)
	spectator_bar.stopped.connect(_refresh_modal)
	victory_screen.continue_pressed.connect(victory_continue.emit)
	victory_screen.spectate_pressed.connect(spectator_bar.begin)
	victory_screen.closed.connect(_refresh_modal)
	pause_menu.opened.connect(_refresh_modal)
	pause_menu.closed.connect(_refresh_modal)
	pause_menu.leave_match_requested.connect(leave_match_requested.emit)
	pause_menu.quit_requested.connect(quit_requested.emit)
	connection_overlay.blocking_changed.connect(_refresh_modal)
	connection_overlay.retry_requested.connect(retry_connection_requested.emit)
	connection_overlay.menu_requested.connect(connection_lost_menu_requested.emit)


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
	transfer_panel.set_players(players, local_id)
	spectator_bar.set_players(players, local_id)


## Call every frame (or whenever it changes) while the player looks at a door.
## info: see door_prompt.gd. The prompt compares the cost with the local points.
func show_door_prompt(info: Dictionary) -> void:
	door_prompt.show_for_door(info, _local_points)


func hide_door_prompt() -> void:
	door_prompt.hide_prompt()


## Show a notification. event: see notification_feed.gd for the types and fields, e.g.
##   notify({"type": "points_deducted", "amount": 2, "detail": "ROOM C4"})
func notify(event: Dictionary) -> void:
	notification_feed.push(event)


## The local player was eliminated. info: { "reason": String, "points": int, "spectate": bool }
## After the short sequence the spectator bar appears (unless "spectate" is false).
func show_elimination(info: Dictionary) -> void:
	_spectate_after_elimination = info.get("spectate", true)
	transfer_panel.close()
	door_prompt.hide_prompt()
	edge_flash.flash(UIStyle.RED)
	elimination_screen.play(str(info.get("reason", "YOU RAN OUT OF POINTS")), info.get("points", 0))
	_refresh_modal()


## The local player escaped. info: see victory_screen.gd
func show_victory(info: Dictionary) -> void:
	transfer_panel.close()
	door_prompt.hide_prompt()
	victory_screen.show_victory(info)
	_refresh_modal()


## Connection banner: kind is "connecting", "reconnecting", "connected" or "hidden".
func set_connection(kind: String, detail := "") -> void:
	connection_overlay.set_status(kind, detail)


## The connection is gone: shows a dialog the player must answer.
func show_connection_lost(reason: String, can_retry := false) -> void:
	connection_overlay.show_lost(reason, can_retry)


func hide_connection_lost() -> void:
	connection_overlay.hide_lost()


func stop_spectating() -> void:
	spectator_bar.end()


func is_modal_open() -> bool:
	return _modal


func _on_elimination_finished() -> void:
	if _spectate_after_elimination:
		spectator_bar.begin()
	_refresh_modal()


func _refresh_modal() -> void:
	var now := transfer_panel.is_open or victory_screen.is_open \
		or elimination_screen.is_playing or spectator_bar.is_active \
		or pause_menu.is_open or connection_overlay.is_blocking
	if now == _modal:
		return
	_modal = now
	if now:
		modal_opened.emit()
	else:
		modal_closed.emit()
