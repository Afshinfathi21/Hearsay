"""Render the character from the EXPORTED .glb.
Run: blender -b --python render_character.py -- <tpose|posetest|lineup> [width] [samples]
"""
import os
import sys
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[sys.argv.index("--") + 1:]
shot = argv[0]
width = int(argv[1]) if len(argv) > 1 else 960
samples = int(argv[2]) if len(argv) > 2 else 28

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col = sc.collection


def lin(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1,)


def spawn(dx):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "Characters/character_base.glb"))
    new = set(bpy.data.objects) - before
    arm = [o for o in new if o.type == 'ARMATURE'][0]
    meshes = {o.name.split(".")[0]: o for o in new if o.type == 'MESH'}
    root = [o for o in new if o.parent is None]
    for o in root:
        o.location.x += dx
    return arm, meshes


def recolor(mesh, hexc):
    for slot in mesh.material_slots:
        m = slot.material
        m = m.copy()
        slot.material = m
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = lin(hexc)


def rot(arm, name, axis, deg):
    pb = arm.pose.bones[name]
    bpy.context.view_layer.update()
    head = pb.head.copy()
    T = Matrix.Translation(head)
    pb.matrix = T @ Matrix.Rotation(math.radians(deg), 4, axis) @ T.inverted() @ pb.matrix
    bpy.context.view_layer.update()


POSES = {
    "tpose": [],
    "relaxed": [("LeftUpperArm", 'Y', 68), ("RightUpperArm", 'Y', -68),
                ("LeftLowerArm", 'X', -25), ("RightLowerArm", 'X', -25),
                ("LeftShoulder", 'Y', 6), ("RightShoulder", 'Y', -6)],
    "walk": [("LeftUpperArm", 'Y', 62), ("RightUpperArm", 'Y', -62),
             ("LeftUpperArm", 'X', 22), ("RightUpperArm", 'X', -26),
             ("LeftLowerArm", 'X', -35), ("RightLowerArm", 'X', -15),
             ("LeftUpperLeg", 'X', -32), ("LeftLowerLeg", 'X', 18),
             ("RightUpperLeg", 'X', 22), ("RightLowerLeg", 'X', 38),
             ("RightFoot", 'X', 15), ("Spine", 'Z', -8), ("Head", 'Z', 12)],
    "crouch": [("LeftUpperLeg", 'X', -75), ("LeftLowerLeg", 'X', 95),
               ("RightUpperLeg", 'X', -75), ("RightLowerLeg", 'X', 95),
               ("Spine", 'X', -22), ("Chest", 'X', -10), ("Head", 'X', 15),
               ("LeftUpperArm", 'Y', 40), ("RightUpperArm", 'Y', -40),
               ("LeftUpperArm", 'X', -55), ("RightUpperArm", 'X', -55),
               ("LeftLowerArm", 'X', -50), ("RightLowerArm", 'X', -50)],
}


def pose(arm, name):
    for b, axis, deg in POSES[name]:
        rot(arm, b, axis, deg)


def show(meshes, top="Char_Top_Jacket", head="Char_Hair"):
    for n, o in meshes.items():
        if n in ("Char_Top_Jacket", "Char_Top_Hoodie"):
            o.hide_render = (n != top)
        if n in ("Char_Hair", "Char_Beanie"):
            o.hide_render = (n != head)


def lift_to_floor(arm, meshes):
    """crouch: drop the whole character so the feet stay near the floor"""
    pass


# ---- characters --------------------------------------------------------------
if shot == "tpose":
    a, m = spawn(0)
    show(m)
    chars = [(a, m)]
    cam_loc, cam_tgt, lens = (0, -4.4, 0.95), (0, 0, 0.88), 35
    span = 1.0
elif shot == "closeup":
    a, m = spawn(0)
    show(m)
    chars = [(a, m)]
    cam_loc, cam_tgt, lens = (0.45, -2.5, 1.22), (0.0, 0, 1.18), 50
