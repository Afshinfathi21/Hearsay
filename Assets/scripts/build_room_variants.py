"""Build Environment/room_grid/room_variants.glb  (run: blender -b --python build_room_variants.py)

One merged mesh per room variant, for a Godot MeshLibrary / GridMap.
A room is one 4 x 4 m cell: floor, ceiling, light fixture, four corner posts and
four sides. Each side is one of
    W = wall          D = doorway wall + door frame (door panel is spawned separately)
    O = open          (no geometry: the neighbouring cell supplies the wall/door)
Variants are named Room_<N><E><S><W>, e.g. Room_WWWW (closed box), Room_DWOW.
Compass (Godot): N = -Z, E = +X, S = +Z, W = -X  (Blender: N = +Y, E = +X, S = -Y, W = -X).
Origin = cell centre at floor level (floor top at y = 0, ceiling underside at y = 3.0).
"""
import os
import sys
import math
import itertools
import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *          # noqa
from common import _merge

ROOT = "/home/claude/asset_pack"
OUT_DIR = os.path.join(ROOT, "Environment/room_grid")
os.makedirs(OUT_DIR, exist_ok=True)

reset_scene()

# ---- import the already-verified kit modules ------------------------------------------
PARTS = {}
slot_names = {}
for key, fname, objname in (("floor", "env_floor_4m", "Env_Floor_4m"),
                            ("ceiling", "env_ceiling_4m", "Env_Ceiling_4m"),
                            ("wall", "env_wall_straight", "Env_Wall_Straight"),
                            ("post", "env_wall_post", "Env_Wall_Post"),
                            ("doorway", "env_wall_doorway", "Env_Wall_Doorway"),
                            ("frame", "env_door_frame", "Env_Door_Frame"),
                            ("light", "env_light_ceiling", "Env_Light_Ceiling")):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "Environment", fname + ".glb"))
    new = set(bpy.data.objects) - before
    obj = [o for o in new if o.type == 'MESH' and "colonly" not in o.name][0]
    PARTS[key] = obj
    slot_names[key] = [m.name.split(".")[0] for m in obj.data.materials]
    assert obj.matrix_world.is_identity or max(abs(v) for r in (obj.matrix_world - Matrix.Identity(4)) for v in r) < 1e-6, key

# canonical material slots shared by every variant
SLOTS = ["M_Concrete_Rough", "M_Concrete_Painted", "M_Steel_Dark_Brushed",
         "M_Polymer_Rubber", "M_Emissive_Light_White"]
SLOT_INDEX = {n: i for i, n in enumerate(SLOTS)}
# (floor/ceiling use painted concrete as slot 0 of their own mesh etc. - remapped by name)
for k in list(slot_names):
    for n in slot_names[k]:
        assert n in SLOT_INDEX, (k, n)

# drop the imported materials; build clean library materials with the same names
src_meshes = {k: o.data for k, o in PARTS.items()}
for m in list(bpy.data.materials):
    bpy.data.materials.remove(m)
MATS = [get_material(n) for n in SLOTS]

col = new_collection("RoomVariants")


def part(key, loc, rot_deg=0.0):
    """Copy of a kit module, transformed into room space, material slots remapped by name."""
    bm = bmesh.new()
    bm.from_mesh(src_meshes[key])
    M = Matrix.Translation(Vector(loc)) @ Matrix.Rotation(math.radians(rot_deg), 4, 'Z')
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    names = slot_names[key]
    for f in bm.faces:
        f.material_index = SLOT_INDEX[names[f.material_index]]
        f.smooth = False                     # hard-surface kit: flat shading
    bm.normal_update()
    return bm


EDGES = {  # side: (location, rotation about Z)
    "N": ((0, 2, 0), 0), "E": ((2, 0, 0), 90), "S": ((0, -2, 0), 0), "W": ((-2, 0, 0), 90)}

LETTERS = "WDO"
objs = []
stats = []
for combo in itertools.product(LETTERS, repeat=4):          # N, E, S, W
    name = "Room_" + "".join(combo)
    bm = bmesh.new()

    def add(key, loc, rot=0.0):
        p = part(key, loc, rot)
        _merge(bm, p)

    add("floor", (0, 0, 0))
    add("ceiling", (0, 0, 3.0))
    add("light", (0, 0, 3.0))
    for sx in (-2, 2):
        for sy in (-2, 2):
            add("post", (sx, sy, 0))
    for side, t in zip("NESW", combo):
        loc, rot = EDGES[side]
        if t == "W":
            add("wall", loc, rot)
        elif t == "D":
            add("doorway", loc, rot)
            add("frame", loc, rot)

    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in MATS:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = False
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    objs.append(o)
    me.calc_loop_triangles()
    stats.append((name, len(me.loop_triangles)))

bpy.context.view_layer.update()

# ---- sanity checks on a few variants --------------------------------------------------
def bounds(o):
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for v in o.bound_box:
        lo = Vector(map(min, lo, v))
        hi = Vector(map(max, hi, v))
    return lo, hi


byname = {o.name: o for o in objs}
lo, hi = bounds(byname["Room_WWWW"])
print("Room_WWWW bounds:", tuple(round(c, 3) for c in lo), tuple(round(c, 3) for c in hi),
      "(expect -2.15,-2.15,-0.2 .. 2.15,2.15,3.3)")
lo, hi = bounds(byname["Room_OOOO"])
print("Room_OOOO bounds:", tuple(round(c, 3) for c in lo), tuple(round(c, 3) for c in hi),
      "(expect posts only on the walls' footprint: still -2.15..2.15)")
tr = [t for _, t in stats]
print("variants:", len(objs), "| tris min/avg/max:", min(tr), round(sum(tr) / len(tr)), max(tr),
      "| total:", sum(tr))
for n in ("Room_WWWW", "Room_OOOO", "Room_DOOO", "Room_DDDD"):
    print("   %s tris=%d" % (n, dict(stats)[n]))

# ---- export one GLB (all variants overlap at the origin on purpose), then lay out for the .blend
roots = objs
export_glb(roots, os.path.join(OUT_DIR, "room_variants.glb"))
for i, o in enumerate(objs):
    a, b = divmod(i, 9)                      # rows: N,E   columns: S,W
    o.location = (b * 5.0, -a * 5.0, 0)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "room_variants.blend"))
print("size MB:", round(os.path.getsize(os.path.join(OUT_DIR, "room_variants.glb")) / 1e6, 2))
