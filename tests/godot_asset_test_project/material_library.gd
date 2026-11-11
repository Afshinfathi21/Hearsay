class_name MaterialLibrary
extends RefCounted
## Looks up library materials by the names used in the GLB files (e.g. "M_Concrete_Rough").
##
## Two ways to use the library:
##  1. Automatically at import: set `apply_material_library.gd` as the Import Script of each .glb
##     (Import dock > Advanced... > Import Script). The textured materials are then baked into the
##     imported scene.
##  2. At runtime, on any instanced scene:  MaterialLibrary.apply(instance)
##     (non-destructive: uses surface override materials).

const DIR := "res://Materials/"
static var _cache := {}


static func get_material(material_name: String) -> Material:
	if not _cache.has(material_name):
		var path := DIR + material_name + ".tres"
		_cache[material_name] = load(path) if ResourceLoader.exists(path) else null
	return _cache[material_name]


## Returns how many surfaces were replaced.
static func apply(root: Node) -> int:
	var count := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null:
				continue
			var lib := get_material(src.resource_name)
			if lib != null:
				mi.set_surface_override_material(s, lib)
				count += 1
	return count
