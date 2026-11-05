class_name DontBlinkRoom
extends Node3D
## The "Don't Blink" mini-game inside one room: a giant eye in the ceiling, a START pad and an EXIT pad, and the
## room lights that flash with the eye. The rules are in DontBlinkGame; this node only measures how fast the
## players move, feeds the rules, and shows the outcome. Add it as a child of the building generator, then
## call setup(). The host (SoloMatch for now) listens to the signals and hands out the reward.
##
## How a player plays it: step on the amber START pad (a short countdown begins, others may join), then cross the
## room to the green EXIT pad. While the eye is open you must not move. A reward (a TRAP SCAN: a hint about one
## nearby room) is given the moment a player reaches the EXIT pad.

signal player_won(room_label: String, player_id: int)
signal player_detected(room_label: String, player_id: int)
## What the HUD should show for the local player: see MiniGamePanel. {} = nothing (hide it).
signal hud_state_changed(state: Dictionary)

const TITLE := "DON'T BLINK"
const LOCAL_ID := 1                      # the player on this machine, until the network layer assigns ids
const CEILING := 3.0                     # interior height above the floor
const EYE_RADIUS := 1.8
const EYE_SINK := 1.2                    # the eye's centre is this far into the ceiling (its lowest point stays above head height)
const PAD_RADIUS := 1.2
const BOUNDS_MARGIN := 0.3               # beyond the room walls by this much = the player left
const DARK_LIGHT := 0.2                  # share of the room lights that stays on while the eye is shut
const WATCH_LIGHT := 2.2                 # the room lights flash this bright while the eye is open
const TELEPORT_DISTANCE := 2.0           # a jump this big in one frame is a teleport, not movement
const RESULT_SECONDS := 3.0              # how long the result stays before the room can be played again
const EVENT_SECONDS := 1.5               # how long "THE EYE SAW YOU" stays on the HUD

var game := DontBlinkGame.new()
var room_label := ""
## Set when the reward was handed out: the room stays calm and cannot be played again.
var claimed := false
## (body) -> player id, or -1 when the body is not a player. Default: the local player group is id 1.
var id_resolver := Callable()

var _generator: Node3D
var _half := 6.0
var _bodies := {}                        # player id -> the body taking part
var _last_pos := {}
var _open := 0.0                         # 0 = eye shut, 1 = eye open
var _light_mul := 1.0
var _end_left := 0.0
var _event_text := ""
var _event_left := 0.0
var _flash := false
var _last_hud_key := ""

var _eye_root: Node3D
var _look: Node3D
var _lid_pivot: Node3D
var _iris_mat: StandardMaterial3D
var _eye_light: OmniLight3D
var _room_lights: Array[Dictionary] = []
var _start_pad := {}
var _finish_pad := {}


## The node must already be in the tree (add_child first). rd: the RoomData of the room.
func setup(generator: Node3D, rd, seed_value: int) -> void:
	_generator = generator
	room_label = rd.label
	_half = float(generator.room_cells) * RoomGrid.CELL_SIZE.x * 0.5
	game.rng.seed = seed_value
	global_position = generator.get_room_floor_center(rd)
	_build_eye()
	var corner := _half - 2.4
	_start_pad = _build_pad("START", Vector3(-corner, 0.0, -corner), UIStyle.AMBER, _on_start_entered)
	_finish_pad = _build_pad("EXIT", Vector3(corner, 0.0, corner), Color(0.35, 0.9, 0.45), _on_finish_entered)
	for n in generator.get_children():
		if n is OmniLight3D:
			var p: Vector3 = (n as Node3D).global_position - global_position
			if absf(p.x) <= _half and absf(p.z) <= _half:
				_room_lights.append({"light": n, "base": (n as OmniLight3D).light_energy})
	game.player_detected.connect(_on_detected)
	game.player_won.connect(func(id: int) -> void: player_won.emit(room_label, id))
	game.ended.connect(func() -> void: _end_left = RESULT_SECONDS)


