"""Render the RoomGrid demo layout from room_variants.glb (ceilings removed for the picture only).
Run: blender -b --python render_room_grid.py -- [width] [samples]"""
import os, sys, math
import bpy, bmesh
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import blender_pbr as pb
argv = sys.argv[sys.argv.index("--") + 1:]
width = int(argv[0]) if argv else 1200
samples = int(argv[1]) if len(argv) > 1 else 28

# ---- same logic as RoomGrid.place_rooms (so the picture cross-checks the GDScript) -------------
W, D, O = 0, 1, 2
DIRS = [(0, -1), (1, 0), (0, 1), (-1, 0)]          # N, E, S, W in (x, z)
cells = [(0, 0), (1, 0), (1, 1), (2, 0)]
links = [{"a": (0, 0), "b": (1, 0), "type": D}, {"a": (1, 0), "b": (1, 1), "type": O}]
key = lambda a, b: tuple(sorted([a, b]))
link_of = {key(l["a"], l["b"]): l for l in links}
ids, sides_of = {}, {}
for c in cells:
    s = [W] * 4
    for d, (dx, dz) in enumerate(DIRS):
        n = (c[0] + dx, c[1] + dz)
        if n not in cells:
            continue
        l = link_of.get(key(c, n))
        if l:
            s[d] = O if l["type"] == O else (D if c == l["a"] else O)
        else:
            s[d] = W if (c[0], c[1]) < n else O
    sides_of[c] = s
    ids[c] = ((s[0] * 3 + s[1]) * 3 + s[2]) * 3 + s[3]
print("python ids:", ids, "(Godot printed A=9 B=8 C=54 D=2)")
assert ids == {(0, 0): 9, (1, 0): 8, (1, 1): 54, (2, 0): 2}

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col = sc.collection
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets/the_exit_room/environment/room_grid/room_variants.glb"))
variants = {o.name: o for o in bpy.data.objects if o.type == 'MESH'}
LET = "WDO"
for c in cells:
    name = "Room_" + "".join(LET[v] for v in sides_of[c])
    src = variants[name]
    o = src.copy()
    o.data = src.data.copy()
    col.objects.link(o)
    o.location = (c[0] * 4 + 2, -(c[1] * 4 + 2), 0)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    kill = [f for f in bm.faces if f.calc_center_median().z > 2.99 and (f.normal.z < -0.5 or f.calc_center_median().z > 3.05)]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(o.data)
    bm.free()
    pb.apply_library([o])
for o in list(variants.values()):
    bpy.data.objects.remove(o)

# door (front faces into the owning room A), minus its frame, plus both monitors
def place(path, loc, rot):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, path))
    new = set(bpy.data.objects) - before
    e = bpy.data.objects.new("inst", None)
    col.objects.link(e)
    e.location, e.rotation_euler = loc, (0, 0, math.radians(rot))
    for o in new:
        if o.parent is None:
            o.parent = e
    for o in list(new):
        if "colonly" in o.name or o.name.startswith("Door_Frame"):
            o.hide_render = True
    pb.apply_library(new)
    return new

place("Doors/door_standard.glb", (4, -2, 0), -90)
m1 = place("Monitors/door_monitor.glb", (3.85, -2, 2.625), -90)
m2 = place("Monitors/door_monitor.glb", (4.15, -2, 2.625), 90)
for m in bpy.data.materials:
    k = m.name.split(".")[0]
    boost = {"M_Digit_Amber": 9, "M_Emissive_Light_Amber": 7, "M_Emissive_Light_White": 8, "M_Emissive_Screen": 0.8}
    if k in boost and m.use_nodes and m.node_tree.nodes.get("Principled BSDF"):
        m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = boost[k]

def area(name, loc, size, power, color, rx=0):
    d = bpy.data.lights.new(name, 'AREA')
    d.shape, d.size, d.size_y, d.energy, d.color = 'RECTANGLE', size[0], size[1], power, color
    o = bpy.data.objects.new(name, d)
    o.location, o.rotation_euler = loc, (math.radians(rx), 0, 0)
    col.objects.link(o)

for c in cells:
    area("room%d%d" % c, (c[0] * 4 + 2, -(c[1] * 4 + 2), 2.9), (0.8, 0.2), 120, (0.88, 0.93, 1.0))
area("sky", (6, -4, 14), (14, 10), 2500, (0.9, 0.93, 1.0))
cd = bpy.data.cameras.new("cam")
cd.lens = 26
co = bpy.data.objects.new("cam", cd)
co.location = (5.0, -15.5, 13.5)
col.objects.link(co)
co.rotation_euler = (Vector((6.0, -3.6, 0.5)) - co.location).to_track_quat('-Z', 'Y').to_euler()
sc.camera = co
sc.render.engine = 'CYCLES'
sc.cycles.device, sc.cycles.samples, sc.cycles.use_denoising = 'CPU', samples, False
sc.cycles.use_adaptive_sampling = True
sc.cycles.max_bounces = 4
sc.render.resolution_x, sc.render.resolution_y = width, int(width * 9 / 16)
sc.view_settings.exposure = 0.0
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.2, 0.21, 0.24, 1)
sc.world = w
sc.render.filepath = os.path.join(ROOT, "previews", "preview_room_grid.png")
bpy.ops.render.render(write_still=True)
print("RENDERED")
