"""Props sheet + material swatches, rendered from the exported GLBs and generated textures.
Run: blender -b --python render_props.py -- <props|swatches> [width] [samples]"""
import os
import sys
import math
import bpy
from mathutils import Vector

ROOT = "/home/claude/asset_pack"
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from common import *          # noqa
import blender_pbr as pb

argv = sys.argv[sys.argv.index("--") + 1:]
shot = argv[0]
width = int(argv[1]) if len(argv) > 1 else 1100
samples = int(argv[2]) if len(argv) > 2 else 28

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col = sc.collection


def slab(name, x0, x1, y0, y1, z0, z1, matname):
    bm = bmesh.new()
    add_box(bm, ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), 0)
    o = finalize(name, bm, col, [pb.pbr(matname)], origin=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    return o


def place(path, loc, rot_z=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, path))
    new = set(bpy.data.objects) - before
    e = bpy.data.objects.new("inst", None)
    col.objects.link(e)
    e.location = loc
    e.rotation_euler = (0, 0, math.radians(rot_z))
    for o in new:
        if o.parent is None:
            o.parent = e
    keep = set()
    for o in list(new):
        if "colonly" in o.name:
            bpy.data.objects.remove(o)       # collision meshes are not rendered
        else:
            keep.add(o)
    pb.apply_library(keep)
    return e, keep


def text(label, loc, size=0.11):
    c = bpy.data.curves.new(label, 'FONT')
    c.body = label
    c.size = size
    c.align_x = 'CENTER'
    o = bpy.data.objects.new(label, c)
    o.location = loc
    o.rotation_euler = (math.radians(90), 0, 0)
    m = bpy.data.materials.new("lbl")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.9, 0.9, 0.9, 1)
    b.inputs["Emission Color"].default_value = (0.9, 0.9, 0.9, 1)
    b.inputs["Emission Strength"].default_value = 0.8
    o.data.materials.append(m)
    col.objects.link(o)


def light(name, loc, size, power, color, rx=0, rz=0):
    d = bpy.data.lights.new(name, 'AREA')
    d.shape = 'RECTANGLE'
    d.size, d.size_y = size
    d.energy = power
    d.color = color
    o = bpy.data.objects.new(name, d)
    o.location = loc
    o.rotation_euler = (math.radians(rx), 0, math.radians(rz))
    col.objects.link(o)


BOOST = {"M_Digit_Amber": 9, "M_Emissive_Light_Amber": 7, "M_Emissive_Light_White": 7,
         "M_Emissive_Light_Red": 9, "M_Emissive_Screen": 0.8}


def boost_emissives():
    for m in bpy.data.materials:
        k = m.name.split(".")[0]
        if k in BOOST and m.use_nodes and m.node_tree.nodes.get("Principled BSDF"):
            m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = BOOST[k]


if shot == "swatches":
    names = ["M_Concrete_Rough", "M_Concrete_Painted", "M_Steel_Dark_Brushed", "M_Paint_Worn",
             "M_Polymer_Rubber", "M_Glass_Frosted"]
    slab("floor", -5, 5, -3, 3, -0.2, 0, "M_Concrete_Painted")
    slab("back", -5, 5, 1.4, 1.7, 0, 3, "M_Concrete_Rough")
    for i, n in enumerate(names):
        x = -2.5 + i
        if n == "M_Glass_Frosted":
            bm = bmesh.new()
            add_box(bm, (x, 0, 0.45), (0.8, 0.8, 0.9), 0, bevel=0.02)
            o = finalize("sw_" + n, bm, col, [get_material("M_Glass_Frosted")], origin=(x, 0, 0.45))
            inner = bmesh.new()
            add_box(inner, (x, 0, 0.45), (0.3, 0.3, 0.3), 0, bevel=0.01)
            finalize("sw_core", inner, col, [get_material("M_Emissive_Light_Amber")], origin=(x, 0, 0.45))
        else:
            bm = bmesh.new()
            add_box(bm, (x, 0, 0.45), (0.8, 0.8, 0.9), 0, bevel=0.02)
            finalize("sw_" + n, bm, col, [pb.pbr(n)], origin=(x, 0, 0.45))
        text(n.replace("M_", "").replace("_", " "), (x, -0.55, 0.0), 0.075)
    boost_emissives()
    cam_loc, cam_tgt, lens = (0.0, -5.2, 1.4), (0.0, 0, 0.5), 24
    light("key", (-2.0, -3.0, 3.5), (3, 3), 600, (1, 0.95, 0.88), 55, -30)
    light("fill", (3.0, -3.0, 2.0), (3, 3), 220, (0.8, 0.88, 1), 70, 35)
