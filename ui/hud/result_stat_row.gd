class_name ResultStatRow
extends HBoxContainer
## One "LABEL ......... value" line of a results list.

@onready var label: Label = %StatLabel
@onready var value_label: Label = %StatValue


func set_data(stat_label: String, stat_value: String) -> void:
	label.text = stat_label.to_upper()
	value_label.text = stat_value
