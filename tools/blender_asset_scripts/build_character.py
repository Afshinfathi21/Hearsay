"""Build Characters/character_base.glb  (run: blender -b --python build_character.py)

A neutral, 1.75 m human in a T-pose, rigged with Godot's SkeletonProfileHumanoid
bone names, plus clothing/headwear variants that share the same skeleton.

Authoring space: Blender Z-up, character faces -Y (-> +Z in Godot), the
character's LEFT is +X. Everything is built from "lofts": rings of points
swept along a limb, so clothing is just the body profile plus an offset.
"""
import os
import sys
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *  # noqa

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets/common/characters")
N = 20                      # segments around each ring

reset_scene()
col = new_collection("Characters")
M = {k: get_material(k) for k in (
    "M_Char_Skin", "M_Char_Cloth_Top", "M_Char_Cloth_Pants", "M_Char_Cloth_Accent",
    "M_Char_Boots", "M_Char_Hair", "M_Char_Eye")}
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))

# ============================================================================
# Skeleton (T-pose). Names follow Godot's SkeletonProfileHumanoid.
# ============================================================================
BONES = []          # (name, head, tail, parent)


def bone(name, head, tail, parent):
    BONES.append((name, Vector(head), Vector(tail), parent))


bone("Root", (0, 0, 0), (0, 0, 0.12), None)
bone("Hips", (0, 0, 0.93), (0, 0, 1.00), "Root")
bone("Spine", (0, 0, 1.00), (0, 0, 1.14), "Hips")
bone("Chest", (0, 0, 1.14), (0, 0, 1.28), "Spine")
bone("UpperChest", (0, 0, 1.28), (0, 0, 1.40), "Chest")
bone("Neck", (0, 0, 1.40), (0, 0, 1.50), "UpperChest")
bone("Head", (0, 0, 1.50), (0, 0, 1.75), "Neck")
for side, s in (("Left", 1), ("Right", -1)):
    bone(side + "Shoulder", (s * 0.03, 0, 1.40), (s * 0.18, 0, 1.41), "UpperChest")
    bone(side + "UpperArm", (s * 0.18, 0, 1.41), (s * 0.46, 0, 1.41), side + "Shoulder")
    bone(side + "LowerArm", (s * 0.46, 0, 1.41), (s * 0.705, 0, 1.41), side + "UpperArm")
    bone(side + "Hand", (s * 0.705, 0, 1.41), (s * 0.88, 0, 1.41), side + "LowerArm")
    bone(side + "UpperLeg", (s * 0.09, 0, 0.92), (s * 0.09, 0, 0.50), "Hips")
    bone(side + "LowerLeg", (s * 0.09, 0, 0.50), (s * 0.09, 0, 0.09), side + "UpperLeg")
    bone(side + "Foot", (s * 0.09, 0, 0.09), (s * 0.09, -0.13, 0.035), side + "LowerLeg")
    bone(side + "Toes", (s * 0.09, -0.13, 0.035), (s * 0.09, -0.22, 0.025), side + "Foot")
BONE = {b[0]: b for b in BONES}

arm_data = bpy.data.armatures.new("Skeleton")
arm_obj = bpy.data.objects.new("Skeleton", arm_data)
col.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode='EDIT')
for name, head, tail, parent in BONES:
    eb = arm_data.edit_bones.new(name)
    eb.head, eb.tail = head, tail
    if parent:
        eb.parent = arm_data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
arm_obj.show_in_front = True


# ============================================================================
# Loft helpers
# ============================================================================
def ring(c, u, v, ru, rv, p=2.0, mulf=None):
    pts = []
    for i in range(N):
        th = 2 * math.pi * i / N
        ct, st = math.cos(th), math.sin(th)
        x = math.copysign(abs(ct) ** (2 / p), ct)
        y = math.copysign(abs(st) ** (2 / p), st)
        m = mulf(th) if mulf else 1.0
        pts.append(c + u * (ru * x * m) + v * (rv * y * m))
    return pts


