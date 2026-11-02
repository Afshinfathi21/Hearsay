extends Node3D
## Generates the building described in the game design:
##   * a square grid of ROOMS (rooms_per_side x rooms_per_side); each room is room_cells x room_cells GridMap
##     cells (3 cells = 12 x 12 m) and is OPEN-PLAN: no walls and no posts inside a room
##   * EVERY pair of neighbouring rooms is joined by one door centred on their shared wall, so
##     centre rooms have 4 doors, edge rooms 3, corner rooms 2 (no dead ends, plenty of loops)
##   * ONE real exit. The exit room is a RANDOM room anywhere in the building. Its exit door has NO room on the
##     other side: if the room is on the perimeter the door leads straight outside; if it is in the middle, ONE
##     neighbouring room is left out, which makes an open-air courtyard behind the door. Only this door's monitor
##     shows a green "EXIT". The start room is then chosen far from the exit room.
##   * a monitor above every door, props that give each room type a recognisable look,
##     per-room penalty data, zones that tell you when a player enters a room, and an exit trigger
## Attach to your level root. The root needs a GridMap child named "GridMap".
## Same seed = same building on every machine (important for multiplayer: generate it on every peer).

signal room_entered(room, body)             # room: RoomData, body: the PhysicsBody3D that entered
signal exit_reached(body)                   # a body walked out of the exit door

const KIND_CORNER := 0
const KIND_EDGE := 1
const KIND_CENTER := 2
const PENALTY_NONE := 0
const PENALTY_LOSE_POINTS := 1              # amount = points lost on entering
const PENALTY_SKIP_ROUND := 2               # the players cannot leave for 'amount' round(s)

const N := RoomGrid.Dir.N
const E := RoomGrid.Dir.E
const S := RoomGrid.Dir.S
const W := RoomGrid.Dir.W
const WALL_FACE := 0.15
const FLOOR_SLAB := 0.2
const OUTSIDE := Vector2i(-1, -1)

const PROPS := {
	"panel": {"path": "res://Assets/Props/prop_electrical_panel.glb", "h": 1.45},
	"camera": {"path": "res://Assets/Props/prop_camera_wall.glb", "h": 2.55},
	"emergency": {"path": "res://Assets/Props/prop_emergency_light.glb", "h": 2.45},
	"speaker": {"path": "res://Assets/Props/prop_speaker_wall.glb", "h": 2.65},
	"plate": {"path": "res://Assets/Props/prop_number_plate.glb", "h": 1.65},
	"wall_panel": {"path": "res://Assets/Environment/env_wall_panel.glb", "h": 1.5},
	"grille": {"path": "res://Assets/Environment/env_grille_wall.glb", "h": 0.55},
	"vent": {"path": "res://Assets/Props/prop_ceiling_vent.glb"},
	"hazard": {"path": "res://Assets/Props/prop_floor_marking_hazard.glb"},
}

@export var rooms_per_side := 7              # 7 rooms x 3 cells x 4 m = 84 m: fits a 100 m base with an 8 m outside strip
@export var room_cells := 3                  # cells per room side; keep it ODD so the door can sit at the exact centre
@export var seed_value := 12345              # 0 = new building every run
@export var base_floor: CSGBox3D             # optional: the building is centred on it and sits on its top face
@export var player: Node3D                   # optional: moved to the first spawn point
@export_range(0.0, 1.0) var penalty_fraction := 0.35
@export var label_rooms := true              # a number plate with the room's name (e.g. "C4") in every room
@export var exit_anywhere := true             # false = the exit may only be on a perimeter room (door straight to the outside)
@export var exit_locked := false
@export var draw_distance := 35.0            # doors, monitors and props are hidden beyond this many metres


class RoomData extends RefCounted:
	var coord := Vector2i.ZERO               # (column, row) in the room grid
	var kind := 0                            # KIND_CORNER / KIND_EDGE / KIND_CENTER
	var penalty := 0                         # PENALTY_*
	var amount := 0
	var doors := 0                           # usable doors, including the exit door
	var is_start := false
	var is_exit := false
	var label := ""                          # e.g. "C4"
	var cells: Array[Vector2i] = []


