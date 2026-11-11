class_name RoomGrid
extends RefCounted
## Helper for filling a GridMap with the room MeshLibrary (Environment/room_grid/room_library.meshlib).
##
## One cell = one 4 x 4 m room. Each of its four sides is WALL, DOOR (doorway wall + frame) or OPEN
## (no geometry; the neighbouring cell supplies the wall or door). There is one library item for every
## combination (3^4 = 81), named Room_<N><E><S><W> with letters W/D/O, e.g. "Room_WDOW".
## Compass: N = -Z, E = +X, S = +Z, W = -X. Cell (x, y) in this API means GridMap cell (x, level, y).
##
## RULE: a shared edge is drawn by exactly ONE of the two cells (the other uses OPEN there). place_rooms()
## does this for you. If you paint by hand, make sure a door/wall is never doubled on one edge.
##
## Typical use:
##   var gm := GridMap.new(); add_child(gm)
##   RoomGrid.setup(gm)
##   RoomGrid.place_rooms(gm, [Vector2i(0,0), Vector2i(1,0)],
##       [{"a": Vector2i(0,0), "b": Vector2i(1,0), "type": RoomGrid.Side.DOOR}])
##   RoomGrid.spawn_doors(gm, self, load("res://Doors/door_standard.glb"), load("res://Monitors/door_monitor.glb"))
##   RoomGrid.add_lights(gm, self)

enum Side { WALL = 0, DOOR = 1, OPEN = 2 }
enum Dir { N, E, S, W }

const CELL_SIZE := Vector3(4.0, 3.5, 4.0)          # 3.5 = 0.2 floor slab + 3.0 interior + 0.3 ceiling slab, so levels stack cleanly
const LIBRARY_PATH := "res://MeshLibraries/room_library.meshlib"            # rooms WITH corner posts
const LIBRARY_OPEN_PATH := "res://MeshLibraries/room_library_open.meshlib"    # rooms WITHOUT posts (use build_posts)
const POST_SCENE_PATH := "res://assets/the_exit_room/environment/env_wall_post.glb"
const POST_SIZE := Vector3(0.3, 3.0, 0.3)
const DIR_VECTORS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]   # N, E, S, W
const LETTERS := "WDO"
const MONITOR_HEIGHT := 2.625
const WALL_FACE := 0.15


## Library item id for the four sides (use Side values).
static func item_id(n: int, e: int, s: int, w: int) -> int:
	return ((n * 3 + e) * 3 + s) * 3 + w


## Inverse of item_id(): returns [n, e, s, w].
static func sides_of(id: int) -> Array[int]:
	return [id / 27, (id / 9) % 3, (id / 3) % 3, id % 3]


static func item_name(id: int) -> String:
	var s := sides_of(id)
	return "Room_%s%s%s%s" % [LETTERS[s[0]], LETTERS[s[1]], LETTERS[s[2]], LETTERS[s[3]]]


## Configure a GridMap for this library: 4 x 3.5 x 4 cells, items centred in X/Z and sitting on the cell floor.
## separate_posts = true uses the library WITHOUT corner posts; then call build_posts() after place_rooms(), so
## posts exist only where a wall needs one and open rooms have no columns inside.
static func setup(gridmap: GridMap, library: MeshLibrary = null, separate_posts := false) -> void:
	if library == null:
		library = load(LIBRARY_OPEN_PATH if separate_posts else LIBRARY_PATH)
	gridmap.mesh_library = library
	gridmap.cell_size = CELL_SIZE
	gridmap.cell_center_x = true
	gridmap.cell_center_y = false
	gridmap.cell_center_z = true


