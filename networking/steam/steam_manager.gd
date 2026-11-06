extends Node
## Central Steamworks lifecycle entry point.
## This is deliberately separate from gameplay and lobby UI.

signal initialization_succeeded
signal initialization_failed(reason: String)

const TEST_APP_ID := 480

var available := false
var initialized := false
var multiplayer_peer_available := false
var steam_id: int = 0
var persona_name := ""

var _steam: Object


func _ready() -> void:
	available = Engine.has_singleton("Steam")
	multiplayer_peer_available = ClassDB.class_exists("SteamMultiplayerPeer")

	if not available:
		push_warning("Steamworks extension not found. Install the Hearsay-compatible GodotSteam MultiplayerPeer build.")
		return

	_steam = Engine.get_singleton("Steam")


func _process(_delta: float) -> void:
	if initialized and is_instance_valid(_steam):
		_steam.call("run_callbacks")


## Initializes Steam using Valve's public Spacewar test App ID.
## Steam must be running, and the matching GodotSteam GDExtension must be installed.
func initialize() -> bool:
	if not available or not is_instance_valid(_steam):
		var reason := "GodotSteam extension is not loaded."
		initialization_failed.emit(reason)
		return false

	if initialized:
		return true

	var result: Dictionary = _steam.call("steamInitEx", false, TEST_APP_ID)
	var status := int(result.get("status", -1))
	if status != 0:
		var reason := str(result.get("verbal", "Steam initialization failed (status %d)." % status))
		initialization_failed.emit(reason)
		push_warning(reason)
		return false

	initialized = true
	steam_id = int(_steam.call("getSteamID"))
	persona_name = str(_steam.call("getPersonaName"))
	multiplayer_peer_available = ClassDB.class_exists("SteamMultiplayerPeer")
	initialization_succeeded.emit()
	return true


func is_ready_for_multiplayer() -> bool:
	return initialized and multiplayer_peer_available


func shutdown() -> void:
	if initialized and is_instance_valid(_steam):
		_steam.call("steamShutdown")
	initialized = false
	steam_id = 0
	persona_name = ""
