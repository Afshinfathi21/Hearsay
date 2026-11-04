class_name TransferTargetRow
extends Button
## One selectable player in the transfer panel (name on the left, balance on the right).

@onready var points_label: Label = %PointsLabel

var player_id := -1
var points := 0


## p: { "id": int, "name": String, "points": int, ... }
func set_data(p: Dictionary) -> void:
	player_id = p.get("id", -1)
	points = p.get("points", 0)
	text = str(p.get("name", "?")).to_upper()
	points_label.text = "%02d PTS" % points
