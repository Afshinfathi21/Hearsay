class_name ConnectionOverlay
extends Control
## Connection status for menus and matches.
##   set_status("connecting" | "reconnecting" | "connected" | "hidden", detail)
##        a small banner at the top of the screen; it never blocks input
##   show_lost(reason, can_retry)
##        a dialog that does block, for a connection that is gone
## Presentation only: your networking code reports what is happening.
## Players disconnecting from the match are ordinary notifications:
##   hud.notify({"type": "info", "title": "MIRA DISCONNECTED"})

signal retry_requested
signal menu_requested
signal blocking_changed

## Distance of the banner from the top of the screen (the HUD moves it below the round info).
@export var banner_top := 32.0

@onready var banner: PanelContainer = %Banner
@onready var mark: ColorRect = %Mark
@onready var message_label: Label = %MessageLabel
@onready var detail_label: Label = %DetailLabel
@onready var lost_dialog: Control = %LostDialog
@onready var reason_label: Label = %ReasonLabel
@onready var retry_button: Button = %RetryButton
@onready var menu_button: Button = %MenuButton

var is_blocking := false

var _pulse: Tween
var _hide_tween: Tween


func _ready() -> void:
	banner.offset_top = banner_top
	banner.offset_bottom = banner_top
	banner.visible = false
	lost_dialog.visible = false
	retry_button.pressed.connect(_on_retry)
	menu_button.pressed.connect(_on_menu)


func set_status(kind: String, detail := "") -> void:
	if _pulse:
		_pulse.kill()
	if _hide_tween:
		_hide_tween.kill()
	mark.modulate.a = 1.0
	match kind:
		"connecting":
			_show_banner("CONNECTING", detail, UIStyle.AMBER, true)
		"reconnecting":
			_show_banner("CONNECTION UNSTABLE   RECONNECTING", detail, UIStyle.AMBER, true)
		"connected":
			_show_banner("CONNECTED", detail, UIStyle.AMBER, false)
			_hide_tween = create_tween()
			_hide_tween.tween_interval(1.5)
			_hide_tween.tween_callback(func() -> void: banner.visible = false)
		_:
			banner.visible = false


func show_lost(reason: String, can_retry := false) -> void:
	set_status("hidden")
	reason_label.text = reason.to_upper()
	retry_button.visible = can_retry
	lost_dialog.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(retry_button if can_retry else menu_button).grab_focus()
	_set_blocking(true)


func hide_lost() -> void:
	lost_dialog.visible = false
	_set_blocking(false)


func _show_banner(message: String, detail: String, colour: Color, pulse: bool) -> void:
	banner.visible = true
	message_label.text = message
	detail_label.text = detail
	detail_label.visible = detail != ""
	mark.color = colour
	if pulse:
		_pulse = create_tween().set_loops()
		_pulse.tween_property(mark, "modulate:a", 0.25, 0.5).set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(mark, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)


func _on_retry() -> void:
	hide_lost()
	set_status("connecting")
	retry_requested.emit()


func _on_menu() -> void:
	hide_lost()
	menu_requested.emit()


func _set_blocking(value: bool) -> void:
	if is_blocking != value:
		is_blocking = value
		blocking_changed.emit()