else:
    slab("wall", -4.2, 4.2, 0.0, 0.3, 0, 3.0, "M_Concrete_Rough")
    slab("wall_low", -4.2, 4.2, -0.02, 0.0, 0, 1.0, "M_Concrete_Painted")
    slab("floor", -4.2, 4.2, -4.0, 0.3, -0.2, 0, "M_Concrete_Painted")
    slab("ceiling", -4.2, 4.2, -4.0, 0.3, 3.0, 3.3, "M_Concrete_Painted")
    items = [("Props/prop_electrical_panel.glb", (-1.55, 0, 1.45), 0),
             ("Props/prop_speaker_wall.glb", (-0.45, 0, 2.65), 0),
             ("Props/prop_camera_wall.glb", (0.5, 0, 2.55), 0),
             ("Props/prop_emergency_light.glb", (1.45, 0, 2.5), 0),
             ("Props/prop_number_plate.glb", (0.95, 0, 1.65), 0),
             ("Props/prop_ceiling_vent.glb", (1.9, 0, 1.3), 0)]
    insts = {}
    for path, loc, rz in items:
        e, objs = place(path, loc, rz)
        insts[path] = (e, objs)
    # the ceiling vent is shown on the wall here, rotated to face the camera
    e, objs = insts["Props/prop_ceiling_vent.glb"]
    e.rotation_euler = (math.radians(-90), 0, 0)
    # open the electrical panel door and pan the camera head for the shot
    e, objs = insts["Props/prop_electrical_panel.glb"]
    for o in objs:
        if o.name.startswith("Prop_ElectricalPanel_Door"):
            o.rotation_mode = 'XYZ'
            o.rotation_euler = (0, 0, math.radians(-105))
    e, objs = insts["Props/prop_camera_wall.glb"]
    for o in objs:
        if o.name.startswith("Prop_Camera_Head"):
            o.rotation_mode = 'XYZ'
            o.rotation_euler = (0, 0, math.radians(28))
    boost_emissives()
    cam_loc, cam_tgt, lens = (0.15, -3.4, 1.6), (0.15, 0, 1.6), 28
    light("key", (-2.5, -3.5, 2.8), (3, 2), 520, (1, 0.95, 0.88), 70, -25)
    light("fill", (3.0, -3.5, 1.5), (3, 2), 180, (0.8, 0.88, 1), 80, 25)

cd = bpy.data.cameras.new("cam")
cd.lens = lens
co = bpy.data.objects.new("cam", cd)
co.location = cam_loc
col.objects.link(co)
co.rotation_euler = (Vector(cam_tgt) - Vector(cam_loc)).to_track_quat('-Z', 'Y').to_euler()
sc.camera = co
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = samples
sc.cycles.use_adaptive_sampling = True
sc.cycles.max_bounces = 5
sc.cycles.use_denoising = False
sc.cycles.transparent_max_bounces = 8
sc.render.resolution_x = width
sc.render.resolution_y = int(width * 9 / 16)
sc.view_settings.exposure = 0.3
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.13, 0.15, 1)
sc.world = w
sc.render.image_settings.file_format = 'PNG'
sc.render.filepath = os.path.join(ROOT, "previews", "preview_%s.png" % shot)
bpy.ops.render.render(write_still=True)
print("RENDERED", sc.render.filepath)