## cells: Array[Vector2i] of room cells (x, z).
## links: Array of {"a": Vector2i, "b": Vector2i, "type": Side.DOOR or Side.OPEN} between ADJACENT cells.
##   DOOR  -> a doorway; cell "a" owns it (its side gets DOOR, cell "b" gets OPEN).
##   OPEN  -> open-plan: both cells OPEN, so the two rooms merge into one bigger room (corner posts stay as columns).
##   no link between neighbours -> a plain wall, drawn by the cell with the smaller (x, z).
## Edges toward empty cells are always WALL, except those listed in exterior_doors:
##   exterior_doors: Array of {"cell": Vector2i, "dir": Dir.N/E/S/W}; that outside-facing side becomes a DOOR
##   (used for a building's real exit). Returns a Dictionary cell -> item id.
static func place_rooms(gridmap: GridMap, cells: Array[Vector2i], links: Array = [], level := 0, exterior_doors: Array = []) -> Dictionary:
	var have := {}
	for c in cells:
		have[c] = true
	var link_of := {}
	for l in links:
		link_of[_edge_key(l["a"], l["b"])] = l
	var placed := {}
	for c in cells:
		var s := [Side.WALL, Side.WALL, Side.WALL, Side.WALL]
		for d in 4:
			var n: Vector2i = c + DIR_VECTORS[d]
			if not have.has(n):
				continue                                   # exterior: wall
			var key := _edge_key(c, n)
			if link_of.has(key):
				var l: Dictionary = link_of[key]
				if l["type"] == Side.OPEN:
					s[d] = Side.OPEN
				else:
					s[d] = Side.DOOR if c == l["a"] else Side.OPEN
			else:
				s[d] = Side.WALL if _owns_plain_wall(c, n) else Side.OPEN
		for e in exterior_doors:
			if e["cell"] == c and not have.has(c + DIR_VECTORS[e["dir"]]):
				s[e["dir"]] = Side.DOOR
		var id := item_id(s[0], s[1], s[2], s[3])
		gridmap.set_cell_item(Vector3i(c.x, level, c.y), id)
		placed[c] = id
	return placed


## Places a wall post at every grid intersection where at least one of the four wall segments meeting there is
## solid (a wall or a door). Nowhere else, so open-plan rooms have no columns. Posts are ONE MultiMeshInstance3D
## (one draw call) plus ONE StaticBody3D with a box per post. Call after place_rooms() on a GridMap that uses the
## open library. Returns the container node (child of `parent`); its meta "positions" is an Array[Vector2i] of the
## intersections that got a post (grid-corner coordinates: world offset = position * cell size).
## as_multimesh = false creates one plain MeshInstance3D per post instead (slower to draw, but every transform can be
## read back, which headless tests need: the dummy renderer does not keep MultiMesh data).
static func build_posts(gridmap: GridMap, parent: Node, level := 0, as_multimesh := true) -> Node3D:
	var corners := {}
	for cell in gridmap.get_used_cells():
		if cell.y != level:
			continue
		for i in 2:
			for j in 2:
				corners[Vector2i(cell.x + i, cell.z + j)] = true
	var needed: Array[Vector2i] = []
	for p in corners:
		var nw := Vector3i(p.x - 1, level, p.y - 1)
		var ne := Vector3i(p.x, level, p.y - 1)
		var sw := Vector3i(p.x - 1, level, p.y)
		if _edge_solid(gridmap, nw, Dir.E) or _edge_solid(gridmap, sw, Dir.E) \
				or _edge_solid(gridmap, nw, Dir.S) or _edge_solid(gridmap, ne, Dir.S):
			needed.append(p)
	var holder := Node3D.new()
	holder.name = "Posts"
	parent.add_child(holder)
	holder.global_transform = gridmap.global_transform
	var inst: Node3D = (load(POST_SCENE_PATH) as PackedScene).instantiate()
	var mesh: Mesh = (inst.find_child("Env_Wall_Post", true, false) as MeshInstance3D).mesh
	inst.free()
	holder.set_meta("positions", needed)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = needed.size() if as_multimesh else 0
	var body := StaticBody3D.new()
	body.name = "PostsCollision"
	var box := BoxShape3D.new()
	box.size = POST_SIZE
	var y := level * CELL_SIZE.y
	for i in needed.size():
		var pos := Vector3(needed[i].x * CELL_SIZE.x, y, needed[i].y * CELL_SIZE.z)
		if as_multimesh:
			mm.set_instance_transform(i, Transform3D(Basis(), pos))
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = pos
			mi.name = "Post_%d_%d" % [needed[i].x, needed[i].y]
			holder.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = pos + Vector3(0, POST_SIZE.y / 2.0, 0)
		body.add_child(cs)
	if as_multimesh:
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "PostsVisual"
		mmi.multimesh = mm
		holder.add_child(mmi)
	holder.add_child(body)
	return holder


