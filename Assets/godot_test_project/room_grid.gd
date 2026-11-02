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
const LIBRARY_PATH := "res://Environment/room_grid/room_library.meshlib"
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
static func setup(gridmap: GridMap, library: MeshLibrary = null) -> void:
	gridmap.mesh_library = library if library != null else load(LIBRARY_PATH)
	gridmap.cell_size = CELL_SIZE
	gridmap.cell_center_x = true
	gridmap.cell_center_y = false
	gridmap.cell_center_z = true


## cells: Array[Vector2i] of room cells (x, z).
## links: Array of {"a": Vector2i, "b": Vector2i, "type": Side.DOOR or Side.OPEN} between ADJACENT cells.
##   DOOR  -> a doorway; cell "a" owns it (its side gets DOOR, cell "b" gets OPEN).
##   OPEN  -> open-plan: both cells OPEN, so the two rooms merge into one bigger room (corner posts stay as columns).
##   no link between neighbours -> a plain wall, drawn by the cell with the smaller (x, z).
## Edges toward empty cells are always WALL. Returns a Dictionary cell -> item id.
static func place_rooms(gridmap: GridMap, cells: Array[Vector2i], links: Array = [], level := 0) -> Dictionary:
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
		var id := item_id(s[0], s[1], s[2], s[3])
		gridmap.set_cell_item(Vector3i(c.x, level, c.y), id)
		placed[c] = id
	return placed


## Instances a working door (+ front and rear monitors) in every DOOR side of the GridMap.
## The GridMap must already be inside the scene tree (its global transform is used).
## door_scene = door_standard.glb, monitor_scene = door_monitor.glb (either may be null).
## The doorway frame is already part of the room mesh, so the door's own frame is removed.
## The door's FRONT faces into the room that owns the doorway. Returns the spawned door nodes.
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
			if door_scene != null:
				var door: Node3D = door_scene.instantiate()
				var frame := door.find_child("Door_Frame", true, false)
				if frame != null:
					for light in frame.find_children("Door_Status_Light_*", "Node3D", true, false):
						light.owner = null                                 # (imported scenes set an owner)
						light.reparent(door, false)                        # keep status lights, drop the frame
					frame.get_parent().remove_child(frame)
					frame.free()
				door.set_script(load("res://door_standard.gd"))
				parent.add_child(door)
				door.global_transform = base
				out.append(door)
			if monitor_scene != null:
				var up := Vector3(0, MONITOR_HEIGHT, 0)
				for side in [1.0, -1.0]:
					var mon: Node3D = monitor_scene.instantiate()
					mon.set_script(load("res://door_monitor.gd"))
					parent.add_child(mon)
					var b := basis if side > 0 else Basis.looking_at(front, Vector3.UP)
					mon.global_transform = gridmap.global_transform * Transform3D(b, edge + front * WALL_FACE * side + up)
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
