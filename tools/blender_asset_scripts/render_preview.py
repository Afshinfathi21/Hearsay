"""Render previews from the EXPORTED .glb files (so previews prove the export).
Run: blender -b --python render_preview.py -- <hero|open|monitor> [width] [samples]
The mock wall/floor/room is preview-only and not part of any asset."""
import os
import sys
import math
import bpy
import bmesh
from mathutils import Vector

ROOT = "/home/claude/asset_pack"
argv = sys.argv[sys.argv.index("--") + 1:]
shot = argv[0]
width = int(argv[1]) if len(argv) > 1 else 960
samples = int(argv[2]) if len(argv) > 2 else 24

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col = sc.collection


def lin(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1,)


def mat(name, hexc, rough, metallic=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(hexc)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metallic
    if emit:
        b.inputs["Emission Color"].default_value = lin(emit)
        b.inputs["Emission Strength"].default_value = strength
    return m


def box(name, x0, x1, y0, y1, z0, z1, m):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector(((v.co.x + .5) * (x1 - x0) + x0, (v.co.y + .5) * (y1 - y0) + y0,
                       (v.co.z + .5) * (z1 - z0) + z0))
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    return o


# ---- import the real assets ------------------------------------------------
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "Doors/door_standard.glb"))
door_objs = set(bpy.data.objects) - before
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "Monitors/door_monitor.glb"))
mon_objs = set(bpy.data.objects) - before
# glTF import puts the nodes at world positions; move monitor roots above the door
for o in mon_objs:
    if o.parent is None:
        o.location += Vector((0, -0.15, 2.625))

by_name = {o.name: o for o in bpy.data.objects}
for o in list(door_objs | mon_objs):
    if "colonly" in o.name:
        bpy.data.objects.remove(o)       # hide collision meshes in the render

# ---- preview-only room -----------------------------------------------------
CONC = mat("pv_concrete", "#7B8085", 0.9)
CONC2 = mat("pv_concrete_dark", "#596168", 0.75)
t = 0.15
# front wall (door wall) with 1.60 x 2.30 cutout, 3.7 m wide
box("pv_wall_L", -1.85, -0.80, -t, t, 0, 3.0, CONC)
box("pv_wall_R", 0.80, 1.85, -t, t, 0, 3.0, CONC)
box("pv_wall_T", -0.80, 0.80, -t, t, 2.30, 3.0, CONC)
box("pv_floor_front", -1.85, 1.85, -4.15, 4.0, -0.2, 0, CONC2)
box("pv_ceil_front", -1.85, 1.85, -4.15, 4.0, 3.0, 3.3, CONC2)
box("pv_side_L", -2.15, -1.85, -4.15, 4.15, -0.2, 3.3, CONC)
box("pv_side_R", 1.85, 2.15, -4.15, 4.15, -0.2, 3.3, CONC)
box("pv_back", -2.15, 2.15, 4.0, 4.3, -0.2, 3.3, CONC)
box("pv_front", -2.15, 2.15, -4.45, -4.15, -0.2, 3.3, CONC)
fix = box("pv_ceiling_fixture", -0.30, 0.30, -2.15, -1.85, 2.96, 3.0,
          mat("pv_fixture", "#101214", 0.4, emit="#E9F2FF", strength=8))

# scale dummy (1.75 m)
dm = mat("pv_dummy", "#3A3F44", 0.9)
if shot != "open":
    box("pv_dummy_body", 1.05, 1.45, -1.4, -1.0, 0.0, 1.50, dm)
    box("pv_dummy_head", 1.13, 1.37, -1.32, -1.08, 1.52, 1.75, dm)

# ---- emissive boost + digit/pip states (preview only) ----------------------
BOOST = {"M_Digit_Amber": 9, "M_Emissive_Light_Amber": 7, "M_Emissive_Light_White": 6,
         "M_Emissive_Screen": 0.8}
for m in bpy.data.materials:
    if m.name.split(".")[0] in BOOST and m.use_nodes:
        b = m.node_tree.nodes.get("Principled BSDF")
        if b:
            b.inputs["Emission Strength"].default_value = BOOST[m.name.split(".")[0]]
