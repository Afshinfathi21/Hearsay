class_name MatchResults
extends Control
## The results of a finished match: every player ranked, with how it ended for them, and
## optional statistics for the local player. Presentation only.
##
## info = {
##   "local_id": 1,
##   "players": [ {"id": 1, "name": "Kai", "rank": 1, "outcome": "escaped", "points": 5}, ... ],
##   "stats": [ {"label": "Rounds", "value": "07"}, ... ],     # optional, the local player's
## }

signal lobby_requested
signal menu_requested

@export var row_scene: PackedScene
@export var stat_row_scene: PackedScene

@onready var summary_label: Label = %SummaryLabel
@onready var rows: VBoxContainer = %Rows
@onready var stats_caption: Label = %StatsCaption
@onready var stats: VBoxContainer = %Stats
@onready var lobby_button: Button = %LobbyButton
@onready var menu_button: Button = %MenuButton


func _ready() -> void:
	lobby_button.pressed.connect(lobby_requested.emit)
	menu_button.pressed.connect(menu_requested.emit)


func show_results(info: Dictionary) -> void:
	var local_id: int = info.get("local_id", -1)
	var players: Array = info.get("players", []).duplicate()
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rank", 99)) < int(b.get("rank", 99)))

	_clear(rows)
	var escaped := 0
	var eliminated := 0
	for p: Dictionary in players:
		var row := row_scene.instantiate() as ResultsRow
		rows.add_child(row)
		row.set_data(int(p.get("rank", 0)), p, p.get("id", -2) == local_id)
		match str(p.get("outcome", "")):
			"escaped": escaped += 1
			"eliminated": eliminated += 1
	summary_label.text = "%d ESCAPED   /   %d ELIMINATED" % [escaped, eliminated]

	_clear(stats)
	var list: Array = info.get("stats", [])
	stats_caption.visible = not list.is_empty()
	for s: Dictionary in list:
		var row := stat_row_scene.instantiate() as ResultStatRow
		stats.add_child(row)
		row.set_data(str(s.get("label", "")), str(s.get("value", "")))

	visible = true
	lobby_button.grab_focus()


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
