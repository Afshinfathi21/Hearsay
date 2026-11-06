extends Node
## Main menu entry point. Steam lobby creation and joining are the next networking step.

@export_file("*.tscn") var level_path := ""
@export var menus: MenuRoot


func _ready() -> void:
	menus.host_requested.connect(_on_host)
	menus.join_requested.connect(_on_join)
	menus.ready_toggled.connect(func(_is_ready: bool) -> void: pass)
	menus.start_requested.connect(_on_start)
	menus.leave_lobby_requested.connect(func() -> void: menus.show_lobby_connect())
	menus.quit_requested.connect(func() -> void: get_tree().quit())


func _on_host(_player_name: String) -> void:
	menus.set_lobby_busy(true)
	if SteamManager.initialize():
		menus.set_lobby_status("STEAM CONNECTED. LOBBY CREATION IS THE NEXT STEP.")
	else:
		menus.set_lobby_status("STEAM INITIALIZATION FAILED. CHECK THE GODOTSTEAM INSTALLATION.", true)
	menus.set_lobby_busy(false)


func _on_join(_player_name: String, _lobby_id: String) -> void:
	menus.set_lobby_busy(true)
	if SteamManager.initialize():
		menus.set_lobby_status("STEAM CONNECTED. LOBBY JOINING IS THE NEXT STEP.")
	else:
		menus.set_lobby_status("STEAM INITIALIZATION FAILED. CHECK THE GODOTSTEAM INSTALLATION.", true)
	menus.set_lobby_busy(false)


func _on_start() -> void:
	if level_path == "":
		push_error("StartScene: set Level Path in the Inspector.")
		return
	menus.show_loading("LOADING")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(level_path)