class DoorRecord extends RefCounted:
	var room_a := Vector2i.ZERO              # the room the door faces into (its owner)
	var room_b := Vector2i(-1, -1)           # the other room, or (-1, -1) for the outside
	var door: Node3D                         # StandardDoor
	var monitors: Array = []                 # [front DoorMonitor, rear DoorMonitor]
	var is_exit := false


var rng := RandomNumberGenerator.new()
var rooms := {}                              # Vector2i -> RoomData
var room_list: Array[RoomData] = []
var door_records: Array[DoorRecord] = []
var start_room := Vector2i.ZERO
var exit_room := Vector2i.ZERO
var has_hole := false                        # true when the exit is inside the building: one neighbouring room is left out
var hole_room := Vector2i(-1, -1)            # grid position of that missing room (an open-air courtyard)
var exit_dir := 0
var start_distance := 0                     # doors between the start room and the exit room
var exit_door: Node3D
var exit_position := Vector3.ZERO            # world position of the exit doorway
var spawn_points: Array[Vector3] = []        # 9 positions in the start room
var placed_props: Array[Dictionary] = []     # {type, cell, dir, node} for every wall prop
var post_positions: Array[Vector2i] = []     # grid-corner coordinates of every post (world = position * 4 m + grid origin)
var door_edges := {}                         # "x,z,dir" -> true for every cell side that holds a door

var _gm: GridMap
var _props_root: Node3D
var _scenes := {}
var _prop_count := 0


func _ready() -> void:
	_gm = $GridMap
	RoomGrid.setup(_gm, null, true)             # the library WITHOUT posts; posts are added below only where walls need them
	if room_cells % 2 == 0:
		push_error("room_cells must be odd so doors can be centred; got %d" % room_cells)
	rng.seed = seed_value if seed_value != 0 else int(Time.get_ticks_usec())
	if base_floor != null:
		_sit_on_base_floor()

	_make_rooms()
	_choose_exit()
	_choose_start()
	_assign_penalties()
	var links := _build_links()
	var cells: Array[Vector2i] = []
	for rd in room_list:
		cells.append_array(rd.cells)
	var exterior := [{"cell": _exit_cell(), "dir": exit_dir}]
	RoomGrid.place_rooms(_gm, cells, links, 0, exterior)
	var posts := RoomGrid.build_posts(_gm, self)
	post_positions.assign(posts.get_meta("positions"))

	var doors := RoomGrid.spawn_doors(_gm, self, load("res://Assets/Doors/door_standard.glb"), load("res://Assets/Monitors/door_monitor.glb"))
	_collect_door_records(doors)

	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)
	_place_props()
	_add_lights()
	_make_room_zones()
	_make_exit_area()
	_finish(doors)


## ---- public helpers for your game logic ----------------------------------------------------------
func get_room_at_position(world_pos: Vector3) -> RoomData:
	var local := _gm.to_local(world_pos)
	var c := Vector2i(floori(local.x / RoomGrid.CELL_SIZE.x), floori(local.z / RoomGrid.CELL_SIZE.z))
	return rooms.get(_room_of(c))


## Plain data describing the whole building (for a minimap, a debug view, or saving). Safe to serialise.
func get_layout() -> Dictionary:
	var rs := []
	for rd in room_list:
		rs.append({"coord": [rd.coord.x, rd.coord.y], "label": rd.label, "kind": rd.kind, "doors": rd.doors,
			"penalty": rd.penalty, "amount": rd.amount, "start": rd.is_start, "exit": rd.is_exit})
	var ds := []
	for r in door_records:
		ds.append({"a": [r.room_a.x, r.room_a.y], "b": [r.room_b.x, r.room_b.y], "exit": r.is_exit})
	return {"rooms_per_side": rooms_per_side, "room_cells": room_cells, "seed": seed_value,
		"start": [start_room.x, start_room.y], "exit_room": [exit_room.x, exit_room.y], "exit_dir": exit_dir,
		"hole": [hole_room.x, hole_room.y] if has_hole else null, "start_distance": start_distance,
		"rooms": rs, "doors": ds}


