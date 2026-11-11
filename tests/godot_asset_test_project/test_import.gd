extends SceneTree
# Headless import check: godot --headless --path . --script res://test_import.gd

func dump(n: Node, depth := 0) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var a := mi.get_aabb()
		extra = " mesh surfaces=%d size=%s" % [mi.mesh.get_surface_count(), a.size.snapped(Vector3(0.001,0.001,0.001))]
	elif n is CollisionShape3D:
		extra = " shape=%s" % (n as CollisionShape3D).shape.get_class()
	print("  ".repeat(depth), n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		dump(c, depth + 1)

func _init() -> void:
	var door: Node3D = load("res://Doors/door_standard.glb").instantiate()
	print("=== DOOR TREE ===")
	dump(door)
	var ap := door.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("animations: ", ap.get_animation_list(), " length=", ap.get_animation("Door_Open").length)
	var panel := door.find_child("Door_Panel", true, false) as Node3D
	print("panel pivot (local pos) = ", panel.position, "  (expect x=-0.67, z=-0.05: hinge axis)")
	var mat := (door.find_child("Door_Frame", true, false) as MeshInstance3D).mesh.surface_get_material(0)
	print("frame mat0: ", mat.resource_name, " class=", mat.get_class(), " metallic multiplier=", (mat as BaseMaterial3D).metallic)

	var mon: Node3D = load("res://Monitors/door_monitor.glb").instantiate()
	print("=== MONITOR TREE (segments collapsed) ===")
	for c in mon.get_children():
		if c.name.begins_with("Mon_Digit"):
			print(c.name, " children=", c.get_child_count())
		else:
			dump(c, 0)

	# Run the scripts
	door.set_script(load("res://door_standard.gd"))
	mon.set_script(load("res://door_monitor.gd"))
	root.add_child(door)     # _ready() runs here, once
	root.add_child(mon)
	await process_frame      # SceneTree isn't running inside _init; let _ready() fire
	mon.show_number(37)
	mon.set_capacity(2)
	mon.set_locked(true)
	var tens: Node = mon.get_node("Mon_Digit_Tens")
	var lit := []
	for d in ["Tens", "Units"]:
		var s := ""
		for l in "ABCDEFG":
			var seg := mon.get_node("Mon_Digit_%s/Mon_Seg_%s_%s" % [d, d, l]) as MeshInstance3D
			if seg.material_override.emission_enabled:
				s += l
		lit.append(s)
	print("show_number(37) lit segments tens/units: ", lit, "  (expect ABGCD / ABC)")
	mon.show_number(5)
	var blank := ""
	for l in "ABCDEFG":
		if (mon.get_node("Mon_Digit_Tens/Mon_Seg_Tens_%s" % l) as MeshInstance3D).material_override.emission_enabled:
			blank += l
	print("show_number(5) tens lit: '", blank, "' (expect blank)")
	door.open()
	print("door.open() called; anim playing=", ap.current_animation)
	quit()
