class_name ResultsRow
extends HBoxContainer
## One player's line in the match results.

@onready var rank_label: Label = %RankLabel
@onready var name_label: Label = %NameLabel
@onready var outcome_label: Label = %OutcomeLabel
@onready var points_label: Label = %PointsLabel


## p: { "name": String, "outcome": "escaped" | "eliminated" | anything else, "points": int }
func set_data(rank: int, p: Dictionary, is_local: bool) -> void:
	rank_label.text = "%02d" % rank if rank > 0 else "--"
	name_label.text = str(p.get("name", "?")).to_upper()
	name_label.add_theme_color_override("font_color", UIStyle.AMBER if is_local else UIStyle.TEXT)
	match str(p.get("outcome", "")):
		"escaped":
			outcome_label.text = "ESCAPED"
			outcome_label.add_theme_color_override("font_color", UIStyle.AMBER)
		"eliminated":
			outcome_label.text = "ELIMINATED"
			outcome_label.add_theme_color_override("font_color", UIStyle.RED)
		_:
			outcome_label.text = "-"
			outcome_label.add_theme_color_override("font_color", UIStyle.TEXT_MUTED)
	points_label.text = "%02d" % int(p.get("points", 0))
