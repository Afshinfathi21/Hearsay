extends SceneTree
func _init() -> void:
	var n := Node3D.new()
	n.set_script(load("res://room_grid_demo.gd"))
	root.add_child(n)
	await process_frame
	await physics_frame
	var gm := n.get_node("Rooms") as GridMap
	print("demo: cells=", gm.get_used_cells().size(), " cell_size=", gm.cell_size, " lights=", n.find_children("*", "OmniLight3D", false, false).size())
	quit()
