"""Two-room alignment test built ONLY from the exported .glb files.
Run: blender -b --python build_alignment_test.py -- check
     blender -b --python build_alignment_test.py -- interior|overview [width] [samples]

Layout (cell pitch 4 m, cells A and B side by side, doorway on the shared edge):

    y=4  P--W--P--W--P
         |  A  D  B  |      P = Env_Wall_Post, W = Env_Wall_Straight,
    y=0  P--W--P--W--P      D = Env_Wall_Doorway + door + 2 monitors
        x=0   x=4   x=8
"""
import os
import sys
import math
import itertools
import bpy
from mathutils import Vector, Matrix

ROOT = "/home/claude/asset_pack"
argv = sys.argv[sys.argv.index("--") + 1:]
mode = argv[0]
width = int(argv[1]) if len(argv) > 1 else 960
samples = int(argv[2]) if len(argv) > 2 else 32

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
col = sc.collection
instances = []          # (module, empty, [visual objects])


def place(module, path, loc, rot_z=0.0, tag=None):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, path))
    new = set(bpy.data.objects) - before
    e = bpy.data.objects.new("%s@%s" % (module, tag or ""), None)
    col.objects.link(e)
    e.location = loc
    e.rotation_euler = (0, 0, math.radians(rot_z))
    for o in new:
        if o.parent is None:
            o.parent = e
    bpy.context.view_layer.update()
    vis = [o for o in new if o.type == 'MESH' and "colonly" not in o.name]
    instances.append((module, e, vis))
    return e, new


# ---- layout ------------------------------------------------------------------
for c in ((2, 2), (6, 2)):
    place("floor", "Environment/env_floor_4m.glb", (c[0], c[1], 0))
    place("ceiling", "Environment/env_ceiling_4m.glb", (c[0], c[1], 3.0))
    place("light", "Environment/env_light_ceiling.glb", (c[0], c[1], 3.0))
for px in (0, 4, 8):
    for py in (0, 4):
        place("post", "Environment/env_wall_post.glb", (px, py, 0))
for wx in (2, 6):
    for wy in (0, 4):
        place("wall", "Environment/env_wall_straight.glb", (wx, wy, 0))
place("wall", "Environment/env_wall_straight.glb", (0, 2, 0), 90)
place("wall", "Environment/env_wall_straight.glb", (8, 2, 0), 90)
place("doorway", "Environment/env_wall_doorway.glb", (4, 2, 0), 90)
door_e, door_objs = place("door", "Doors/door_standard.glb", (4, 2, 0), 90)
# monitors: front (+X side, room B) and rear (room A), above the door
mf, mf_objs = place("monitor", "Monitors/door_monitor.glb", (4.15, 2, 2.625), 90, "front")
mr, mr_objs = place("monitor", "Monitors/door_monitor.glb", (3.85, 2, 2.625), -90, "rear")
# optional props on room A walls
place("prop", "Environment/env_wall_panel.glb", (0.15, 1.2, 1.5), 90, "panel")
place("prop", "Environment/env_grille_wall.glb", (2.0, 3.85, 0.5), 0, "grille")

# ---- numeric alignment checks -----------------------------------------------
EPS = 1e-4


