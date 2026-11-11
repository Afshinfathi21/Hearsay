extends Node3D
## Generates a connected level of rooms on a GridMap using RoomGrid.
## Attach to your level root. The root needs a GridMap child named "GridMap".
##
## 1. The grid (default 24 x 24 cells of 4 m = 96 x 96 m) is split into rectangular ROOMS of
##    min_room..max_room cells per side (2..5 cells = 8..20 m). Cells inside one room are joined
##    with OPEN links, so the room has no inner walls (its corner posts stay as columns).
## 2. Rooms are connected with doors: a random spanning tree guarantees every room is reachable,
##    then some extra doors add loops.
## 3. Working doors + monitors and ceiling lights are added.
## Same seed = same level. seed_value 0 = a different level every run.

@export var grid_size := Vector2i(24, 24)
@export var min_room := 2                   # cells per side; keep max_room >= 2 * min_room - 1
@export var max_room := 5
@export_range(0.0, 1.0) var extra_door_chance := 0.2
@export var seed_value := 12345
@export var draw_distance := 30.0           # doors/monitors are hidden beyond this many metres
@export var player: Node3D                  # optional: moved to spawn_position once the level exists
@export var base_floor: CSGBox3D            # optional: the grid is centred on this box and sits on its top face

const FLOOR_SLAB := 0.2                     # the room floor slab hangs 0.2 m below the cell's floor level

var rng := RandomNumberGenerator.new()
var rooms: Array[Rect2i] = []               # every room, in cell coordinates
var room_of := {}                           # Vector2i cell -> index into rooms
var spawn_position := Vector3.ZERO          # a good place to put the player


func _ready() -> void:
	var gm: GridMap = $GridMap
	RoomGrid.setup(gm)
	if base_floor != null:
		_sit_on_base_floor(gm)                  # must happen before anything is placed
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	_split(Rect2i(Vector2i.ZERO, grid_size))
	for i in rooms.size():
		for y in range(rooms[i].position.y, rooms[i].end.y):
			for x in range(rooms[i].position.x, rooms[i].end.x):
				room_of[Vector2i(x, y)] = i

	var links: Array = _open_links()
	links.append_array(_door_links())
	var cells: Array[Vector2i] = []
	for y in grid_size.y:
		for x in grid_size.x:
			cells.append(Vector2i(x, y))
	RoomGrid.place_rooms(gm, cells, links)

	var doors := RoomGrid.spawn_doors(gm, self, load("res://assets/the_exit_room/doors/door_standard.glb"), load("res://assets/the_exit_room/monitors/door_monitor.glb"))
	_add_lights(gm)
	_limit_draw_distance(doors)

	var first := rooms[0]
	spawn_position = gm.to_global(gm.map_to_local(Vector3i(first.position.x, 0, first.position.y))
		+ Vector3(first.size.x - 1, 0, first.size.y - 1) * 2.0 + Vector3(0, 0.1, 0))
	if player != null:
		player.global_position = spawn_position


## Centres the grid on the base-floor box and puts the rooms on top of it.
## The room floor slab is 0.2 m thick and hangs BELOW each cell's floor level, so the grid is raised by
## 0.2 m: the slab then rests on the box's top face instead of sharing the same plane (which would z-fight).
func _sit_on_base_floor(gm: GridMap) -> void:
	var size := base_floor.size
	var grid_m := Vector2(grid_size) * RoomGrid.CELL_SIZE.x
	if grid_m.x > size.x or grid_m.y > size.z:
		push_warning("The %d x %d m grid is larger than the %d x %d m base floor." % [grid_m.x, grid_m.y, size.x, size.z])
	var top := base_floor.global_position + Vector3(0, size.y / 2.0, 0)
	gm.global_position = top + Vector3(-grid_m.x / 2.0, FLOOR_SLAB, -grid_m.y / 2.0)
	base_floor.use_collision = true             # CSG shapes only collide when this is on