OFF = mat("pv_off", "#1F1208", 0.5)
PIP_OFF = mat("pv_pip_off", "#15181A", 0.5)
SEG = {"0": "ABCDEF", "1": "BC", "2": "ABGED", "3": "ABGCD", "4": "FGBC", "5": "AFGCD",
       "6": "AFGEDC", "7": "ABC", "8": "ABCDEFG", "9": "ABCDFG"}
number = "37" if shot == "monitor" else "02"
for digit, ch in zip(("Tens", "Units"), number):
    for letter in "ABCDEFG":
        o = by_name["Mon_Seg_%s_%s" % (digit, letter)]
        if letter not in SEG[ch]:
            o.data.materials[0] = OFF
for i in (3, 4):
    by_name["Mon_Pip_%d" % i].data.materials[0] = PIP_OFF

# ---- door pose ---------------------------------------------------------------
for n in ("Door_Panel", "Door_Bolt_A", "Door_Bolt_B"):
    by_name[n].animation_data_clear()
if shot == "open":
    p = by_name["Door_Panel"]
    p.rotation_mode = 'XYZ'
    p.rotation_euler = (0, 0, math.radians(100))
    for n in ("Door_Bolt_A", "Door_Bolt_B"):
        by_name[n].location.x -= 0.05

# ---- lights -----------------------------------------------------------------
def area(name, loc, size, power, color, rot=(0, 0, 0)):
    d = bpy.data.lights.new(name, 'AREA')
    d.shape = 'RECTANGLE'
    d.size, d.size_y = size
    d.energy = power
    d.color = color[:3]
    o = bpy.data.objects.new(name, d)
    o.location = loc
    o.rotation_euler = rot
    col.objects.link(o)


area("ceiling", (0, -2.0, 2.95), (0.6, 0.3), 140, (0.88, 0.93, 1.0))
area("fill", (0, -3.9, 2.0), (3.0, 1.5), 40, (0.85, 0.9, 1.0), rot=(math.radians(90), 0, 0))
pl = bpy.data.lights.new("monitor_glow", 'POINT')
pl.energy = 18
pl.color = (1.0, 0.55, 0.12)
pl.shadow_soft_size = 0.2
po = bpy.data.objects.new("monitor_glow", pl)
po.location = (0, -0.7, 2.5)
col.objects.link(po)
rear = bpy.data.lights.new("rear", 'POINT')
rear.energy = 120 if shot == "open" else 10
rear.color = (1.0, 0.75, 0.45)
ro = bpy.data.objects.new("rear", rear)
ro.location = (0.3, 2.0, 2.6)
col.objects.link(ro)

# ---- camera -----------------------------------------------------------------
CAM = {"hero": ((0.0, -3.9, 1.5), (0.0, 0.0, 1.55), 20),
       "open": ((1.45, -3.3, 1.6), (-0.3, 0.6, 1.2), 20),
       "monitor": ((0.0, -1.6, 2.5), (0.0, -0.15, 2.62), 35)}[shot]
cd = bpy.data.cameras.new("cam")
cd.lens = CAM[2]
co = bpy.data.objects.new("cam", cd)
co.location = CAM[0]
col.objects.link(co)
tgt = bpy.data.objects.new("tgt", None)
tgt.location = CAM[1]
col.objects.link(tgt)
tc = co.constraints.new('TRACK_TO')
tc.target = tgt
tc.track_axis = 'TRACK_NEGATIVE_Z'
tc.up_axis = 'UP_Y'
sc.camera = co

# ---- render -----------------------------------------------------------------
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = samples
sc.cycles.use_adaptive_sampling = True
sc.cycles.max_bounces = 4
try:
    sc.cycles.use_denoising = False  # this Blender build has no OpenImageDenoise
except Exception:
    pass
sc.render.resolution_x = width
sc.render.resolution_y = int(width * 9 / 16)
sc.render.resolution_percentage = 100
sc.view_settings.view_transform = 'Filmic' if 'Filmic' in \
    bpy.types.ColorManagedViewSettings.bl_rna.properties['view_transform'].enum_items.keys() else 'AgX'
sc.view_settings.exposure = 0.4
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.11, 0.12, 0.14, 1)
sc.world = w
sc.render.image_settings.file_format = 'PNG'
sc.render.filepath = os.path.join(ROOT, "previews", "preview_%s.png" % shot)
bpy.ops.render.render(write_still=True)
print("RENDERED", sc.render.filepath)