def aabb(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for v in o.bound_box:
            w = o.matrix_world @ Vector(v)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


results = []


def check(name, ok, detail=""):
    results.append((name, ok, detail))


struct = [(m, aabb(v)) for m, e, v in instances
          if m in ("floor", "ceiling", "wall", "post", "doorway")]

# 1. floors touch and sit at z=0; ceilings touch and sit at z=3
fl = sorted([b for m, b in struct if m == "floor"], key=lambda b: b[0].x)
ce = sorted([b for m, b in struct if m == "ceiling"], key=lambda b: b[0].x)
check("floors share an edge (x=4)", abs(fl[0][1].x - fl[1][0].x) < EPS)
check("floor tops at z=0", all(abs(b[1].z) < EPS for b in fl))
check("ceilings share an edge (x=4)", abs(ce[0][1].x - ce[1][0].x) < EPS)
check("ceiling undersides at z=3.0", all(abs(b[0].z - 3.0) < EPS for b in ce))

# 2. every wall line is continuous from post to post with no gaps
def line_pieces(axis, value):
    """pieces whose footprint straddles grid line axis=value (axis 0=x-const, 1=y-const)"""
    out = []
    for m, (lo, hi) in struct:
        if m in ("wall", "post", "doorway") and lo[axis] - EPS <= value <= hi[axis] + EPS \
                and abs(lo.z) < EPS and abs(hi.z - 3.0) < EPS:
            out.append((lo[1 - axis], hi[1 - axis]))
    return sorted(out)


for axis, value, label in [(1, 0, "y=0"), (1, 4, "y=4"), (0, 0, "x=0"), (0, 4, "x=4"), (0, 8, "x=8")]:
    pcs = line_pieces(axis, value)
    expect_hi = 8.15 if axis == 1 else 4.15
    gaps = [round(b[0] - a[1], 5) for a, b in zip(pcs, pcs[1:])]
    ok = pcs and abs(pcs[0][0] + 0.15) < EPS and abs(pcs[-1][1] - expect_hi) < EPS \
        and all(abs(g) < EPS for g in gaps)
    check("wall line %s continuous (%d pieces, gaps=%s)" % (label, len(pcs), gaps), bool(ok))

# 3. no volumetric overlap between structural modules
bad = []
for (m1, (a0, a1)), (m2, (b0, b1)) in itertools.combinations(struct, 2):
    ov = [min(a1[i], b1[i]) - max(a0[i], b0[i]) for i in range(3)]
    if all(x > EPS for x in ov):
        bad.append((m1, m2, [round(x, 4) for x in ov]))
check("no overlapping structural modules (%d pairs tested)" % (len(struct) * (len(struct) - 1) // 2),
      not bad, str(bad[:3]))

# 4. door frame sits flush in the doorway wall; monitor clears the frame trim
fr = [o for o in door_objs if o.name == "Door_Frame"][0]
flo, fhi = aabb([fr])
check("door frame centred in doorway (x 3.835..4.165, y 1.14..2.86)",
      abs(flo.x - 3.835) < EPS and abs(fhi.x - 4.165) < EPS and abs(flo.y - 1.14) < EPS
      and abs(fhi.y - 2.86) < EPS, "%s %s" % (tuple(round(v, 3) for v in flo), tuple(round(v, 3) for v in fhi)))
mlo, mhi = aabb([o for o in mf_objs if o.type == 'MESH'])
check("monitor bottom (%.3f) clears frame trim top (%.3f)" % (mlo.z, fhi.z), mlo.z - fhi.z > 0.02)
check("monitor sits on wall face (back plane x=%.3f)" % mlo.x, abs(mlo.x - 4.15) < 0.01)

# 5. the cutout measured in the doorway mesh equals the frame's collision box
dw = [v for m, e, v in instances if m == "doorway"][0][0]
# world coordinates; the doorway is rotated 90 deg, so "across the opening" is world Y about y=2
verts = [dw.matrix_world @ v.co for v in dw.data.vertices]
cut_x = min(abs(v.y - 2.0) for v in verts if 0.1 < v.z < 2.2 and abs(v.y - 2.0) < 1.0)  # jamb-side faces
cut_z = min(v.z for v in verts if abs(v.y - 2.0) < 0.79 and v.z > 2.0)                   # header underside
col_obj = [o for o in door_objs if o.name.startswith("Door_Frame_Col")][0]
clo, chi = aabb([col_obj])
frame_w, frame_h = chi.y - clo.y, chi.z - clo.z    # door is rotated 90 deg about Z
check("doorway cutout %.3f x %.3f m == frame body %.3f x %.3f m (jamb bottom to header)" %
      (2 * cut_x, cut_z, frame_w, frame_h),
      abs(2 * cut_x - frame_w) < EPS and abs(cut_z - frame_h) < EPS)

print("=== ALIGNMENT CHECKS ===")
for n, ok, d in results:
    print(("PASS " if ok else "FAIL ") + n + (("  " + d) if d and not ok else ""))
print("RESULT: %d/%d passed" % (sum(1 for r in results if r[1]), len(results)))

if mode == "check":
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "Environment/alignment_test.blend"))
    sys.exit(0)

# ---- render setup --------------------------------------------------------------
def lin(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1,)


