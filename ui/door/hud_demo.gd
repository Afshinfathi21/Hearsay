extends Node
## TEST ONLY: pretends to be the host so you can see the HUD react.
## Keys:  1 = +2 points   2 = -2 points   3 = set points to 2 (warning)
##        4 = eliminate player 2   5 = next round   6 = timer to 8 s (urgent)
##        7 = door prompt (ready)   8 = too expensive   9 = door full   0 = hide prompt
## Delete this script and the demo scene when the real game sends the state.

@export var hud: GameHUD

var _state := {
	"local_id": 1,
	"round": 1,
	"phase": "Decision",
	"time_left": 30.0,
	"time_total": 30.0,
	"starting_points": 10,
	"players": [
		{"id": 1, "name": "You", "points": 10, "alive": true, "room": "03"},
		{"id": 2, "name": "Mira", "points": 6, "alive": true, "room": "03"},
		{"id": 3, "name": "Jonas", "points": 4, "alive": true, "room": "05"},
		{"id": 4, "name": "Ilse", "points": 9, "alive": true},
	],
}


func _ready() -> void:
	hud.apply_state(_state)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1: _change_points(1, 2)
		KEY_2: _change_points(1, -2)
		KEY_3: _set_points(1, 2)
		KEY_4: _eliminate(2)
		KEY_5:
			_state["round"] += 1
			_state["phase"] = "Decision"
			_state["time_left"] = 30.0
		KEY_6: _state["time_left"] = 8.0
		KEY_7: hud.show_door_prompt({"cost": 3, "capacity": 2, "reserved": 0})
		KEY_8: hud.show_door_prompt({"cost": 99, "capacity": 2, "reserved": 0})
		KEY_9: hud.show_door_prompt({"cost": 3, "capacity": 2, "reserved": 2})
		KEY_0: hud.hide_door_prompt()
		_: return
	hud.apply_state(_state)


func _player(id: int) -> Dictionary:
	for p: Dictionary in _state["players"]:
		if p["id"] == id:
			return p
	return {}


func _set_points(id: int, value: int) -> void:
	var p := _player(id)
	if not p.is_empty():
		p["points"] = maxi(value, 0)
		if p["points"] == 0:
			p["alive"] = false


func _change_points(id: int, amount: int) -> void:
	_set_points(id, _player(id).get("points", 0) + amount)


func _eliminate(id: int) -> void:
	var p := _player(id)
	if not p.is_empty():
		p["points"] = 0
		p["alive"] = false
