extends SceneTree
# godot --headless --path . --script res://test_character.gd

func _init() -> void:
	var player := FirstPersonPlayer.new()
	player.palette_index = 1
	root.add_child(player)
	await process_frame

	var model: PlayerCharacter = player.model
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	print("skeleton bones: ", skel.get_bone_count())

	# 1) bone names vs Godot's humanoid profile
	var prof := SkeletonProfileHumanoid.new()
	var missing: Array[String] = []
	var matched := 0
	var bm := BoneMap.new()
	bm.profile = prof
	for i in prof.bone_size:
		var n := prof.get_bone_name(i)
		if skel.find_bone(n) >= 0:
			matched += 1
			bm.set_skeleton_bone_name(n, n)
		else:
			missing.append(n)
	print("humanoid profile bones: ", prof.bone_size, " matched: ", matched)
	print("unmatched (expected: fingers/eyes/jaw/ToesEnd only): ", missing)

	# 2) rest pose sanity (global rest of a few bones, metres, Y-up)
	for b in ["Hips", "Head", "LeftHand", "RightHand", "LeftFoot", "LeftToes"]:
		var idx := skel.find_bone(b)
		print("  rest ", b, " = ", skel.get_bone_global_rest(idx).origin.snapped(Vector3(0.001, 0.001, 0.001)))

	# 3) meshes, skins, triangle counts
	var tris_total := 0
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var t := 0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			t += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("  %-16s tris=%4d skin=%s visible=%s layers=%d" % [mi.name, t, mi.skin != null, mi.visible, mi.layers])
		if mi.visible:
			tris_total += t
	print("visible triangles (default outfit): ", tris_total)

	# 4) first-person separation
	print("camera y=", player.camera.position.y, " cull_mask has body layer: ", (player.camera.cull_mask & PlayerCharacter.BODY_LAYER) != 0, " (expect false)")
	print("model faces +Z rotated PI: rotation.y=", snappedf(model.rotation.y, 0.001))

	# 5) variants + colours
	model.configure(2, PlayerCharacter.Top.HOODIE, PlayerCharacter.Headwear.BEANIE)
	var hood := model.find_child("Char_Top_Hoodie", true, false) as MeshInstance3D
	var jack := model.find_child("Char_Top_Jacket", true, false) as MeshInstance3D
	var bean := model.find_child("Char_Beanie", true, false) as MeshInstance3D
	print("hoodie visible=", hood.visible, " jacket visible=", jack.visible, " beanie visible=", bean.visible,
		" hoodie colour=", (hood.material_override as BaseMaterial3D).albedo_color.to_html(false), " (expect 5c6b3a)")

	# 6) skinned bounds
	var lo := 1e9
	var hi := -1e9
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (m as MeshInstance3D).get_aabb()
		lo = minf(lo, a.position.y)
		hi = maxf(hi, a.end.y)
	print("mesh height range y=", snappedf(lo, 0.001), "..", snappedf(hi, 0.001))
	quit()
