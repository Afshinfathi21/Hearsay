class_name PlayerListEntry
extends HBoxContainer
## One row of the multiplayer list.
##   alive          : amber marker, white points
##   alive, in danger (low points) : red marker, red points
##   eliminated     : dim row, dark red marker

@onready var status_mark: ColorRect = %StatusMark
@onready var name_label: Label = %NameLabel
@onready var room_label: Label = %RoomLabel
@onready var points_label: Label = %PointsLabel

var player_id := -1


## p: { "id": int, "name": String, "points": int, "alive": bool, "room": String (optional) }
func set_data(p: Dictionary, is_local: bool, low_threshold: int) -> void:
	player_id = p.get("id", -1)
	var alive: bool = p.get("alive", true)
	var points: int = p.get("points", 0)
	var room := str(p.get("room", ""))

	name_label.text = str(p.get("name", "?")).to_upper()
	points_label.text = str(points)
	room_label.text = room
	room_label.visible = room != "" and alive

	var mark := UIStyle.AMBER
	var points_colour := UIStyle.TEXT
	var name_colour := UIStyle.AMBER if is_local else UIStyle.TEXT
	if not alive:
		mark = UIStyle.RED_DIM
		points_colour = UIStyle.TEXT_DISABLED
		name_colour = UIStyle.TEXT_DISABLED
	elif points <= low_threshold:
		mark = UIStyle.RED
		points_colour = UIStyle.RED
	status_mark.color = mark
	points_label.add_theme_color_override("font_color", points_colour)
	name_label.add_theme_color_override("font_color", name_colour)

	var target_alpha := 1.0 if alive else 0.55
	if not is_equal_approx(modulate.a, target_alpha):
		create_tween().tween_property(self, "modulate:a", target_alpha, UIStyle.DUR_NORMAL)