## True if the cell side (c, d) holds a wall or door, judged from either cell that shares the edge.
static func _edge_solid(gridmap: GridMap, c: Vector3i, d: int) -> bool:
	var id := gridmap.get_cell_item(c)
	if id != GridMap.INVALID_CELL_ITEM and sides_of(id)[d] != Side.OPEN:
		return true
	var v: Vector2i = DIR_VECTORS[d]
	var n := Vector3i(c.x + v.x, c.y, c.z + v.y)
	var nid := gridmap.get_cell_item(n)
	return nid != GridMap.INVALID_CELL_ITEM and sides_of(nid)[(d + 2) % 4] != Side.OPEN


## Instances a working door (+ front and rear monitors) in every DOOR side of the GridMap.
## The GridMap must already be inside the scene tree (its global transform is used).
## door_scene = door_standard.glb, monitor_scene = door_monitor.glb (either may be null).
## The doorway frame is already part of the room mesh, so the door's own frame is removed.
## The door's FRONT faces into the room that owns the doorway. Returns the spawned door nodes.
## Each door is named Door_<x>_<y>_<z>_<N|E|S|W> (stable across peers, good for multiplayer) and carries metadata:
## "cell" (Vector3i), "dir" (Dir) and "monitors" (the front and rear DoorMonitor nodes, if monitor_scene was given).
static func spawn_doors(gridmap: GridMap, parent: Node, door_scene: PackedScene, monitor_scene: PackedScene = null) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for cell in gridmap.get_used_cells():
		var sides := sides_of(gridmap.get_cell_item(cell))
		for d in 4:
			if sides[d] != Side.DOOR:
				continue
			var dv: Vector2i = DIR_VECTORS[d]
			var outward := Vector3(dv.x, 0, dv.y)
			var edge: Vector3 = gridmap.map_to_local(cell) + outward * (CELL_SIZE.x / 2.0)
			var front := -outward                                          # into the owning room
			var basis := Basis.looking_at(-front, Vector3.UP)              # model +Z -> front
			var base := gridmap.global_transform * Transform3D(basis, edge)
			var tag := "%d_%d_%d_%s" % [cell.x, cell.y, cell.z, "NESW"[d]]
			var monitors: Array = []
			var door: Node3D = null
			if door_scene != null:
				door = door_scene.instantiate()
				door.name = "Door_" + tag
				var frame := door.find_child("Door_Frame", true, false)
				if frame != null:
					for light in frame.find_children("Door_Status_Light_*", "Node3D", true, false):
						light.owner = null                                 # (imported scenes set an owner)
						light.reparent(door, false)                        # keep status lights, drop the frame
					frame.get_parent().remove_child(frame)
					frame.free()
				door.set_script(load("res://Levels/The Exit Room/Room/door_standard.gd"))
				parent.add_child(door)
				door.global_transform = base
				door.set_meta("cell", cell)
				door.set_meta("dir", d)
				out.append(door)
			if monitor_scene != null:
				var up := Vector3(0, MONITOR_HEIGHT, 0)
				for side in [1.0, -1.0]:
					var mon: Node3D = monitor_scene.instantiate()
					mon.name = "Monitor_%s_%s" % [tag, "F" if side > 0 else "R"]
					mon.set_script(load("res://Levels/The Exit Room/Room/door_monitor.gd"))
					parent.add_child(mon)
					monitors.append(mon)
					var b := basis if side > 0 else Basis.looking_at(front, Vector3.UP)
					mon.global_transform = gridmap.global_transform * Transform3D(b, edge + front * WALL_FACE * side + up)
			if door != null:
				door.set_meta("monitors", monitors)
	return out


## One OmniLight3D per room, under the ceiling fixture. Returns the lights.
static func add_lights(gridmap: GridMap, parent: Node, energy := 1.6, light_range := 7.0, shadows := false) -> Array[OmniLight3D]:
	var out: Array[OmniLight3D] = []
	for cell in gridmap.get_used_cells():
		var l := OmniLight3D.new()
		l.light_color = Color(0.88, 0.93, 1.0)
		l.light_energy = energy
		l.omni_range = light_range
		l.shadow_enabled = shadows
		parent.add_child(l)
		l.global_position = gridmap.to_global(gridmap.map_to_local(cell) + Vector3(0, 2.85, 0))
		out.append(l)
	return out


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
	var hi := b if lo == a else a
	return "%d,%d|%d,%d" % [lo.x, lo.y, hi.x, hi.y]


static func _owns_plain_wall(c: Vector2i, n: Vector2i) -> bool:
	return c.x < n.x or (c.x == n.x and c.y < n.y)