# ---- 1. split the grid into rooms (binary space partition) ------------------------------------
func _split(r: Rect2i) -> void:
	var can_x := r.size.x >= min_room * 2
	var can_y := r.size.y >= min_room * 2
	var must_x := r.size.x > max_room
	var must_y := r.size.y > max_room
	if not (can_x or can_y):
		rooms.append(r)
		return
	if not (must_x or must_y) and rng.randf() < 0.25:       # sometimes stop early: variety in room sizes
		rooms.append(r)
		return
	var split_x: bool
	if must_x and can_x:
		split_x = true
	elif must_y and can_y:
		split_x = false
	elif can_x and can_y:
		split_x = r.size.x > r.size.y or (r.size.x == r.size.y and rng.randf() < 0.5)
	else:
		split_x = can_x
	if split_x:
		var k := rng.randi_range(min_room, r.size.x - min_room)
		_split(Rect2i(r.position, Vector2i(k, r.size.y)))
		_split(Rect2i(r.position + Vector2i(k, 0), Vector2i(r.size.x - k, r.size.y)))
	else:
		var k := rng.randi_range(min_room, r.size.y - min_room)
		_split(Rect2i(r.position, Vector2i(r.size.x, k)))
		_split(Rect2i(r.position + Vector2i(0, k), Vector2i(r.size.x, r.size.y - k)))


# ---- 2a. open-plan links inside each room ----------------------------------------------------
func _open_links() -> Array:
	var out := []
	for r in rooms:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c := Vector2i(x, y)
				if x + 1 < r.end.x:
					out.append({"a": c, "b": c + Vector2i.RIGHT, "type": RoomGrid.Side.OPEN})
				if y + 1 < r.end.y:
					out.append({"a": c, "b": c + Vector2i.DOWN, "type": RoomGrid.Side.OPEN})
	return out


# ---- 2b. doors between rooms: random spanning tree + some extra loops --------------------------
func _door_links() -> Array:
	var candidates := {}                    # Vector2i(room i, room j) -> Array of [cell a, cell b]
	for y in grid_size.y:
		for x in grid_size.x:
			var c := Vector2i(x, y)
			for d in [Vector2i.RIGHT, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if n.x >= grid_size.x or n.y >= grid_size.y:
					continue
				var i: int = room_of[c]
				var j: int = room_of[n]
				if i == j:
					continue
				var key := Vector2i(mini(i, j), maxi(i, j))
				if not candidates.has(key):
					candidates[key] = []
				candidates[key].append([c, n])

	var keys: Array = candidates.keys()
	for i in range(keys.size() - 1, 0, -1):                 # Fisher-Yates with our seeded rng
		var j := rng.randi_range(0, i)
		var tmp = keys[i]
		keys[i] = keys[j]
		keys[j] = tmp

	var parent: Array[int] = []
	for i in rooms.size():
		parent.append(i)
	var out := []
	for key in keys:
		var ra := _find(parent, key.x)
		var rb := _find(parent, key.y)
		if ra != rb or rng.randf() < extra_door_chance:
			parent[ra] = rb
			var options: Array = candidates[key]
			var pick: Array = options[rng.randi() % options.size()]
			out.append({"a": pick[0], "b": pick[1], "type": RoomGrid.Side.DOOR})
	return out


func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


# ---- 3. lights and draw distance ---------------------------------------------------------------
## One OmniLight3D per 2 x 2 cells (144 lights for 24 x 24). Every room gets at least one,
## because every room is at least 2 cells wide and tall. Godot's default clustered limit is 512 lights,
## which is why RoomGrid.add_lights() (one per cell = 576) is NOT used here.
func _add_lights(gm: GridMap) -> void:
	for cell in gm.get_used_cells():
		if cell.x % 2 != 0 or cell.z % 2 != 0:
			continue
		var l := OmniLight3D.new()
		l.light_color = Color(0.88, 0.93, 1.0)
		l.light_energy = 1.8
		l.omni_range = 7.5
		add_child(l)
		l.global_position = gm.to_global(gm.map_to_local(cell) + Vector3(0, 2.85, 0))


## Doors and monitors have many small meshes (the monitor's digits); hide them when far away.
func _limit_draw_distance(doors: Array[Node3D]) -> void:
	var nodes: Array[Node] = []
	nodes.append_array(doors)
	for child in get_children():
		if child is DoorMonitor:
			nodes.append(child)
	for n in nodes:
		for m in n.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).visibility_range_end = draw_distance
