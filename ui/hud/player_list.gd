class_name PlayerList
extends PanelContainer
## All players in the match. Entries are created, updated and removed to match
## the list the host sends; nothing here changes game state.

@export var entry_scene: PackedScene
@export var low_points_threshold := 3

@onready var count_label: Label = %CountLabel
@onready var rows: VBoxContainer = %Rows

var _entries := {}   # player id -> PlayerListEntry


func set_players(players: Array, local_id: int) -> void:
	assert(entry_scene != null, "PlayerList: assign Entry Scene in the Inspector.")

	# Living players first, eliminated ones last; otherwise keep the host's order.
	var ordered: Array = []
	for p: Dictionary in players:
		if p.get("alive", true):
			ordered.append(p)
	var alive_count := ordered.size()
	for p: Dictionary in players:
		if not p.get("alive", true):
			ordered.append(p)

	var seen := {}
	for i in ordered.size():
		var p: Dictionary = ordered[i]
		var id: int = p.get("id", -1)
		seen[id] = true
		var entry: PlayerListEntry = _entries.get(id)
		if entry == null:
			entry = entry_scene.instantiate() as PlayerListEntry
			rows.add_child(entry)
			_entries[id] = entry
		entry.set_data(p, id == local_id, low_points_threshold)
		rows.move_child(entry, i)

	for id in _entries.keys():
		if not seen.has(id):
			(_entries[id] as Node).queue_free()
			_entries.erase(id)

	count_label.text = "%d / %d ALIVE" % [alive_count, players.size()]
