extends SceneTree
## Builds Environment/room_grid/room_library.meshlib from room_variants.glb (81 merged room meshes),
## adding collision boxes to each item.
## Run:  godot --headless --path . --script res://build_room_meshlibrary.gd
## (import the GLB first: godot --headless --import)

const SRC := "res://Environment/room_grid/room_variants.glb"
const OUT := "res://Environment/room_grid/room_library.meshlib"
const WALL_H := 3.0
const T := 0.3                       # wall thickness
var _boxes := {}                     # size -> BoxShape3D (shared between items)


func _box(size: Vector3, centre: Vector3) -> Array:
	if not _boxes.has(size):
		var b := BoxShape3D.new()
		b.size = size
		_boxes[size] = b
	return [_boxes[size], Transform3D(Basis(), centre)]


## Collision for one room: floor, ceiling, 4 posts, and per side a wall / doorway wall + frame jambs.
func _shapes(sides: Array[int]) -> Array:
	var s := []
	s.append_array(_box(Vector3(4, 0.2, 4), Vector3(0, -0.1, 0)))              # floor slab
	s.append_array(_box(Vector3(4, 0.3, 4), Vector3(0, WALL_H + 0.15, 0)))      # ceiling slab
	for sx in [-2.0, 2.0]:
		for sz in [-2.0, 2.0]:
			s.append_array(_box(Vector3(T, WALL_H, T), Vector3(sx, WALL_H / 2, sz)))
	for d in 4:
		if sides[d] == RoomGrid.Side.OPEN:
			continue
		var v: Vector2i = RoomGrid.DIR_VECTORS[d]
		var edge := Vector3(v.x, 0, v.y) * 2.0
		var along := Vector3(absf(v.y), 0, absf(v.x))        # unit vector along the wall (X for N/S, Z for E/W)
		var thick := Vector3(absf(v.x), 0, absf(v.y)) * T    # thickness across the wall
		if sides[d] == RoomGrid.Side.WALL:
			s.append_array(_box(along * 3.7 + thick + Vector3(0, WALL_H, 0), edge + Vector3(0, WALL_H / 2, 0)))
		else:
			# doorway wall: two side blocks and a lintel around the 1.6 x 2.3 cutout
			for sign in [-1.0, 1.0]:
				s.append_array(_box(along * 1.05 + thick + Vector3(0, WALL_H, 0),
					edge + along * 1.325 * sign + Vector3(0, WALL_H / 2, 0)))
			s.append_array(_box(along * 1.6 + thick + Vector3(0, 0.7, 0), edge + Vector3(0, 2.65, 0)))
			# door frame: jambs and header inside the cutout (clear opening 1.4 x 2.2)
			for sign in [-1.0, 1.0]:
				s.append_array(_box(along * 0.1 + thick + Vector3(0, 2.3, 0),
					edge + along * 0.75 * sign + Vector3(0, 1.15, 0)))
			s.append_array(_box(along * 1.4 + thick + Vector3(0, 0.1, 0), edge + Vector3(0, 2.25, 0)))
	return s


func _init() -> void:
	var scene: Node = load(SRC).instantiate()
	var lib := MeshLibrary.new()
	var count := 0
	var tris := 0
	for node in scene.find_children("Room_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var code := String(mi.name).substr(5)               # e.g. "WDOW"
		var sides: Array[int] = []
		for ch in code:
			sides.append(RoomGrid.LETTERS.find(ch))
		var id := RoomGrid.item_id(sides[0], sides[1], sides[2], sides[3])
		lib.create_item(id)
		lib.set_item_name(id, "Room_" + code)
		lib.set_item_mesh(id, mi.mesh)
		lib.set_item_shapes(id, _shapes(sides))
		count += 1
		for sidx in mi.mesh.get_surface_count():
			tris += (mi.mesh.surface_get_arrays(sidx)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var err := ResourceSaver.save(lib, OUT)
	scene.free()
	print("items=", count, " triangles=", tris, " shared box shapes=", _boxes.size(), " save=", "OK" if err == OK else err)
	quit()