def pmat(name, hexc, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(hexc)
    b.inputs["Roughness"].default_value = rough
    return m


for o in bpy.data.objects:
    if "colonly" in o.name:
        o.hide_render = True
        o.hide_viewport = True

BOOST = {"M_Digit_Amber": 9, "M_Emissive_Light_Amber": 7, "M_Emissive_Light_White": 9,
         "M_Emissive_Screen": 0.8, "M_Emissive_Light_Red": 9}
for m in bpy.data.materials:
    k = m.name.split(".")[0]
    if k in BOOST and m.use_nodes and m.node_tree.nodes.get("Principled BSDF"):
        m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = BOOST[k]

if mode == "textured":
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    import blender_pbr as pb
    _, _ = place("prop", "Props/prop_number_plate.glb", (4.15, 3.25, 1.65), 90, "plate")
    _, _ = place("prop", "Props/prop_emergency_light.glb", (6.3, 0.15, 2.45), 180, "emergency")
    _, _ = place("prop", "Props/prop_speaker_wall.glb", (5.2, 3.85, 2.6), 0, "speaker")
    _, cam_objs = place("prop", "Props/prop_camera_wall.glb", (7.0, 3.85, 2.6), 0, "camera")
    _, _ = place("prop", "Props/prop_electrical_panel.glb", (5.3, 0.15, 1.5), 180, "panel")
    _, _ = place("prop", "Props/prop_ceiling_vent.glb", (6.0, 2.9, 3.0), 0, "vent")
    _, _ = place("prop", "Props/prop_floor_marking_hazard.glb", (4.65, 2.0, 0), 90, "hazard")
    _, _ = place("prop", "Props/prop_floor_marking_arrow.glb", (5.7, 2.0, 0), -90, "arrow")
    _, _ = place("prop", "Props/prop_floor_marking_line.glb", (6.6, 2.0, 0), 0, "line")
    for o in cam_objs:
        if o.name.startswith("Prop_Camera_Head"):
            o.rotation_mode = 'XYZ'
            o.rotation_euler = (0, 0, math.radians(-35))
    for o in bpy.data.objects:
        if "colonly" in o.name:
            o.hide_render = True
            o.hide_viewport = True
    pb.apply_library(bpy.data.objects)

# monitor shows "03" with three pips; unlit segments/pips go dark
OFF = pmat("pv_off", "#1F1208", 0.5)
PIP_OFF = pmat("pv_pip_off", "#15181A", 0.5)
SEG = {"0": "ABCDEF", "3": "ABGCD"}
for objs in (mf_objs, mr_objs):
    named = {o.name.split(".")[0]: o for o in objs}
    for digit, ch in zip(("Tens", "Units"), "03"):
        for letter in "ABCDEFG":
            if letter not in SEG[ch]:
                named["Mon_Seg_%s_%s" % (digit, letter)].data.materials[0] = OFF
    named["Mon_Pip_4"].data.materials[0] = PIP_OFF

for n in ("Door_Panel", "Door_Bolt_A", "Door_Bolt_B"):
    for o in door_objs:
        if o.name.split(".")[0] == n:
            o.animation_data_clear()
            if mode == "overview":
                if n == "Door_Panel":
                    o.rotation_mode = 'XYZ'
                    o.rotation_euler = (0, 0, math.radians(100))
                else:
                    o.location.x -= 0.05

if mode == "overview":
    for m, e, vis in instances:
        if m in ("ceiling", "light"):
            for o in vis:
                o.hide_render = True


def area(name, loc, size, power, color):
    d = bpy.data.lights.new(name, 'AREA')
    d.shape = 'RECTANGLE'
    d.size, d.size_y = size
    d.energy = power
    d.color = color
    o = bpy.data.objects.new(name, d)
    o.location = loc
    col.objects.link(o)


for cx in (2, 6):
    area("fix%d" % cx, (cx, 2, 2.93), (0.8, 0.18), 220 if mode in ("interior", "textured") else 90, (0.88, 0.93, 1.0))
pl = bpy.data.lights.new("glow", 'POINT')
pl.energy = 14
pl.color = (1.0, 0.55, 0.12)
pl.shadow_soft_size = 0.2
po = bpy.data.objects.new("glow", pl)
po.location = (4.7, 2, 2.5)
col.objects.link(po)

if mode in ("interior", "textured"):
    # scale figure (1.75 m) in room B
    dm = pmat("pv_dummy", "#3A3F44", 0.9)
    import bmesh as _bm
    for nm, (x0, x1, y0, y1, z0, z1) in {"body": (6.0, 6.4, 2.6, 3.0, 0, 1.5),
                                         "head": (6.08, 6.32, 2.68, 2.92, 1.52, 1.75)}.items():
        me = bpy.data.meshes.new(nm)
        bm = _bm.new()
        _bm.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector(((v.co.x + .5) * (x1 - x0) + x0, (v.co.y + .5) * (y1 - y0) + y0,
                           (v.co.z + .5) * (z1 - z0) + z0))
        bm.to_mesh(me)
        bm.free()
        me.materials.append(dm)
        ob = bpy.data.objects.new(nm, me)
        col.objects.link(ob)

cd = bpy.data.cameras.new("cam")
co = bpy.data.objects.new("cam", cd)
col.objects.link(co)
if mode in ("interior", "textured"):
    cd.lens = 20
    co.location = (7.7, 1.0, 1.55)
    tgt = Vector((4.2, 2.1, 1.45))
else:
    cd.type = 'ORTHO'
    cd.ortho_scale = 9.6
    co.location = (4.0, 2.0, 12.0)
    tgt = Vector((4.0, 2.0, 0.0))
d = tgt - co.location
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
sc.view_settings.exposure = 0.4 if mode in ("interior", "textured") else -0.3
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = ((0.11, 0.12, 0.14, 1) if mode in ("interior", "textured") else (0.30, 0.32, 0.36, 1))
sc.world = w
sc.render.image_settings.file_format = 'PNG'
sc.render.filepath = os.path.join(ROOT, "previews", "preview_rooms_%s.png" % mode)
bpy.ops.render.render(write_still=True)
print("RENDERED", sc.render.filepath)