## Smallest horizontal distance between any two doors in the building, in metres. Doors sit at the centre of their
## walls, so with 12 m rooms two doors in one room are never closer than about 8.5 m.
func get_min_door_distance() -> float:
	var best := INF
	for i in door_records.size():
		for j in range(i + 1, door_records.size()):
			var a: Vector3 = door_records[i].door.global_position
			var b: Vector3 = door_records[j].door.global_position
			best = minf(best, Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)))
	return best


## The door record between two neighbouring rooms (order does not matter), or null.
func get_door_between(a: Vector2i, b: Vector2i) -> DoorRecord:
	for r in door_records:
		if (r.room_a == a and r.room_b == b) or (r.room_a == b and r.room_b == a):
			return r
	return null


## Shows `count` on both monitors of a door and lights that many of the 4 capacity pips.
func set_door_capacity(record: DoorRecord, count: int) -> void:
	for m in record.monitors:
		m.show_number(count)
		m.set_capacity(count)

func set_door_state(record: DoorRecord, capacity: int, reserved: int) -> void:
	if record.door != null and not record.is_exit:
		record.door.set_round_state(capacity, reserved)
# ---- rooms --------------------------------------------------------------------------------------
func _make_rooms() -> void:
	var R := rooms_per_side
	for rz in R:
		for rx in R:
			var rd := RoomData.new()
			rd.coord = Vector2i(rx, rz)
			var on_x := rx == 0 or rx == R - 1
			var on_z := rz == 0 or rz == R - 1
			rd.kind = KIND_CORNER if (on_x and on_z) else (KIND_EDGE if (on_x or on_z) else KIND_CENTER)
			rd.label = "%s%d" % [char(65 + rx), rz + 1]
			for z in room_cells:
				for x in room_cells:
					rd.cells.append(Vector2i(rx * room_cells + x, rz * room_cells + z))
			rooms[rd.coord] = rd
			room_list.append(rd)


## The exit room is random: rooms are tried in a seeded random order and the first one that can have an exit door
## is used. A room can have an exit door on a side that faces OUTSIDE the grid (perimeter rooms), or, with
## exit_anywhere, on a side whose neighbouring room can be left out without creating a dead end (that neighbour
## becomes the open-air courtyard behind the door). Perimeter rooms use their outside side when they have one.
func _choose_exit() -> void:
	var order: Array = room_list.duplicate()
	for i in range(order.size() - 1, 0, -1):                # Fisher-Yates with our seeded rng
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for rd in order:
		var outside_sides: Array[int] = []
		var hole_sides: Array[int] = []
		for d in 4:
			var n: Vector2i = rd.coord + RoomGrid.DIR_VECTORS[d]
			if not _room_in_grid(n):
				outside_sides.append(d)
			elif exit_anywhere and _hole_ok(n, rd.coord):
				hole_sides.append(d)
		var pool := outside_sides if not outside_sides.is_empty() else hole_sides
		if pool.is_empty():
			continue
		exit_room = rd.coord
		exit_dir = pool[rng.randi() % pool.size()]
		if outside_sides.is_empty():
			hole_room = rd.coord + RoomGrid.DIR_VECTORS[exit_dir]
			has_hole = true
			room_list.erase(rooms[hole_room])
			rooms.erase(hole_room)
		rooms[exit_room].is_exit = true
		rooms[exit_room].doors += 1
		return
	push_error("No room can hold an exit door (rooms_per_side too small?)")


func _room_in_grid(r: Vector2i) -> bool:
	return r.x >= 0 and r.y >= 0 and r.x < rooms_per_side and r.y < rooms_per_side


## Can room `m` be left out (made into the courtyard behind the exit of room `ex`)? Every other room must keep at
## least 2 doors (the exit room keeps its count: it loses the door to m but gains the exit door), and the rest of
## the building must stay connected.
func _hole_ok(m: Vector2i, ex: Vector2i) -> bool:
	var R := rooms_per_side
	var remaining := 0
	for z in R:
		for x in R:
			var r := Vector2i(x, z)
			if r == m:
				continue
			remaining += 1
			var deg := 0
			for d in 4:
				var n: Vector2i = r + RoomGrid.DIR_VECTORS[d]
				if _room_in_grid(n) and n != m:
					deg += 1
			if r == ex:
				deg += 1
			if deg < 2:
				return false
	var start := Vector2i(0, 0) if m != Vector2i(0, 0) else Vector2i(1, 0)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in 4:
			var n: Vector2i = c + RoomGrid.DIR_VECTORS[d]
			if _room_in_grid(n) and n != m and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size() == remaining


