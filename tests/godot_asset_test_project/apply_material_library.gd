@tool
extends EditorScenePostImport
## Import script: swaps the flat glTF materials for the textured library materials of the
## same name. Self-contained on purpose (no class_name lookups) so it works on first import.

const DIR := "res://Materials/"


func _post_import(scene: Node) -> Object:
	var swapped := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s)
			if src == null:
				continue
			var path := DIR + src.resource_name + ".tres"
			if ResourceLoader.exists(path):
				mesh.surface_set_material(s, load(path))
				swapped += 1
	print("apply_material_library: swapped ", swapped, " surface materials in ", scene.name)
	return scene