## The reward was handed out: the eye sleeps for good.
func mark_claimed() -> void:
	claimed = true
	game.reset()
	_bodies.clear()
	_last_pos.clear()
	for pad in [_start_pad, _finish_pad]:
		(pad["label"] as Label3D).text = "DONE"
		(pad["label"] as Label3D).modulate = UIStyle.TEXT_MUTED
		((pad["disc"] as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = 0.15


func _physics_process(delta: float) -> void:
	if _generator == null:
		return
	var speeds := {}
	for id in _bodies.keys():
		var body := _bodies[id] as Node3D
		if not is_instance_valid(body):
			_drop(id)
			continue
		var p := body.global_position
		if absf(p.x - global_position.x) > _half + BOUNDS_MARGIN or absf(p.z - global_position.z) > _half + BOUNDS_MARGIN:
			_drop(id)                                    # walked out of the room: no result, no penalty
			continue
		var moved := p.distance_to(_last_pos[id])
		_last_pos[id] = p
		speeds[id] = 0.0 if moved > TELEPORT_DISTANCE else moved / maxf(delta, 0.0001)
	game.tick(delta, speeds)
	if _end_left > 0.0:
		_end_left -= delta
		if _end_left <= 0.0:
			game.reset()
			_bodies.clear()
			_last_pos.clear()
	_event_left = maxf(_event_left - delta, 0.0)
	_update_visuals(delta)
	_emit_hud()


func _drop(id: int) -> void:
	_bodies.erase(id)
	_last_pos.erase(id)
	game.leave(id)


func _id_of(body: Node3D) -> int:
	if id_resolver.is_valid():
		return int(id_resolver.call(body))
	return LOCAL_ID if body.is_in_group("player") else -1


func _on_start_entered(body: Node3D) -> void:
	var id := _id_of(body)
	if id < 0 or claimed or _end_left > 0.0:
		return
	if game.join(id):
		_bodies[id] = body
		_last_pos[id] = body.global_position


func _on_finish_entered(body: Node3D) -> void:
	var id := _id_of(body)
	if id >= 0 and not claimed:
		game.finish(id)


func _on_detected(id: int) -> void:
	player_detected.emit(room_label, id)
	_event_text = "THE EYE SAW YOU" if id == LOCAL_ID else "THE EYE SAW SOMEONE"
	_event_left = EVENT_SECONDS
	if id == LOCAL_ID:
		_flash = true


# ---- what the HUD shows ------------------------------------------------------------------------------
func _emit_hud() -> void:
	var state := _hud_state()
	var key := str(state)
	if key == _last_hud_key and not state.get("flash", false):
		return
	_last_hud_key = key
	hud_state_changed.emit(state)
	_flash = false


func _hud_state() -> Dictionary:
	var status := game.status_of(LOCAL_ID)
	if status == "" or status == "left":
		return {}
	var phase := "countdown"
	if status == "won" or status == "lost":
		phase = status
	elif game.state == DontBlinkGame.State.RUNNING:
		phase = "watching" if game.watching else "dark"
	return {"title": TITLE, "phase": phase, "countdown": ceili(game.countdown_left()), "danger": game.danger,
		"max_danger": game.max_danger, "time_left": snappedf(game.time_left(), 1.0),
		"event": _event_text if _event_left > 0.0 else "", "flash": _flash}


# ---- the eye, the pads, the lights ------------------------------------------------------------------
func _build_eye() -> void:
	_eye_root = Node3D.new()
	_eye_root.name = "Eye"
	_eye_root.position = Vector3(0.0, CEILING + EYE_SINK, 0.0)
	add_child(_eye_root)

	var ball := MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = EYE_RADIUS
	ball_mesh.height = EYE_RADIUS * 2.0
	ball.mesh = ball_mesh
	ball.material_override = _material(Color(0.93, 0.9, 0.84), Color(0.3, 0.28, 0.25), 0.25, 0.4)
	_eye_root.add_child(ball)

	_look = Node3D.new()                                 # turns toward the player; the iris is on its far side
	_eye_root.add_child(_look)
	_iris_mat = _material(Color(0.9, 0.55, 0.1), Color(1.0, 0.65, 0.12), 0.2, 0.3)
	_look.add_child(_disc_mesh(EYE_RADIUS * 0.54, 0.3, Vector3(0.0, -EYE_RADIUS * 0.93, 0.0), _iris_mat))
	_look.add_child(_disc_mesh(EYE_RADIUS * 0.235, 0.35, Vector3(0.0, -EYE_RADIUS * 1.04, 0.0), _material(Color(0.01, 0.01, 0.01), Color.BLACK, 0.0, 0.2)))

	_lid_pivot = Node3D.new()                            # a hemisphere that swings over the eye: the eyelid
	_eye_root.add_child(_lid_pivot)
	var lid := MeshInstance3D.new()
	var lid_mesh := SphereMesh.new()
	lid_mesh.radius = EYE_RADIUS * 1.22                  # big enough to hide the iris, which bulges out of the eyeball
	lid_mesh.height = EYE_RADIUS * 1.22
	lid_mesh.is_hemisphere = true
	lid.mesh = lid_mesh
	lid.material_override = _material(Color(0.1, 0.06, 0.06), Color.BLACK, 0.0, 0.9)
	_lid_pivot.add_child(lid)
	_lid_pivot.rotation.x = PI                           # dome down = shut

	_eye_light = OmniLight3D.new()
	_eye_light.position = Vector3(0.0, -EYE_RADIUS - 0.3, 0.0)
	_eye_light.omni_range = 18.0
	_eye_light.light_energy = 0.0
	_eye_root.add_child(_eye_light)


func _disc_mesh(radius: float, flat: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	m.mesh = s
	m.scale = Vector3(1.0, flat, 1.0)
	m.position = at
	m.material_override = mat
	return m


func _material(albedo: Color, emission: Color, energy: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.emission_enabled = energy > 0.0
	m.emission = emission
	m.emission_energy_multiplier = energy
	return m


func _build_pad(text: String, at: Vector3, color: Color, on_enter: Callable) -> Dictionary:
	var root := Node3D.new()
	root.position = at
	add_child(root)
	var cyl := CylinderMesh.new()
	cyl.top_radius = PAD_RADIUS
	cyl.bottom_radius = PAD_RADIUS
	cyl.height = 0.04
	var disc := MeshInstance3D.new()
	disc.mesh = cyl
	disc.position.y = 0.02
	disc.material_override = _material(color * 0.4, color, 1.4, 0.6)
	root.add_child(disc)
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 72
	label.pixel_size = 0.0035
	label.outline_size = 14
	label.modulate = color
	label.position.y = 1.5
	root.add_child(label)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = PAD_RADIUS
	cs.height = 2.0
	shape.shape = cs
	shape.position.y = 1.0
	area.add_child(shape)
	root.add_child(area)
	area.body_entered.connect(on_enter)
	return {"root": root, "disc": disc, "label": label, "area": area}


func _update_visuals(delta: float) -> void:
	var running := game.state == DontBlinkGame.State.RUNNING
	_open = move_toward(_open, 1.0 if (running and game.watching) else 0.0, delta * 8.0)
	_lid_pivot.rotation.x = lerpf(PI, 0.0, _open)
	var heat := float(game.danger) / float(maxi(game.max_danger, 1))
	var colour := Color(1.0, 0.65, 0.12).lerp(Color(0.9, 0.08, 0.05), heat)
	_iris_mat.albedo_color = colour * 0.55
	_iris_mat.emission = colour
	_iris_mat.emission_energy_multiplier = 0.2 + 1.3 * _open
	_eye_light.light_energy = _open * (3.5 + 2.0 * heat)
	_eye_light.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.35, 0.25), heat)

	var dir := Vector3.DOWN                              # the iris follows the player while the eye is open
	var target := _look_target()
	if target != null and _open > 0.05:
		var want := (target.global_position + Vector3(0.0, 1.4, 0.0) - _eye_root.global_position).normalized()
		var angle := Vector3.DOWN.angle_to(want)
		dir = want if angle <= 0.9 else Vector3.DOWN.slerp(want, 0.9 / angle)
	_look.basis = _look.basis.slerp(Basis(Quaternion(Vector3.DOWN, dir)), clampf(delta * 8.0, 0.0, 1.0))

	var light_target := 1.0                              # the room lights follow the eye
	if running:
		light_target = WATCH_LIGHT if game.watching else DARK_LIGHT
	_light_mul = move_toward(_light_mul, light_target, delta * 12.0)
	for entry in _room_lights:
		var l := entry["light"] as OmniLight3D
		if is_instance_valid(l):
			l.light_energy = float(entry["base"]) * _light_mul


func _look_target() -> Node3D:
	for id in _bodies:
		return _bodies[id] as Node3D
	return null