## The start room is picked from the farthest quarter of the rooms (measured in doors from the exit room),
## so the players always begin far from the exit.
func _choose_start() -> void:
	var dist := {exit_room: 0}
	var queue: Array[Vector2i] = [exit_room]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in 4:
			var n: Vector2i = c + RoomGrid.DIR_VECTORS[d]
			if rooms.has(n) and not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	var list: Array = []
	for rd in room_list:
		if rd.coord != exit_room:
			list.append([dist[rd.coord], rd.coord])
	list.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and (a[1].y * 1000 + a[1].x) < (b[1].y * 1000 + b[1].x)))
	var take := maxi(3, list.size() / 4)
	start_room = list[rng.randi() % mini(take, list.size())][1]
	start_distance = int(dist[start_room])
	rooms[start_room].is_start = true


## Penalties are data only (apply them in your game logic when room_entered fires). The start room and the
## exit room are always safe, so the level stays winnable.
func _assign_penalties() -> void:
	for rd in room_list:
		if rd.is_start or rd.is_exit:
			continue
		if rng.randf() < penalty_fraction:
			if rng.randf() < 0.6:
				rd.penalty = PENALTY_LOSE_POINTS
				rd.amount = rng.randi_range(1, 2)
			else:
				rd.penalty = PENALTY_SKIP_ROUND
				rd.amount = 1


# ---- links: open plan inside rooms, one centred door between every pair of neighbours -----------
func _build_links() -> Array:
	var k := room_cells
	var mid := k / 2
	var R := rooms_per_side
	var links := []
	for rd in room_list:
		for c in rd.cells:
			var local := c - rd.coord * k
			if local.x + 1 < k:
				links.append({"a": c, "b": c + Vector2i.RIGHT, "type": RoomGrid.Side.OPEN})
			if local.y + 1 < k:
				links.append({"a": c, "b": c + Vector2i.DOWN, "type": RoomGrid.Side.OPEN})
	for rz in R:
		for rx in R:
			var here := Vector2i(rx, rz)
			if not rooms.has(here):
				continue
			if rooms.has(here + Vector2i.RIGHT):
				_add_door_link(links, Vector2i(rx * k + k - 1, rz * k + mid), E, here, here + Vector2i.RIGHT)
			if rooms.has(here + Vector2i.DOWN):
				_add_door_link(links, Vector2i(rx * k + mid, rz * k + k - 1), S, here, here + Vector2i.DOWN)
	var ec := _exit_cell()
	door_edges[_ek(ec, exit_dir)] = true
	return links


func _add_door_link(links: Array, a: Vector2i, dir: int, room_a: Vector2i, room_b: Vector2i) -> void:
	var b: Vector2i = a + RoomGrid.DIR_VECTORS[dir]
	links.append({"a": a, "b": b, "type": RoomGrid.Side.DOOR})
	door_edges[_ek(a, dir)] = true
	door_edges[_ek(b, (dir + 2) % 4)] = true
	rooms[room_a].doors += 1
	rooms[room_b].doors += 1
	var rec := DoorRecord.new()
	rec.room_a = room_a
	rec.room_b = room_b
	rec.set_meta("key", _ek(a, dir))
	door_records.append(rec)


func _exit_cell() -> Vector2i:
	var k := room_cells
	var mid := k / 2
	var rc: Vector2i = exit_room
	match exit_dir:
		N: return Vector2i(rc.x * k + mid, rc.y * k)
		S: return Vector2i(rc.x * k + mid, rc.y * k + k - 1)
		W: return Vector2i(rc.x * k, rc.y * k + mid)
		_: return Vector2i(rc.x * k + k - 1, rc.y * k + mid)