elif shot == "posetest":
    chars = []
    for dx, pn, top, hd in ((-2.2, "tpose", "Char_Top_Jacket", "Char_Hair"),
                            (-0.75, "relaxed", "Char_Top_Hoodie", "Char_Hair"),
                            (0.75, "walk", "Char_Top_Jacket", "Char_Beanie"),
                            (2.2, "crouch", "Char_Top_Hoodie", "Char_Beanie")):
        a, m = spawn(dx)
        show(m, top, hd)
        pose(a, pn)
        chars.append((a, m))
    cam_loc, cam_tgt, lens = (0.3, -7.0, 1.0), (0.3, 0, 0.85), 35
else:   # lineup: four players, relaxed pose, different colours / silhouettes
    chars = []
    PAL = [("#A8781F", "#343A40", "#C9C6BD"), ("#3E6A8A", "#2B2F33", "#B7791F"),
           ("#5C6B3A", "#3A3F44", "#C9C6BD"), ("#C9C6BD", "#4A4E52", "#8C2B2B")]
    VAR = [("Char_Top_Jacket", "Char_Hair"), ("Char_Top_Hoodie", "Char_Beanie"),
           ("Char_Top_Jacket", "Char_Beanie"), ("Char_Top_Hoodie", "Char_Hair")]
    for i, dx in enumerate((-2.25, -0.75, 0.75, 2.25)):
        a, m = spawn(dx)
        show(m, *VAR[i])
        top, pants, acc = PAL[i]
        recolor(m["Char_Top_Jacket"], top)
        recolor(m["Char_Top_Hoodie"], top)
        recolor(m["Char_Trousers"], pants)
        recolor(m["Char_Beanie"], acc)
        pose(a, "relaxed")
        chars.append((a, m))
    cam_loc, cam_tgt, lens = (0.0, -7.0, 0.95), (0.0, 0, 0.85), 35

# ---- stage -------------------------------------------------------------------
def pmat(name, hexc, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(hexc)
    b.inputs["Roughness"].default_value = rough
    return m


floor = bpy.data.meshes.new("floor")
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * 14, v.co.y * 10 + 3, v.co.z * 0.2 - 0.1))
bm.to_mesh(floor)
bm.free()
floor.materials.append(pmat("pv_floor", "#596168", 0.75))
col.objects.link(bpy.data.objects.new("floor", floor))
wall = bpy.data.meshes.new("wall")
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * 14, v.co.y * 0.3 + 3.2, v.co.z * 4 + 2))
bm.to_mesh(wall)
bm.free()
wall.materials.append(pmat("pv_wall", "#7B8085", 0.9))
col.objects.link(bpy.data.objects.new("wall", wall))


def area(name, loc, size, power, color, rot_x=0, rot_z=0):
    d = bpy.data.lights.new(name, 'AREA')
    d.shape = 'RECTANGLE'
    d.size, d.size_y = size
    d.energy = power
    d.color = color
    o = bpy.data.objects.new(name, d)
    o.location = loc
    o.rotation_euler = (math.radians(rot_x), 0, math.radians(rot_z))
    col.objects.link(o)


area("key", (-2.5, -4.0, 3.2), (2.5, 2.5), 700, (1.0, 0.94, 0.86), rot_x=55, rot_z=-30)
area("fill", (3.0, -4.0, 1.8), (3.0, 3.0), 260, (0.78, 0.86, 1.0), rot_x=70, rot_z=35)
area("rim", (0, 2.0, 3.0), (4.0, 1.0), 400, (0.85, 0.92, 1.0), rot_x=-120)

cd = bpy.data.cameras.new("cam")
cd.lens = lens
co = bpy.data.objects.new("cam", cd)
co.location = cam_loc
col.objects.link(co)
d = Vector(cam_tgt) - Vector(cam_loc)
co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
sc.camera = co

sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = samples
sc.cycles.use_adaptive_sampling = True
sc.cycles.max_bounces = 4
sc.cycles.use_denoising = False
sc.render.resolution_x = width
sc.render.resolution_y = int(width * 9 / 16)
sc.view_settings.exposure = 0.0
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.10, 0.11, 0.13, 1)
sc.world = w
sc.render.image_settings.file_format = 'PNG'
sc.render.filepath = os.path.join(ROOT, "previews", "preview_char_%s.png" % shot)
bpy.ops.render.render(write_still=True)
print("RENDERED", sc.render.filepath)
