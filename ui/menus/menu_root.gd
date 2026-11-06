class_name MenuRoot
extends Control

signal host_requested(player_name: String)
signal join_requested(player_name: String, lobby_id: String)
signal ready_toggled(ready: bool)
signal start_requested
signal leave_lobby_requested
signal back_to_lobby_requested
signal leave_to_menu_requested
signal retry_requested
signal quit_requested

@export var min_players_to_start := 2

@onready var main_menu: MainMenu = %MainMenu
@onready var lobby_menu: LobbyMenu = %LobbyMenu
@onready var settings_menu: SettingsMenu = %SettingsMenu
@onready var loading_screen: LoadingScreen = %LoadingScreen
@onready var match_results: MatchResults = %MatchResults
@onready var connection_overlay: ConnectionOverlay = %ConnectionOverlay

var _screens: Array[Control] = []


func _ready() -> void:
	GameSettings.apply_all()
	lobby_menu.min_players_to_start = min_players_to_start
	_screens = [main_menu, lobby_menu, settings_menu, loading_screen, match_results]

	main_menu.play_requested.connect(func() -> void: show_lobby_connect())
	main_menu.settings_requested.connect(func() -> void: _show(settings_menu))
	main_menu.quit_requested.connect(quit_requested.emit)
	settings_menu.back_requested.connect(show_main_menu)

	lobby_menu.host_requested.connect(host_requested.emit)
	lobby_menu.join_requested.connect(join_requested.emit)
	lobby_menu.ready_toggled.connect(ready_toggled.emit)
	lobby_menu.start_requested.connect(start_requested.emit)
	lobby_menu.leave_requested.connect(leave_lobby_requested.emit)
	lobby_menu.back_requested.connect(show_main_menu)

	match_results.lobby_requested.connect(back_to_lobby_requested.emit)
	match_results.menu_requested.connect(_go_to_menu)
	connection_overlay.retry_requested.connect(retry_requested.emit)
	connection_overlay.menu_requested.connect(_go_to_menu)

	show_main_menu()


func show_main_menu() -> void:
	_show(main_menu)


func show_lobby_connect(status := "") -> void:
	lobby_menu.show_connect(status)
	_show(lobby_menu)


func show_lobby_room(players: Array, local_id: int, is_host: bool, lobby_id := "") -> void:
	lobby_menu.show_room(players, local_id, is_host, lobby_id)
	_show(lobby_menu)


func set_lobby_status(text: String, is_error := false) -> void:
	lobby_menu.set_status(text, is_error)


func set_lobby_busy(busy: bool) -> void:
	lobby_menu.set_busy(busy)


func show_loading(status := "LOADING") -> void:
	loading_screen.show_loading(status)
	_show(loading_screen)


func set_loading_progress(progress: float) -> void:
	loading_screen.set_progress(progress)


func set_loading_status(text: String) -> void:
	loading_screen.set_status(text)


func show_results(info: Dictionary) -> void:
	match_results.show_results(info)
	_show(match_results)


func show_none() -> void:
	for s in _screens:
		s.visible = false


func set_connection(kind: String, detail := "") -> void:
	connection_overlay.set_status(kind, detail)


func show_connection_lost(reason: String, can_retry := false) -> void:
	connection_overlay.show_lost(reason, can_retry)


func hide_connection_lost() -> void:
	connection_overlay.hide_lost()


func _show(screen: Control) -> void:
	for s in _screens:
		s.visible = s == screen
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _go_to_menu() -> void:
	leave_to_menu_requested.emit()
	show_main_menu()