## Matches each spawned door node (named by cell + side) to its record.
func _collect_door_records(doors: Array[Node3D]) -> void:
	var by_key := {}
	for r in door_records:
		by_key[r.get_meta("key")] = r
	var exit_rec := DoorRecord.new()
	exit_rec.room_a = exit_room
	exit_rec.room_b = OUTSIDE
	exit_rec.is_exit = true
	exit_rec.set_meta("key", _ek(_exit_cell(), exit_dir))
	door_records.append(exit_rec)
	by_key[exit_rec.get_meta("key")] = exit_rec
	for d in doors:
		var cell: Vector3i = d.get_meta("cell")
		var rec: DoorRecord = by_key.get(_ek(Vector2i(cell.x, cell.z), d.get_meta("dir")))
		if rec == null:
			push_warning("door %s has no record" % d.name)
			continue
		rec.door = d
		rec.monitors = d.get_meta("monitors")
		if rec.is_exit:
			exit_door = d
			exit_door.set_locked(exit_locked)
			exit_door.is_exit = true
			_show_exit_signs.call_deferred(rec)


func _show_exit_signs(rec: DoorRecord) -> void:
	for m in rec.monitors:
		m.show_exit()


# ---- props: give every room type a recognisable look -------------------------------------------
## Corner rooms: an electrical panel centred on each outside wall.   Edge rooms: a low grille on the outside wall.
## Centre rooms: ceiling vents and a security camera.  Every room: a number plate, plus random wall panels,
## speakers, grilles and cameras on plain walls. Every door gets hazard stripes on the floor on both sides.
## The exit door gets two red emergency lights beside it. Props never sit on a door edge.
func _place_props() -> void:
	var k := room_cells
	var mid := k / 2
	var occupied := {}
	for rd in room_list:
		var plain := _plain_edges(rd)
		# signature props
		for e in plain:
			var c: Vector2i = e[0]
			var d: int = e[1]
			if not _is_exterior(c, d) or _along_index(c, d, rd) != mid:
				continue
			if rd.kind == KIND_CORNER:
				_wall_prop("panel", c, d, 0.0, occupied)
			elif rd.kind == KIND_EDGE:
				_wall_prop("grille", c, d, 0.0, occupied)
		if rd.kind == KIND_CENTER:
			_vent(rd.cells[rd.cells.size() / 2], Vector2(1.2, 1.2))
			if not plain.is_empty():                # (a 1-cell room with 4 doors has no plain wall left)
				var cam: Array = plain[rng.randi() % plain.size()]
				_wall_prop("camera", cam[0], cam[1], 0.0, occupied)
		elif rng.randf() < 0.5:
			_vent(rd.cells[rng.randi() % rd.cells.size()], Vector2(-1.2, 1.2))
		# number plate: the first free plain wall of the room
		if label_rooms:
			for e in plain:
				if not occupied.has(_ek(e[0], e[1])):
					var plate := _wall_prop("plate", e[0], e[1], 0.0, occupied)
					_write_label(plate, rd.label)
					break
		# random flavour on the remaining plain walls
		for e in plain:
			if occupied.has(_ek(e[0], e[1])) or rng.randf() > 0.4:
				continue
			var roll := rng.randf()
			var kind := "wall_panel" if roll < 0.30 else ("speaker" if roll < 0.50 else ("grille" if roll < 0.68 else ("camera" if roll < 0.82 else "panel")))
			_wall_prop(kind, e[0], e[1], rng.randf_range(-0.8, 0.8), occupied)
	# hazard stripes at every door, on the floor of each room it connects
	for r in door_records:
		var key: String = r.get_meta("key")
		var parts := key.split(",")
		var c := Vector2i(int(parts[0]), int(parts[1]))
		var d := int(parts[2])
		_hazard(c, d)
		if not r.is_exit:
			_hazard(c + RoomGrid.DIR_VECTORS[d], (d + 2) % 4)
	# exit landmarks: red emergency lights either side of the exit door (inside)
	for off in [-1.4, 1.4]:
		_wall_prop("emergency", _exit_cell(), exit_dir, off, {}, true)


## Cell sides of a room that are plain walls (not open to the room itself, not a door).
func _plain_edges(rd: RoomData) -> Array:
	var out := []
	for c in rd.cells:
		for d in 4:
			var n: Vector2i = c + RoomGrid.DIR_VECTORS[d]
			if _cell_exists(n) and _room_of(n) == rd.coord:
				continue
			if door_edges.has(_ek(c, d)):
				continue
			out.append([c, d])
	return out


