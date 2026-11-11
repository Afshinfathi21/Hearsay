extends SceneTree
# godot --headless --path . --script res://test_props.gd

func dump(n: Node, depth := 0) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var kinds := []
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			kinds.append("%s:%s" % [m.resource_name, m.get_class()])
		extra = " " + str(kinds)
	elif n is CollisionShape3D:
		extra = " shape=" + (n as CollisionShape3D).shape.get_class()
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		dump(c, depth + 1)

func _init() -> void:
	# 1) every library material loads, has the right class and its textures
	print("=== LIBRARY ===")
	var dir := DirAccess.open("res://Materials/")
	var names: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".tres"):
			names.append(f)
	names.sort()
	for f in names:
		var m := load("res://Materials/" + f) as Material
		var tex := ""
		if m is ORMMaterial3D:
			var o := m as ORMMaterial3D
			tex = "albedo=%s orm=%s normal=%s" % [o.albedo_texture != null, o.orm_texture != null, o.normal_texture != null]
		elif m is StandardMaterial3D:
			var s := m as StandardMaterial3D
			tex = "emission=%s transparency=%d normal=%s" % [s.emission_enabled, s.transparency, s.normal_texture != null]
		print("  %-26s %-18s %s" % [m.resource_name, m.get_class(), tex])

	# 2) props: structure, collision, materials
	print("=== PROPS ===")
	for p in ["prop_camera_wall", "prop_emergency_light", "prop_electrical_panel", "prop_ceiling_vent", "prop_floor_marking_hazard"]:
		var inst: Node3D = load("res://Props/%s.glb" % p).instantiate()
		dump(inst)
		inst.free()
	var cam: Node3D = load("res://Props/prop_camera_wall.glb").instantiate()
	var head := cam.find_child("Prop_Camera_Head", true, false) as Node3D
	print("camera head pivot (local) = ", head.position, " (expect (0, 0, 0.11): arm end, Godot +Z = front)")
	var plate: Node3D = load("res://Props/prop_number_plate.glb").instantiate()
	print("number plate label anchor = ", (plate.find_child("Anchor_Label", true, false) as Node3D).position, " (front face, +Z)")
	cam.free()
	plate.free()

	# 3) runtime helper
	var panel: Node3D = load("res://Props/prop_electrical_panel.glb").instantiate()
	print("MaterialLibrary.apply swapped ", MaterialLibrary.apply(panel), " surfaces")
	panel.free()
	quit()
