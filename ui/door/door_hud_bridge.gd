extends Node
## Connects the hitscan to the HUD's door prompt, and pauses the player while a HUD panel
## is open (transfer, pause, elimination, victory ...).
##
## Add it as the LAST child of your level scene. It finds the three things it needs by group,
## so nothing has to be dragged in:
##   "hitscan"  the hitscan Node3D (hitscan.gd adds itself)
##   "hud"      the GameHUD (its scene is already in this group)
##   "player"   the Player (player.gd adds itself)
## You can still assign them in the Inspector instead.
##
## StandardDoor provides get_hud_info() (cost, capacity, reserved, locked, exit).

@export var hitscan: Node3D
@export var hud: GameHUD
## The Player node (it needs the input_blocked variable from player.gd).
@export var player: Node


func _ready() -> void:
	if hitscan == null:
		hitscan = get_tree().get_first_node_in_group("hitscan") as Node3D
	if hud == null:
		hud = get_tree().get_first_node_in_group("hud") as GameHUD
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if hitscan == null or hud == null or player == null:
		push_warning("door_hud_bridge: could not find the hitscan, the HUD and the player. Is this node the last child of the level?")
		return

	hitscan.door_focused.connect(_on_door_focused)
	hitscan.door_unfocused.connect(hud.hide_door_prompt)
	hud.modal_opened.connect(_on_modal_opened)
	hud.modal_closed.connect(_on_modal_closed)


func _on_door_focused(door: StandardDoor) -> void:
	hud.show_door_prompt(door.get_hud_info())


func _on_modal_opened() -> void:
	player.input_blocked = true
	hitscan.set_process(false)
	hud.hide_door_prompt()


func _on_modal_closed() -> void:
	player.input_blocked = false
	hitscan.set_process(true)