func _wall_prop(type: String, c: Vector2i, d: int, along: float, occupied: Dictionary, allow_door_edge := false) -> Node3D:
	if not allow_door_edge and door_edges.has(_ek(c, d)):
		return null
	var dv: Vector2i = RoomGrid.DIR_VECTORS[d]
	var out_v := Vector3(dv.x, 0, dv.y)
	var inward := -out_v
	var tangent := Vector3(absf(dv.y), 0, absf(dv.x))
	var local: Vector3 = _gm.map_to_local(Vector3i(c.x, 0, c.y)) + out_v * 2.0 + inward * WALL_FACE \
		+ tangent * along + Vector3(0, PROPS[type]["h"], 0)
	var node := _spawn(type, Basis.looking_at(-inward, Vector3.UP), local)
	if type == "camera":
		var head := node.find_child("Prop_Camera_Head", true, false) as Node3D
		if head != null:
			head.rotation.y = deg_to_rad(rng.randf_range(-40.0, 40.0))
	occupied[_ek(c, d)] = true
	placed_props.append({"type": type, "cell": c, "dir": d, "node": node})
	return node


func _vent(c: Vector2i, offset: Vector2) -> void:
	var local: Vector3 = _gm.map_to_local(Vector3i(c.x, 0, c.y)) + Vector3(offset.x, 3.0, offset.y)
	_spawn("vent", Basis(), local)


func _hazard(c: Vector2i, d: int) -> void:
	var dv: Vector2i = RoomGrid.DIR_VECTORS[d]
	var out_v := Vector3(dv.x, 0, dv.y)
	var basis := Basis(Vector3.UP, PI / 2.0) if dv.x != 0 else Basis()
	basis = basis.scaled_local(Vector3(1.5, 1.0, 1.0))
	_spawn("hazard", basis, _gm.map_to_local(Vector3i(c.x, 0, c.y)) + out_v * 2.0 - out_v * 1.0)


func _spawn(type: String, basis: Basis, local_pos: Vector3) -> Node3D:
	if not _scenes.has(type):
		_scenes[type] = load(PROPS[type]["path"])
	var n: Node3D = _scenes[type].instantiate()
	n.name = "%s_%d" % [type, _prop_count]               # stable, unique, identical on every peer
	n.set_meta("prop_type", type)
	_prop_count += 1
	_props_root.add_child(n)
	n.global_transform = _gm.global_transform * Transform3D(basis, local_pos)
	return n


func _write_label(plate: Node3D, text: String) -> void:
	if plate == null:
		return
	var anchor := plate.find_child("Anchor_Label", true, false) as Node3D
	if anchor == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 56
	l.pixel_size = 0.0018
	l.modulate = Color(0.1, 0.11, 0.12)
	l.shaded = false
	l.position = Vector3(0, 0, 0.003)
	anchor.add_child(l)


# ---- lights, zones, exit -------------------------------------------------------------------------
## One OmniLight3D per 2 x 2 cells. (Godot's default clustered limit is 512 lights; one per cell would exceed it.)
func _add_lights() -> void:
	for cell in _gm.get_used_cells():
		if cell.x % 2 != 0 or cell.z % 2 != 0:
			continue
		var l := OmniLight3D.new()
		l.light_color = Color(0.88, 0.93, 1.0)
		l.light_energy = 1.8
		l.omni_range = 7.5
		add_child(l)
		l.global_position = _gm.to_global(_gm.map_to_local(cell) + Vector3(0, 2.85, 0))


## An Area3D per room: emits room_entered(room, body) when a physics body walks in.
func _make_room_zones() -> void:
	var size := room_cells * RoomGrid.CELL_SIZE.x
	for rd in room_list:
		var zone := Area3D.new()
		zone.name = "RoomZone_%d_%d" % [rd.coord.x, rd.coord.y]
		zone.collision_layer = 0
		zone.collision_mask = 1
		zone.monitorable = false
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size - 0.8, 3.0, size - 0.8)
		shape.shape = box
		zone.add_child(shape)
		add_child(zone)
		var first: Vector2i = rd.cells[0]
		var centre: Vector3 = _gm.map_to_local(Vector3i(first.x, 0, first.y)) + Vector3(room_cells - 1, 0, room_cells - 1) * 2.0
		zone.global_position = _gm.to_global(centre + Vector3(0, 1.5, 0))
		zone.body_entered.connect(func(body: Node3D) -> void: room_entered.emit(rd, body))


