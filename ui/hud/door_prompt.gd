class_name DoorPrompt
extends PanelContainer
## Prompt shown while the player looks at a door they could walk through.
## Presentation only: it shows what the host says about the door.
##
## info = {
##   "cost": 3,          # points the door costs
##   "capacity": 2,      # places this round
##   "reserved": 0,      # places held by players who have not crossed yet
##   "available": 2,     # optional: places still free (capacity - used - reserved)
##   "locked": false,    # optional: temporary lockdown
##   "exit": false,      # optional: the real exit door (free, no places)
## }

@export var interact_action := &"interact"

@onready var key_label: Label = %KeyLabel
@onready var action_label: Label = %ActionLabel
@onready var cost_label: Label = %CostLabel
@onready var capacity_label: Label = %CapacityLabel
@onready var status_label: Label = %StatusLabel
@onready var room_label: Label = %RoomLabel

var _last_info := {}
var _last_points := -1
var _fade: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0


func show_for_door(info: Dictionary, player_points: int) -> void:
	if visible and info == _last_info and player_points == _last_points:
		return   # nothing changed since the last call
	_last_info = info.duplicate()
	_last_points = player_points

	var cost: int = info.get("cost", 0)
	var capacity: int = info.get("capacity", 0)
	var reserved: int = info.get("reserved", 0)
	var locked: bool = info.get("locked", false)
	var remaining: int = info.get("available", maxi(capacity - reserved, 0))
	var is_exit: bool = info.get("exit", false)

	room_label.text = "BEHIND: " + str(info.get("room_behind", "UNKNOWN"))

	var usable := false
	var message := ""
	var message_colour := UIStyle.RED
	if is_exit:
		usable = not locked
		message = "DOOR LOCKED" if locked else "THE WAY OUT"
		message_colour = UIStyle.RED if locked else UIStyle.AMBER
	elif locked or capacity <= 0:
		message = "DOOR CLOSED"
	elif remaining <= 0:
		message = "NO PLACES LEFT"
	elif player_points < cost:
		message = "NOT ENOUGH POINTS  (NEED %d, HAVE %d)" % [cost, player_points]
	elif player_points - cost <= 0:
		usable = true
		message = "WARNING: THIS LEAVES YOU AT 0 POINTS"
	else:
		usable = true
		message = "YOU WILL HAVE %d POINTS LEFT" % (player_points - cost)
		message_colour = UIStyle.AMBER

	key_label.text = _key_text()
	key_label.add_theme_color_override("font_color", UIStyle.AMBER if usable else UIStyle.TEXT_DISABLED)
	action_label.text = ("OPEN / CLOSE EXIT" if is_exit else "RESERVE A PLACE") if usable else "UNAVAILABLE"
	action_label.add_theme_color_override("font_color", UIStyle.TEXT if usable else UIStyle.TEXT_DISABLED)
	cost_label.text = "FREE" if is_exit else "COST  %02d PTS" % cost
	capacity_label.text = "EXIT" if is_exit else "PLACES  %02d / %02d" % [remaining, capacity]
	status_label.text = message
	status_label.add_theme_color_override("font_color", message_colour)

	if not visible:
		visible = true
	_fade_to(1.0, false)


func hide_prompt() -> void:
	if not visible:
		return
	_last_info = {}
	_last_points = -1
	_fade_to(0.0, true)


func _fade_to(alpha: float, hide_after: bool) -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", alpha, UIStyle.DUR_FAST)
	if hide_after:
		_fade.tween_callback(func() -> void: visible = false)


## The key the player has bound to the interact action, as text ("E").
func _key_text() -> String:
	if InputMap.has_action(interact_action):
		for ev in InputMap.action_get_events(interact_action):
			if ev is InputEventKey:
				if ev.physical_keycode != KEY_NONE:
					return ev.as_text_physical_keycode()
				return ev.as_text_keycode()
			return ev.as_text()
	return "E"