def loft(bm, rings, mat=0, cap0=True, cap1=True):
    """Sweep rings into a tube. Winding is decided from the geometry (normals
    must point away from the axis), so lofts built top-down or on the -X side
    still come out outward-facing without relying on recalc."""
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    side = []
    for a, b in zip(vs, vs[1:]):
        for i in range(N):
            j = (i + 1) % N
            side.append(bm.faces.new((a[i], a[j], b[j], b[i])))
    cents = [sum((v.co for v in r), Vector()) / N for r in vs]
    score = 0.0
    for k, f in enumerate(side):
        f.normal_update()
        score += f.normal.dot(f.calc_center_median() - cents[k // N])
    caps = []
    if cap0:
        caps.append((bm.faces.new(vs[0]), cents[0] - cents[1]))
    if cap1:
        caps.append((bm.faces.new(vs[-1]), cents[-1] - cents[-2]))
    for f, out in caps:
        f.normal_update()
        if f.normal.dot(out) < 0:
            bmesh.ops.reverse_faces(bm, faces=[f])
    if score < 0:
        bmesh.ops.reverse_faces(bm, faces=side)
    for f in side + [c[0] for c in caps]:
        f.material_index = mat


def folds(centres, amp=0.05, width=0.035, k=3):
    """radial multiplier: soft creases around given axis positions"""
    def f(t, th):
        a = 0.0
        for c in centres:
            a += amp * math.exp(-((t - c) / width) ** 2) * math.sin(k * th + c * 23.0)
        return 1.0 + a + 0.008 * math.sin(5 * th + t * 31.0)
    return f


def vloft(bm, tab, cx=0.0, grow=0.0, p=2.0, mat=0, fold=None, cap0=True, cap1=True):
    """tab rows: (z, rx, ry, dy). Rings in XY planes, swept along Z."""
    rings = []
    for z, rx, ry, dy in tab:
        mf = (lambda th, z=z: fold(z, th)) if fold else None
        rings.append(ring(Vector((cx, dy, z)), X, Y, rx + grow, ry + grow, p, mf))
    loft(bm, rings, mat, cap0, cap1)


def aloft(bm, side, tab, grow=0.0, mat=0, fold=None, cap0=True, cap1=True, cz=1.41):
    """tab rows: (x, ry, rz[, dy]); arm swept along +-X (side=+1 left)."""
    rings = []
    for row in tab:
        x, ry, rz = row[:3]
        dy = row[3] if len(row) > 3 else 0.0
        mf = (lambda th, x=x: fold(x, th)) if fold else None
        rings.append(ring(Vector((side * x, dy, cz)), Y, Z, ry + grow, rz + grow, 2.0, mf))
    loft(bm, rings, mat, cap0, cap1)


def tube(bm, pts, radii, mat=0, cap0=True, cap1=True):
    rings = []
    for i, p in enumerate(pts):
        a = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        t = a.normalized()
        ref = Z if abs(t.dot(Z)) < 0.9 else X
        u = t.cross(ref).normalized()
        v = t.cross(u).normalized()
        r = radii[i]
        rings.append(ring(Vector(p), u, v, r, r))
    loft(bm, rings, mat, cap0, cap1)


def ellipsoid(bm, c, rx, ry, rz, mat=0):
    tmp = bmesh.new()
    bmesh.ops.create_uvsphere(tmp, u_segments=10, v_segments=7, radius=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * rx + c[0], v.co.y * ry + c[1], v.co.z * rz + c[2]))
    for f in tmp.faces:
        f.material_index = mat
    me = bpy.data.meshes.new("_t")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


# ---- head profile (z, rx, ry, dy) used by head, hair, beanie ---------------
HEAD = [(1.515, .028, .040, -.030), (1.535, .052, .062, -.028), (1.56, .068, .080, -.020),
        (1.60, .077, .092, -.012), (1.64, .080, .098, -.008), (1.68, .078, .099, -.002),
        (1.715, .068, .090, .004), (1.735, .048, .068, .006), (1.752, .018, .030, .006)]


def head_at(z):
    z = min(max(z, HEAD[0][0]), HEAD[-1][0])
    for a, b in zip(HEAD, HEAD[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / (b[0] - a[0])
            return tuple(a[i] + (b[i] - a[i]) * t for i in (1, 2, 3))
    return HEAD[-1][1:]


def head_shell(bm, zb_fn, z_top, scale, grow, mat, n_t=6, cap_top=True):
    """Dome over the head whose lower edge height depends on the angle
    (hairline / beanie edge)."""
    rings = []
    for k in range(n_t):
        t = (k / (n_t - 1)) ** 0.8
        pts = []
        for i in range(N):
            th = 2 * math.pi * i / N
            zb = zb_fn(th)
            z = zb + t * (z_top - zb)
            rx, ry, dy = head_at(z)
            pts.append(Vector(((rx * scale + grow) * math.cos(th),
                               dy + (ry * scale + grow) * math.sin(th), z)))
        rings.append(pts)
    loft(bm, rings, mat, cap0=False, cap1=cap_top)


# ============================================================================
# Meshes (each is its own object so variants can be toggled / recoloured)
# ============================================================================
parts = []        # (obj, bone_candidates, gates)


def make(name, bm, mats):
    o = finalize(name, bm, col, mats, parent=None, recalc=False)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


# ---- body (visible skin only): head, neck, hands -----------------------------
bm = bmesh.new()
vloft(bm, HEAD, mat=0)
tube(bm, [Vector((0, 0.004, 1.395)), Vector((0, 0.004, 1.47)), Vector((0, 0.0, 1.56))],
     [0.052, 0.049, 0.047], 0, True, False)
tube(bm, [Vector((0, -0.088, 1.640)), Vector((0, -0.110, 1.606)), Vector((0, -0.119, 1.598))],
     [0.015, 0.011, 0.007], 0)                                  # nose
tube(bm, [Vector((-0.060, -0.084, 1.676)), Vector((0, -0.092, 1.678)), Vector((0.060, -0.084, 1.676))],
     [0.009, 0.010, 0.009], 0)                                  # brow
for s in (-1, 1):
    tube(bm, [Vector((s * 0.077, 0.012, 1.655)), Vector((s * 0.081, 0.012, 1.625)),
              Vector((s * 0.078, 0.012, 1.600))], [0.013, 0.015, 0.011], 0)   # ears
HAND = [(0.700, .030, .026), (0.735, .041, .019), (0.800, .046, .016),
        (0.850, .044, .015), (0.882, .030, .011), (0.894, .012, .008)]
for s in (1, -1):
    aloft(bm, s, HAND, mat=0)
    A = Vector((s * 0.765, -0.036, 1.405))
    tube(bm, [A, A + Vector((s * 0.03, -0.045, -0.002)), A + Vector((s * 0.06, -0.075, -0.004))],
         [0.015, 0.012, 0.009], 0)                              # thumb
body = make("Char_Body", bm, [M["M_Char_Skin"]])
body["parts"] = "head neck hands"
parts.append((body, ["UpperChest", "Neck", "Head", "LeftLowerArm", "RightLowerArm",
                     "LeftHand", "RightHand"], "body"))

bm = bmesh.new()
for s in (-1, 1):
    ellipsoid(bm, (s * 0.032, -0.0905, 1.655), 0.0105, 0.0075, 0.0095, 0)
eyes = make("Char_Eyes", bm, [M["M_Char_Eye"]])
parts.append((eyes, ["Head"], "rigid"))

# ---- clothing profiles -------------------------------------------------------
TORSO = [(0.84, .182, .106, 0), (0.90, .192, .110, 0), (0.97, .186, .107, 0),
         (1.04, .152, .097, 0), (1.12, .157, .099, -.003), (1.20, .170, .106, -.007),
         (1.28, .183, .112, -.010), (1.35, .190, .108, -.006), (1.41, .170, .094, 0),
         (1.445, .098, .075, 0), (1.470, .066, .066, 0)]
SLEEVE = [(0.10, .066, .068), (0.17, .071, .073), (0.23, .062, .064), (0.31, .055, .057),
          (0.39, .052, .054), (0.43, .051, .052), (0.46, .050, .050), (0.49, .051, .051),
          (0.56, .052, .052), (0.64, .045, .046), (0.70, .044, .044), (0.718, .044, .044)]
LEG = [(0.88, .088, .096, 0), (0.80, .090, .095, 0), (0.70, .080, .086, .002),
       (0.60, .068, .076, .004), (0.55, .063, .073, .005), (0.51, .062, .072, .006),
       (0.47, .062, .072, .004), (0.40, .060, .074, .010), (0.30, .052, .062, .010),
       (0.20, .048, .056, .008), (0.14, .060, .068, .006), (0.09, .068, .074, .003)]
PELVIS = [(1.045, .146, .097, 0), (1.00, .160, .102, 0), (0.94, .168, .105, 0),
          (0.88, .166, .104, 0), (0.82, .148, .098, 0)]

# ---- jacket (silhouette A: fitted, short collar) -----------------------------
bm = bmesh.new()
f_torso = folds([0.97, 1.08], amp=0.035, width=0.04, k=4)
vloft(bm, TORSO, grow=0.024, mat=0, fold=f_torso, cap0=False, cap1=False)
f_sleeve = folds([0.46, 0.64], amp=0.05, width=0.04, k=3)
for s in (1, -1):
    aloft(bm, s, SLEEVE, grow=0.0, mat=0, fold=f_sleeve, cap0=False, cap1=False)
add_box(bm, (0, -0.139, 1.17), (0.012, 0.008, 0.56), 0)                  # zip
for s in (-1, 1):
    add_box(bm, (s * 0.105, -0.112, 1.02), (0.09, 0.016, 0.06), 0)        # pocket flaps
jacket = make("Char_Top_Jacket", bm, [M["M_Char_Cloth_Top"]])
parts.append((jacket, ["Hips", "Spine", "Chest", "UpperChest", "Neck",
                       "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm",
                       "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand",
                       "LeftUpperLeg", "RightUpperLeg"], "torso"))

# ---- hoodie (silhouette B: baggier, kangaroo pocket, hood bunched at the neck)
bm = bmesh.new()
vloft(bm, TORSO, grow=0.034, mat=0, fold=folds([0.95, 1.10], 0.045, 0.05, 4),
      cap0=False, cap1=False)
CUFF = [(0.10, .068, .070), (0.18, .074, .076), (0.26, .066, .068), (0.34, .060, .062),
        (0.42, .057, .058), (0.46, .056, .056), (0.50, .057, .057), (0.58, .056, .056),
        (0.65, .050, .051), (0.690, .047, .047), (0.716, .043, .043)]
for s in (1, -1):
    aloft(bm, s, CUFF, mat=0, fold=folds([0.46, 0.62], 0.06, 0.045, 3), cap0=False, cap1=False)
add_box(bm, (0, -0.122, 0.99), (0.22, 0.016, 0.11), 0, bevel=0.004)
HOOD = [(1.395, .082, .050, .066), (1.44, .112, .068, .074), (1.49, .120, .074, .076),
        (1.55, .100, .064, .070), (1.60, .056, .038, .064)]
vloft(bm, HOOD, mat=0, fold=folds([1.47], 0.05, 0.05, 3))
for s in (-1, 1):
    tube(bm, [Vector((s * 0.030, -0.122, 1.44)), Vector((s * 0.034, -0.133, 1.34)),
              Vector((s * 0.032, -0.136, 1.25))], [0.004, 0.004, 0.005], 0)
hoodie = make("Char_Top_Hoodie", bm, [M["M_Char_Cloth_Top"]])
parts.append((hoodie, ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
                       "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm",
                       "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand",
                       "LeftUpperLeg", "RightUpperLeg"], "torso"))

# ---- trousers ---------------------------------------------------------------
bm = bmesh.new()
f_leg = folds([0.51, 0.14, 0.78], amp=0.045, width=0.035, k=3)
vloft(bm, PELVIS, grow=0.012, mat=0, fold=folds([1.0], 0.03, 0.04, 4), cap0=False, cap1=True)
for s in (-1, 1):
    vloft(bm, LEG, cx=s * 0.09, grow=0.012, mat=0, fold=f_leg, cap0=True, cap1=False)
trousers = make("Char_Trousers", bm, [M["M_Char_Cloth_Pants"]])
parts.append((trousers, ["Hips", "Spine", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg",
                         "RightLowerLeg", "LeftFoot", "RightFoot"], "legs"))

# ---- boots ------------------------------------------------------------------
bm = bmesh.new()
SHAFT = [(0.25, .059, .063, .004), (0.19, .056, .060, .005), (0.13, .052, .057, .006),
         (0.085, .050, .056, .004)]
FOOT = [(0.085, .044, .040, .054), (0.040, .048, .052, .058), (-0.020, .050, .046, .052),
        (-0.100, .052, .040, .042), (-0.170, .046, .031, .032), (-0.215, .034, .022, .025)]
for s in (-1, 1):
    vloft(bm, SHAFT, cx=s * 0.09, mat=0, cap0=False, cap1=False)
    rings = []
    for y, rx, rz, cz in FOOT:
        rings.append(ring(Vector((s * 0.09, y, cz)), X, Z, rx, rz, 3.2))
    loft(bm, rings, 0)
boots = make("Char_Boots", bm, [M["M_Char_Boots"]])
parts.append((boots, ["LowerLeg", "Foot", "Toes"], "boots"))

# ---- hair & beanie ----------------------------------------------------------
bm = bmesh.new()
head_shell(bm, lambda th: 1.655 - 0.045 * math.sin(th), 1.756, 1.04, 0.008, 0)
hair = make("Char_Hair", bm, [M["M_Char_Hair"]])
parts.append((hair, ["Head"], "rigid"))

bm = bmesh.new()
zb_beanie = lambda th: 1.665 - 0.020 * math.sin(th)
head_shell(bm, zb_beanie, 1.775, 1.07, 0.010, 0, n_t=7)
# folded cuff: a short band at the lower edge (rings at fixed offset above the edge)
rings = []
for k in range(3):
    pts = []
    for i in range(N):
        th = 2 * math.pi * i / N
        z = zb_beanie(th) - 0.004 + k * 0.018
        rx, ry, dy = head_at(z)
        sc = 1.10 if k in (0, 1) else 1.085
        pts.append(Vector((((rx * 1.04) + 0.014) * math.cos(th) * (sc / 1.10),
                           dy + ((ry * 1.04) + 0.014) * math.sin(th) * (sc / 1.10), z)))
    rings.append(pts)
loft(bm, rings, 0, cap0=False, cap1=False)
beanie = make("Char_Beanie", bm, [M["M_Char_Cloth_Accent"]])
parts.append((beanie, ["Head"], "rigid"))


# ============================================================================
# Skin weights: distance to bone segments, with per-region gates
# ============================================================================
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared)) if ab.length_squared else 0.0
    return (p - (a + ab * t)).length


