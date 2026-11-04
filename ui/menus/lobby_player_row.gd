class_name LobbyPlayerRow
extends HBoxContainer
## One player in the lobby list.

@onready var status_mark: ColorRect = %StatusMark
@onready var name_label: Label = %NameLabel
@onready var tag_label: Label = %TagLabel
@onready var ready_label: Label = %ReadyLabel
@onready var ping_label: Label = %PingLabel

var player_id := -1


## p: { "id": int, "name": String, "ready": bool, "host": bool, "ping": int (ms, optional) }
func set_data(p: Dictionary, is_local: bool) -> void:
	player_id = p.get("id", -1)
	var ready: bool = p.get("ready", false)
	name_label.text = str(p.get("name", "?")).to_upper()
	name_label.add_theme_color_override("font_color", UIStyle.AMBER if is_local else UIStyle.TEXT)
	var tags: Array[String] = []
	if p.get("host", false):
		tags.append("HOST")
	if is_local:
		tags.append("YOU")
	tag_label.text = "  ".join(tags)
	ready_label.text = "READY" if ready else "NOT READY"
	ready_label.add_theme_color_override("font_color", UIStyle.AMBER if ready else UIStyle.TEXT_MUTED)
	status_mark.color = UIStyle.AMBER if ready else UIStyle.METAL_LIGHT
	var ping: int = p.get("ping", -1)
	ping_label.text = "%d MS" % ping if ping >= 0 else ""
