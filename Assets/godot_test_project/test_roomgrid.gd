extends SceneTree
# godot --headless --path . --script res://test_roomgrid.gd
# Layout (x, z):   A(0,0) -door-> B(1,0) -wall- D(2,0)
#                               B(1,0) -open- C(1,1)

func _ray(from: Vector3, to: Vector3) -> String:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := root.world_3d.direct_space_state.intersect_ray(q)
	return "no hit" if hit.is_empty() else "hit at %s" % (hit["position"] as Vector3).snapped(Vector3(0.01, 0.01, 0.01))


func _init() -> void:
	var gm := GridMap.new()
	root.add_child(gm)
	RoomGrid.setup(gm)
	var A := Vector2i(0, 0)
	var B := Vector2i(1, 0)
	var C := Vector2i(1, 1)
	var D := Vector2i(2, 0)
	var cells: Array[Vector2i] = [A, B, C, D]
	var placed := RoomGrid.place_rooms(gm, cells, [
		{"a": A, "b": B, "type": RoomGrid.Side.DOOR},
		{"a": B, "b": C, "type": RoomGrid.Side.OPEN}])
	print("library items: ", gm.mesh_library.get_item_list().size(), "  cell_size=", gm.cell_size)
	for c in [A, B, C, D]:
		print("  cell ", c, " -> id ", placed[c], " ", gm.mesh_library.get_item_name(placed[c]))
	print("expect: A=Room_WDWW  B=Room_WWOO  C=Room_OWWW  D=Room_WWWO")

	# every shared edge must be drawn by exactly one cell (door/wall) or by none (open link)
	var edges := {"A-B (door)": [placed[A], 1, placed[B], 3, 1], "B-D (wall)": [placed[B], 1, placed[D], 3, 1],
		"B-C (open)": [placed[B], 2, placed[C], 0, 0]}
	for k in edges:
		var e: Array = edges[k]
		var drawn := int(RoomGrid.sides_of(e[0])[e[1]] != RoomGrid.Side.OPEN) + int(RoomGrid.sides_of(e[2])[e[3]] != RoomGrid.Side.OPEN)
		print("  edge ", k, ": drawn by ", drawn, " cell(s) (expect ", e[4], ")")

	# combined visual bounds of all placed cells
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var arr := gm.get_meshes()
	for i in range(0, arr.size(), 2):
		var xf: Transform3D = arr[i]
		var mesh: Mesh = arr[i + 1]
		var b := xf * mesh.get_aabb()
		lo = lo.min(b.position)
		hi = hi.max(b.end)
	print("bounds lo=", lo.snapped(Vector3(0.001, 0.001, 0.001)), " hi=", hi.snapped(Vector3(0.001, 0.001, 0.001)), "  expect (-0.15,-0.2,-0.15) .. (12.15,3.3,8.15)")

	await process_frame            # let the GridMap enter the tree before using global transforms
	await physics_frame
	await physics_frame
	print("BEFORE spawning the door: A centre -> east: ", _ray(Vector3(2, 1.5, 2), Vector3(20, 1.5, 2)), "   (open doorway: passes through, stops at B's east wall x~7.85)")
	# doors, monitors, lights
	var doors := RoomGrid.spawn_doors(gm, root, load("res://Doors/door_standard.glb"), load("res://Monitors/door_monitor.glb"))
	var lights := RoomGrid.add_lights(gm, root)
	await process_frame
	await physics_frame
	await physics_frame
	var door := doors[0]
	print("doors=", doors.size(), " lights=", lights.size(), "  door pos=", door.global_position, " front(+Z)=", door.global_transform.basis.z.snapped(Vector3(0.01, 0.01, 0.01)), " (expect (4,0,2), front (-1,0,0) = into owner room A)")
	print("door frame removed: ", door.find_child("Door_Frame", true, false) == null, "  status lights kept: ", door.find_child("Door_Status_Light_Front", true, false) != null)
	var mons := root.find_children("*", "Node3D", false, false).filter(func(n): return n.get_script() != null and "monitor" in String(n.get_script().resource_path))
	print("monitors=", mons.size(), " positions=", mons.map(func(m): return m.global_position))

	print("=== physics rays (y=1.5) ===")
	print("A centre -> west     : ", _ray(Vector3(2, 1.5, 2), Vector3(-3, 1.5, 2)), "   (expect x~0.15: west wall)")
	print("A centre -> east     : ", _ray(Vector3(2, 1.5, 2), Vector3(20, 1.5, 2)), "   (door spawned and closed: its panel blocks at x~3.95)")
	print("A -> east off-centre : ", _ray(Vector3(2, 1.5, 2.75), Vector3(20, 1.5, 2.75)), "   (door frame jamb x~3.85)")
	print("C centre -> north    : ", _ray(Vector3(6, 1.5, 6), Vector3(6, 1.5, -3)), "   (open link: passes z=4, hits B's north wall z~0.15)")
	print("D centre -> west     : ", _ray(Vector3(10, 1.5, 2), Vector3(3.5, 1.5, 2)), "   (one shared wall, hit x~8.15)")
	print("A down               : ", _ray(Vector3(2, 1.0, 2), Vector3(2, -1.0, 2)), "   (floor y~0)")
	print("A up                 : ", _ray(Vector3(2, 1.0, 2), Vector3(2, 5.0, 2)), "   (ceiling y~3.0)")
	quit()
