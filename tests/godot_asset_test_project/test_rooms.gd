extends SceneTree
# godot --headless --path . --script res://test_rooms.gd

func _init() -> void:
	var rb := RoomBuilder.new()
	root.add_child(rb)
	rb.build([Vector2i(0, 0), Vector2i(1, 0)], [[Vector2i(0, 0), Vector2i(1, 0)]])
	await process_frame
	var counts := {}
	for c in rb.get_children():
		var key := String(c.name).get_slice("@", 0).rstrip("0123456789")
		counts[key] = counts.get(key, 0) + 1
	print("children by name: ", counts)

	# global bounds of every visible mesh
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var stack: Array[Node] = [rb]
	var meshes := 0
	var bodies := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			meshes += 1
			var b: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
			lo = lo.min(b.position)
			hi = hi.max(b.end)
		elif n is StaticBody3D:
			bodies += 1
	print("meshes=", meshes, " static bodies=", bodies)
	print("bounds lo=", lo.snapped(Vector3(0.001, 0.001, 0.001)), " hi=", hi.snapped(Vector3(0.001, 0.001, 0.001)))
	print("expect  lo=(-0.15, -0.2, -0.15)  hi=(8.15, 3.3, 4.15)")

	var d: Dictionary = rb.doors.values()[0]
	var door: Node3D = d["door"]
	var mf: Node3D = d["monitor_front"]
	print("door pos=", door.global_position, " front(+Z)=", door.global_transform.basis.z.snapped(Vector3(0.01, 0.01, 0.01)), "  (expect (4,0,2), front (-1,0,0) = toward cell 0)")
	print("monitor_front pos=", mf.global_position, " front=", mf.global_transform.basis.z.snapped(Vector3(0.01, 0.01, 0.01)), " (expect (3.85,2.625,2) facing -X)")
	(mf as DoorMonitor).show_number(3)
	(mf as DoorMonitor).set_capacity(3)
	(door as StandardDoor).open()
	print("scripts ran: door anim=", (door.find_child("AnimationPlayer", true, false) as AnimationPlayer).current_animation)
	quit()
