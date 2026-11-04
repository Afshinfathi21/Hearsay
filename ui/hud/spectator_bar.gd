class_name SpectatorBar
extends PanelContainer
## Shown at the bottom of the screen while the local player watches others
## (after being eliminated, or after escaping). Left / Right switch player.
## Presentation only: it tells the game which player to watch (target_changed)
## and the game moves the camera.

signal target_changed(player_id: int)   # -1 = nobody left to watch
signal started
signal stopped

@onready var prev_button: Button = %PrevButton
@onready var next_button: Button = %NextButton
@onready var name_label: Label = %NameLabel
@onready var detail_label: Label = %DetailLabel

var is_active := false

var _others: Array = []      # living players other than the local one
var _current_id := -1


func _ready() -> void:
	visible = false
	prev_button.pressed.connect(_step.bind(-1))
	next_button.pressed.connect(_step.bind(1))


func begin() -> void:
	if is_active:
		return
	is_active = true
	visible = true
	_current_id = -2        # forces target_changed to fire for the first target
	_ensure_target()
	started.emit()


func end() -> void:
	if not is_active:
		return
	is_active = false
	visible = false
	stopped.emit()


## Called by GameHUD every time the host sends a new state.
func set_players(players: Array, local_id: int) -> void:
	_others.clear()
	for p: Dictionary in players:
		if p.get("id", -2) != local_id and p.get("alive", true):
			_others.append(p)
	if is_active:
		_ensure_target()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event.is_action_pressed("ui_left"):
		_step(-1)
	elif event.is_action_pressed("ui_right"):
		_step(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _ensure_target() -> void:
	for p: Dictionary in _others:
		if p.get("id", -1) == _current_id:
			_update_labels()
			return
	# The watched player is gone (or this is the first target): pick the first living one.
	_current_id = _others[0].get("id", -1) if not _others.is_empty() else -1
	target_changed.emit(_current_id)
	_update_labels()


func _step(direction: int) -> void:
	if _others.size() < 2:
		return
	var index := 0
	for i in _others.size():
		if _others[i].get("id", -1) == _current_id:
			index = i
	_current_id = _others[posmod(index + direction, _others.size())].get("id", -1)
	target_changed.emit(_current_id)
	_update_labels()


func _update_labels() -> void:
	prev_button.disabled = _others.size() < 2
	next_button.disabled = _others.size() < 2
	for p: Dictionary in _others:
		if p.get("id", -1) == _current_id:
			name_label.text = str(p.get("name", "?")).to_upper()
			var detail := "%02d PTS" % int(p.get("points", 0))
			var room := str(p.get("room", ""))
			if room != "":
				detail += "   ROOM %s" % room
			detail_label.text = detail
			return
	name_label.text = "NO ONE LEFT TO WATCH"
	detail_label.text = ""
