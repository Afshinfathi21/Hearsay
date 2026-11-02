extends Node
## Connects the hitscan to the HUD's door prompt. Add it as a child of any node in the
## Player scene, then drag the Hitscan node and the GameHUD node into the two slots.
##
## Every StandardDoor must provide get_hud_info() (the host's numbers about that door):
##
##   func get_hud_info() -> Dictionary:
##       return {"cost": cost, "capacity": capacity, "reserved": reserved, "locked": locked}
##
## Use your door's real variables. The same numbers drive its DoorMonitor.

@export var hitscan: Node3D
@export var hud: GameHUD


func _ready() -> void:
	hitscan.door_focused.connect(_on_door_focused)
	hitscan.door_unfocused.connect(hud.hide_door_prompt)


func _on_door_focused(door: StandardDoor) -> void:
	hud.show_door_prompt(door.get_hud_info())