## The exterior: a yard slab outside the exit door and an Area3D that fires exit_reached.
func _make_exit_area() -> void:
	var ec := _exit_cell()
	var dv: Vector2i = RoomGrid.DIR_VECTORS[exit_dir]
	var out_v := Vector3(dv.x, 0, dv.y)
	var edge_local: Vector3 = _gm.map_to_local(Vector3i(ec.x, 0, ec.y)) + out_v * 2.0
	exit_position = _gm.to_global(edge_local)

	var thickness := base_floor.size.y if base_floor != null else 1.0
	var top_y: float = (_gm.global_position.y - FLOOR_SLAB) - 0.02          # base top - 2 cm (never coplanar with the base)
	var yard := CSGBox3D.new()
	yard.name = "ExitYard"
	yard.size = Vector3(16.0, thickness, 22.0) if dv.x != 0 else Vector3(22.0, thickness, 16.0)
	yard.use_collision = true
	add_child(yard)
	yard.global_position = Vector3(exit_position.x, top_y - thickness / 2.0, exit_position.z) + out_v * (8.0 + WALL_FACE)

	var area := Area3D.new()
	area.name = "ExitTrigger"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 3.0)
	shape.shape = box
	area.add_child(shape)
	add_child(area)
	area.global_position = exit_position + out_v * 2.5 + Vector3(0, 1.5, 0)
	area.body_entered.connect(func(body: Node3D) -> void: exit_reached.emit(body))


func _finish(doors: Array[Node3D]) -> void:
	# draw distance for the many small meshes (monitor digits, props)
	var nodes: Array[Node] = [_props_root]
	nodes.append_array(doors)
	for child in get_children():
		if child is DoorMonitor:
			nodes.append(child)
	for n in nodes:
		for m in n.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).visibility_range_end = draw_distance
	# spawn points: the 9 cell centres of the start room
	for c in rooms[start_room].cells:
		spawn_points.append(_gm.to_global(_gm.map_to_local(Vector3i(c.x, 0, c.y)) + Vector3(0, 0.1, 0)))
	if player != null:
		player.global_position = spawn_points[spawn_points.size() / 2]


func _sit_on_base_floor() -> void:
	var cells := rooms_per_side * room_cells
	var grid_m := Vector2(cells, cells) * RoomGrid.CELL_SIZE.x
	var size := base_floor.size
	if grid_m.x > size.x or grid_m.y > size.z:
		push_warning("The %d m building is larger than the %d m base floor." % [grid_m.x, size.x])
	var top := base_floor.global_position + Vector3(0, size.y / 2.0, 0)
	_gm.global_position = top + Vector3(-grid_m.x / 2.0, FLOOR_SLAB, -grid_m.y / 2.0)
	base_floor.use_collision = true


# ---- small helpers ----------------------------------------------------------------------------------
func _ek(c: Vector2i, d: int) -> String:
	return "%d,%d,%d" % [c.x, c.y, d]


@warning_ignore("integer_division")
func _room_of(c: Vector2i) -> Vector2i:
	return Vector2i(floori(float(c.x) / room_cells), floori(float(c.y) / room_cells))


func _in_grid(c: Vector2i) -> bool:
	var n := rooms_per_side * room_cells
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n


func _is_exterior(c: Vector2i, d: int) -> bool:
	return not _cell_exists(c + RoomGrid.DIR_VECTORS[d])


func _cell_exists(c: Vector2i) -> bool:
	return _in_grid(c) and rooms.has(_room_of(c))


## Index (0..room_cells-1) of cell c along the wall in direction d, inside its room.
func _along_index(c: Vector2i, d: int, rd: RoomData) -> int:
	var local := c - rd.coord * room_cells
	return local.x if (d == N or d == S) else local.y
