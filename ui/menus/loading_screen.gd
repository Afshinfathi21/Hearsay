class_name LoadingScreen
extends Control
## Shown while a match loads. Presentation only: your code reports the progress.

@onready var status_label: Label = %StatusLabel
@onready var bar: ProgressBar = %Bar

var _tween: Tween


## status: what is happening now ("GENERATING THE BUILDING", "WAITING FOR PLAYERS  3 / 4").
func show_loading(status := "LOADING") -> void:
	bar.value = 0.0
	set_status(status)
	visible = true


func set_status(text: String) -> void:
	status_label.text = text.to_upper()


## progress: 0.0 to 1.0
func set_progress(progress: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(bar, "value", clampf(progress, 0.0, 1.0) * bar.max_value, UIStyle.DUR_NORMAL)


func hide_loading() -> void:
	visible = false
