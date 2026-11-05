extends Node
## Connects the hitscan to the HUD's door prompt, and pauses the player while a HUD panel is open. Add it as a child of any node in the
## Player scene, then drag the Hitscan node and the GameHUD node into the two slots.
##
## StandardDoor already provides get_hud_info() (cost, capacity, reserved, locked).

@export var hitscan: Node3D
@export var hud: GameHUD
## The Player node (it needs the input_blocked variable from player.gd).
@export var player: Node


func _ready() -> void:
	hitscan.door_focused.connect(_on_door_focused)
	hitscan.door_unfocused.connect(hud.hide_door_prompt)
	hud.modal_opened.connect(_on_modal_opened)
	hud.modal_closed.connect(_on_modal_closed)


func _on_modal_opened() -> void:
	player.input_blocked = true
	hitscan.set_process(false)
	hud.hide_door_prompt()


func _on_modal_closed() -> void:
	player.input_blocked = false
	hitscan.set_process(true)


func _on_door_focused(door: StandardDoor) -> void:
	hud.show_door_prompt(door.get_hud_info(player.global_position))
