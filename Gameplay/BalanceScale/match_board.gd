class_name MatchBoard
extends CanvasLayer
## Top-left overview of every pot: name, acid level (public) and status. Never shows points.

var _rows: Dictionary = {}     # player id -> {name, bar, status}
var _box: VBoxContainer
var _panel: PanelContainer


func _ready() -> void:
	layer = 7
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.position = Vector2(20, 120)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.05, 0.8)
	style.border_color = Color(0.45, 0.8, 0.25, 0.8)
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_box)
	var title := Label.new()
	title.text = "ACID POTS"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.7, 0.95, 0.35)
	_box.add_child(title)


func update_view(view: Dictionary, local_id: int) -> void:
	_panel.visible = true
	var capacity: int = view["capacity"]
	for p in view["players"]:
		var id: int = p["id"]
		if not _rows.has(id):
			var row := VBoxContainer.new()
			var line := HBoxContainer.new()
			var name_label := Label.new()
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var status := Label.new()
			line.add_child(name_label)
			line.add_child(status)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(210, 10)
			row.add_child(line)
			row.add_child(bar)
			_box.add_child(row)
			_rows[id] = {"row": row, "name": name_label, "bar": bar, "status": status}
		var r: Dictionary = _rows[id]
		(r["name"] as Label).text = ("%s (YOU)" % p["name"]) if id == local_id else str(p["name"])
		var bar_node := r["bar"] as ProgressBar
		bar_node.max_value = capacity
		bar_node.value = mini(p["acid"], capacity)
		var ratio := float(p["acid"]) / float(maxi(capacity, 1))
		var color := Color(0.72, 0.95, 0.22)
		if p["acid"] > capacity: color = Color(0.5, 0.5, 0.5)
		elif ratio >= 1.0: color = Color(1.0, 0.18, 0.1)
		elif ratio >= 0.8: color = Color(1.0, 0.5, 0.12)
		elif ratio >= 0.6: color = Color(0.95, 0.85, 0.2)
		bar_node.modulate = color
		var status_label := r["status"] as Label
		if not p["alive"]:
			status_label.text = "OUT"
			status_label.modulate = Color(1.0, 0.3, 0.25)
			(r["name"] as Label).modulate = Color(1, 1, 1, 0.4)
		elif ratio >= 1.0:
			status_label.text = "CRITICAL  %d/%d" % [p["acid"], capacity]
			status_label.modulate = Color(1.0, 0.3, 0.25)
		else:
			var tag := "✓ LOCKED" if p["locked"] else ""
			status_label.text = ("%d/%d  %s" % [p["acid"], capacity, tag]).strip_edges()
			status_label.modulate = Color.WHITE