def clamp01(x):
    return max(0.0, min(1.0, x))


def gate(kind, bname, p):
    z = p.z
    if kind == "body":
        if bname in ("Neck", "UpperChest"):
            return 1.0 - clamp01((z - 1.50) / 0.045) if abs(p.x) < 0.12 else 1.0
        if bname == "Head":
            return clamp01((z - 1.44) / 0.08) if abs(p.x) < 0.12 else 1.0
    if kind == "torso":
        arm = ("Shoulder" in bname) or ("Arm" in bname) or ("Hand" in bname)
        if arm and abs(p.x) < 0.20:
            return clamp01((z - 1.25) / 0.12)
        if "Leg" in bname:
            return clamp01((1.00 - z) / 0.12)
        if bname == "Head":
            return clamp01((z - 1.50) / 0.05)
    return 1.0


def skin(obj, candidates, kind):
    me = obj.data
    names = set()
    cand = []
    for c in candidates:
        if c in BONE:
            cand.append(c)
    if kind == "boots":
        cand = [c for c in BONE if any(k in c for k in ("LowerLeg", "Foot", "Toes"))]
    for c in cand:
        obj.vertex_groups.new(name=c)
    for v in me.vertices:
        p = v.co.copy()
        if kind == "rigid":
            obj.vertex_groups["Head"].add([v.index], 1.0, 'REPLACE')
            continue
        ws = []
        for c in cand:
            _, h, t, _ = BONE[c]
            if kind == "boots" and ((p.x > 0) != ("Left" in c)):
                continue
            if kind == "legs" and c in ("LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg",
                                        "RightLowerLeg", "LeftFoot", "RightFoot") \
                    and abs(p.x) > 0.02 and ((p.x > 0) != ("Left" in c)):
                continue
            d = seg_dist(p, h, t)
            w = gate(kind, c, p) / (d + 0.02) ** 3
            ws.append((w, c))
        ws.sort(reverse=True)
        ws = ws[:4]
        tot = sum(w for w, _ in ws) or 1.0
        for w, c in ws:
            if w / tot > 0.01:
                obj.vertex_groups[c].add([v.index], w / tot, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm_obj
    obj.parent = arm_obj


for obj, cand, kind in parts:
    skin(obj, cand, kind)

# ============================================================================
# Report + save + export
# ============================================================================
os.makedirs(OUT_DIR, exist_ok=True)
roots = [arm_obj] + [p[0] for p in parts]
total = 0
print("=== CHARACTER ===")
for o, _, _ in parts:
    t = tri_count(o)
    total += t
    print("%-18s tris=%5d verts=%5d" % (o.name, t, len(o.data.vertices)))
default = sum(tri_count(o) for o, _, _ in parts if o.name not in ("Char_Top_Hoodie", "Char_Beanie"))
print("TOTAL (all variants) tris:", total, " | default outfit (jacket + hair):", default)
print("bones:", len(BONES))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "character_base.blend"))
export_glb(roots, os.path.join(OUT_DIR, "character_base.glb"))
