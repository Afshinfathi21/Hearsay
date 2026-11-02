class_name RoomBuilder
extends Node3D
## Assembles rooms from the Environment/ kit on a 4 m grid.
##
## Cell (x, y) covers world X = 4x .. 4x+4 and Z = 4y .. 4y+4.
##   var rb := RoomBuilder.new()
##   add_child(rb)
##   rb.build([Vector2i(0, 0), Vector2i(1, 0)],              # cells
##            [[Vector2i(0, 0), Vector2i(1, 0)]])            # doorways: [front_cell, back_cell]
## Every cell gets a floor, ceiling and ceiling light. Every cell edge gets a wall
## (or a doorway wall + door + two monitors when listed). Posts go on grid corners.

const PITCH := 4.0
const HEIGHT := 3.0
const MONITOR_HEIGHT := 2.625
const WALL_FACE := 0.15              # half wall thickness
const KIT := "res://Assets/Environment/"
const DOOR := "res://Assets/Doors/door_standard.glb"
const MONITOR := "res://Assets/Monitors/door_monitor.glb"

var doors := {}                      # edge key -> {door, monitor_front, monitor_rear}
var _cache := {}


func build(cells: Array[Vector2i], doorways: Array = []) -> void:
	var cell_set := {}
	for c in cells:
		cell_set[c] = true
	var door_edges := {}
	for pair in doorways:
		door_edges[_edge_key(pair[0], pair[1])] = pair
	var posts := {}
	var done := {}

	for c in cells:
		var centre := _centre(c)
		_spawn(KIT + "env_floor_4m.glb", Transform3D(Basis(), centre))
		_spawn(KIT + "env_ceiling_4m.glb", Transform3D(Basis(), centre + Vector3(0, HEIGHT, 0)))
		_spawn(KIT + "env_light_ceiling.glb", Transform3D(Basis(), centre + Vector3(0, HEIGHT, 0)))
		for i in 2:
			for j in 2:
				posts[Vector2i(c.x + i, c.y + j)] = true
		for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = c + dir
			var key := _edge_key(c, n)
			if done.has(key):
				continue
			done[key] = true
			var mid := centre + Vector3(dir.x, 0, dir.y) * PITCH / 2.0
			if door_edges.has(key) and cell_set.has(n):
				_spawn_doorway(mid, door_edges[key], key)
			else:
				# walls run along X for UP/DOWN edges, along Z for LEFT/RIGHT edges
				var basis := Basis(Vector3.UP, PI / 2.0) if dir.x != 0 else Basis()
				_spawn(KIT + "env_wall_straight.glb", Transform3D(basis, mid))

	for p in posts:
		_spawn(KIT + "env_wall_post.glb", Transform3D(Basis(), Vector3(p.x, 0, p.y) * PITCH))


func _spawn_doorway(mid: Vector3, pair: Array, key: String) -> void:
	# The door's FRONT (+Z in the model) faces pair[0]; it swings toward pair[1].
	var front: Vector2i = pair[0] - pair[1]
	var d3 := Vector3(front.x, 0, front.y)
	var basis := Basis.looking_at(-d3, Vector3.UP)          # +Z -> d3
	var back_basis := Basis.looking_at(d3, Vector3.UP)      # +Z -> -d3
	_spawn(KIT + "env_wall_doorway.glb", Transform3D(basis, mid))
	var info := {}
	info["door"] = _spawn(DOOR, Transform3D(basis, mid), "res://Levels/The Exit Room/Room/door_standard.gd")
	var up := Vector3(0, MONITOR_HEIGHT, 0)
	info["monitor_front"] = _spawn(MONITOR, Transform3D(basis, mid + d3 * WALL_FACE + up), "res://Levels/The Exit Room/Room/door_monitor.gd")
	info["monitor_rear"] = _spawn(MONITOR, Transform3D(back_basis, mid - d3 * WALL_FACE + up), "res://Levels/The Exit Room/Room/door_monitor.gd")
	doors[key] = info


func _spawn(path: String, xf: Transform3D, script_path := "") -> Node3D:
	if not _cache.has(path):
		_cache[path] = load(path)
	var n: Node3D = _cache[path].instantiate()
	if script_path != "":
		n.set_script(load(script_path))   # before add_child so _ready() runs
	n.transform = xf
	add_child(n)
	return n


func _centre(c: Vector2i) -> Vector3:
	return Vector3(c.x * PITCH + PITCH / 2.0, 0, c.y * PITCH + PITCH / 2.0)


func _edge_key(a: Vector2i, b: Vector2i) -> String:
	var lo := a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
	var hi := b if lo == a else a
	return "%d,%d|%d,%d" % [lo.x, lo.y, hi.x, hi.y]
