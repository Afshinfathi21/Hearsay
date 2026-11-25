class_name SeatingController
extends Node
## Makes every player take a chair before the Balance Scale game starts, and keeps them
## in it until the game is over.
##
##   1. SEATING   players walk up to a free chair, look at it and press E (interact).
##   2. PLAYING   once every expected player is seated, `all_seated` fires. Seated players
##                cannot stand, but can still look around and use the HUD (Esc menu etc.).
##   3. GAME_OVER call end_game() (or bind_game(balance_scale_game)); players may now
##                press E to stand up again.
##
## This node also connects the GameHUD's pause menu (Esc) to the player so the mouse is
## freed and movement stops while a HUD panel is open.

signal player_seated(player: Node3D, seat: AuctionSeat)
signal all_seated
signal player_stood(player: Node3D)
signal game_over

enum State { SEATING, PLAYING, GAME_OVER }

@export var hud: GameHUD
## Node whose children are the AuctionSeat chairs.
@export var seats_root: Node
## How many players must be seated before the game starts. For a networked match set this
## to the number of players in the match; 0 = however many players are in this scene.
@export var expected_players := 0
@export var interact_distance := 3.0
## How far from the exact line of sight a chair may be and still be picked (degrees).
@export_range(5.0, 80.0) var aim_cone_deg := 40.0
## false = players may stand up whenever they like (for testing).
@export var lock_until_game_over := true

var state := State.SEATING
var seats: Array[AuctionSeat] = []

var _prompt: Label
var _modal := false
var _locked_msg_cooldown := 0.0


func _ready() -> void:
	_ensure_interact_action()
	if seats_root != null:
		for n in seats_root.find_children("*", "Node3D", true, false):
			if n is AuctionSeat:
				seats.append(n)
	_build_prompt()
	if hud != null:
		hud.modal_opened.connect(_on_modal_opened)
		hud.modal_closed.connect(_on_modal_closed)
		hud.leave_match_requested.connect(_on_leave_match)
		hud.quit_requested.connect(get_tree().quit)
		await get_tree().process_frame
		hud.notify({"type": "info", "title": "TAKE YOUR SEAT",
			"detail": "LOOK AT A CHAIR AND PRESS E. NOBODY LEAVES UNTIL THE GAME ENDS"})


## Call when the game is over (or connect it to BalanceScaleGame.game_ended with bind_game).
func end_game() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	game_over.emit()
	if hud != null:
		hud.notify({"type": "info", "title": "GAME OVER", "detail": "LOOK AT YOUR CHAIR AND PRESS E TO STAND"})


func bind_game(game: BalanceScaleGame) -> void:
	game.game_ended.connect(func(_winner_id: int) -> void: end_game())


func get_players() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node3D:
			out.append(n)
	return out


func _process(delta: float) -> void:
	_locked_msg_cooldown = maxf(0.0, _locked_msg_cooldown - delta)
	var player := _local_player()
	if player == null:
		_prompt.visible = false
		return

	var pressed := Input.is_action_just_pressed("interact") and not _modal
	if player.seated:
		_prompt.visible = state == State.GAME_OVER and not _modal
		_prompt.text = "[E]  STAND UP"
		if pressed:
			if _can_stand():
				_stand(player)
			elif _locked_msg_cooldown <= 0.0 and hud != null:
				_locked_msg_cooldown = 2.0
				hud.notify({"type": "info", "title": "STAY SEATED", "detail": "YOU CANNOT LEAVE YOUR CHAIR UNTIL THE GAME IS OVER"})
		return

	var seat := _seat_in_view(player)
	_prompt.visible = seat != null and not _modal
	_prompt.text = "[E]  SIT"
	if pressed and seat != null:
		_sit(player, seat)


func _local_player() -> Node3D:
	var players := get_players()
	return players[0] if players.size() > 0 else null


func _can_stand() -> bool:
	return state == State.GAME_OVER or not lock_until_game_over


## The free chair the player is looking at (closest to the line of sight), or null.
func _seat_in_view(player: Node3D) -> AuctionSeat:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var eye: Vector3 = player.head.global_position
	var look := -cam.global_transform.basis.z
	var best: AuctionSeat = null
	var best_angle := deg_to_rad(aim_cone_deg)
	for seat in seats:
		if not seat.is_free():
			continue
		var to_seat := seat.get_aim_position() - eye
		if to_seat.length() > interact_distance:
			continue
		var angle := look.angle_to(to_seat)
		if angle < best_angle:
			best_angle = angle
			best = seat
	return best


func _sit(player: Node3D, seat: AuctionSeat) -> void:
	seat.take(player)
	player.sit_down(seat, seat.get_sit_position(), seat.get_forward())
	player_seated.emit(player, seat)
	if hud != null:
		hud.notify({"type": "info", "title": "SEATED", "detail": "%d OF %d PLAYERS READY" % [_seated_count(), _needed()]})
	_check_all_seated()


func _stand(player: Node3D) -> void:
	var seat: AuctionSeat = player.seat
	player.stand_up(seat.get_stand_position() + Vector3.UP * 0.95 if seat != null else player.global_position)
	if seat != null:
		seat.release()
	player_stood.emit(player)


func _seated_count() -> int:
	var n := 0
	for p in get_players():
		if p.seated:
			n += 1
	return n


func _needed() -> int:
	return maxi(expected_players, get_players().size())


func _check_all_seated() -> void:
	if state != State.SEATING or _seated_count() < _needed():
		return
	state = State.PLAYING
	all_seated.emit()
	if hud != null:
		hud.notify({"type": "info", "title": "ALL PLAYERS SEATED", "detail": "THE GAME BEGINS"})


func _on_modal_opened() -> void:
	_modal = true
	for p in get_players():
		p.input_blocked = true


func _on_modal_closed() -> void:
	_modal = false
	for p in get_players():
		p.input_blocked = false


func _on_leave_match() -> void:
	get_tree().change_scene_to_file("res://ui/menus/start_scene.tscn")


func _build_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	_prompt = Label.new()
	_prompt.visible = false
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.offset_left = 0.0
	_prompt.offset_right = 0.0
	_prompt.offset_top = -170.0
	_prompt.add_theme_font_size_override("font_size", 26)
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("outline_size", 8)
	layer.add_child(_prompt)


func _ensure_interact_action() -> void:
	if InputMap.has_action("interact"):
		return
	InputMap.add_action("interact")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	InputMap.action_add_event("interact", ev)
