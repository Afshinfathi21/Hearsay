"""Build Monitors/door_monitor.glb  (run: blender -b --python build_monitor.py)

Monitor root space: origin = centre of the BACK plate, front faces -Y
(-> +Z in Godot). Housing 1.20 (X) x 0.18 (depth) x 0.45 (Z).
Mount it on the wall face above a door at: x = 0, z = 2.625 (centre),
y = -0.15 (front wall face; use +0.15 and a 180 deg Y rotation for the back).

Dynamic numbers: two 7-segment digits made of real meshes (Mon_Seg_*), no
baked texture. Toggle segments in Godot (see godot/door_monitor.gd).
The Mon_Screen quad also has clean 0-1 UVs if you prefer a SubViewport/UI.
"""
import os
import sys
import bpy
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *  # noqa

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets/the_exit_room/monitors")

reset_scene()
col = new_collection("Monitors")
STEEL = get_material("M_Steel_Dark_Brushed")
PAINT = get_material("M_Paint_Worn")
SCREEN = get_material("M_Emissive_Screen")
DIGIT = get_material("M_Digit_Amber")
AMBER = get_material("M_Emissive_Light_Amber")
WHITE = get_material("M_Emissive_Light_White")

FRONT = -0.18          # front face of the bezel
SCREEN_Y = -0.151      # screen glass plane (recessed 0.029 behind the bezel)
SCR_HX, SCR_HZ = 0.36, 0.17

root = None   # no root empty: Godot already wraps the file in a root node

# ---------------------------------------------------------------------------
# Housing: slots 0 steel, 1 worn paint
# ---------------------------------------------------------------------------
bm = bmesh.new()
add_box(bm, (0, -0.075, 0), (1.20, 0.15, 0.45), 0, bevel=0.008)          # body
add_rect_ring(bm, (0.60, 0.225), (SCR_HX, SCR_HZ), -0.15, FRONT, 0)      # bezel
for sx in (-1, 1):                                                          # bolts
    for sz in (-1, 1):
        add_cyl(bm, (sx * 0.565, FRONT - 0.003, sz * 0.1975), 0.011, 0.006,
                'Y', 0, 8)
y_paint = FRONT - 0.0015
for x in (-0.10, 0.0, 0.10):                                               # top ticks
    add_box(bm, (x, y_paint, 0.1975), (0.03, 0.003, 0.012), 1)
add_box(bm, (0.0, y_paint, -0.1975), (0.50, 0.003, 0.010), 1)              # bottom rule
add_box(bm, (-0.48, y_paint, -0.09), (0.09, 0.003, 0.012), 1)              # lamp label
add_box(bm, (-0.48, y_paint, -0.13), (0.03, 0.003, 0.03), 1)
add_box(bm, (0.42, y_paint, 0.0), (0.006, 0.003, 0.30), 1)                 # pip divider
housing = finalize("Mon_Housing", bm, col, [STEEL, PAINT], parent=root)

# ---------------------------------------------------------------------------
# Screen glass (own material, own 0-1 UVs)
# ---------------------------------------------------------------------------
bm = bmesh.new()
v = [bm.verts.new(p) for p in ((-SCR_HX, SCREEN_Y, -SCR_HZ), (SCR_HX, SCREEN_Y, -SCR_HZ),
                               (SCR_HX, SCREEN_Y, SCR_HZ), (-SCR_HX, SCREEN_Y, SCR_HZ))]
f = bm.faces.new(v)
uvl = bm.loops.layers.uv.verify()
for l, (u, w) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
    l[uvl].uv = (u, w)
f.normal_update()
assert f.normal.y < 0, "screen must face -Y"
finalize("Mon_Screen", bm, col, [SCREEN], parent=root, recalc=False, uv=None)

# ---------------------------------------------------------------------------
# 7-segment digits: each segment is its own mesh so Godot can switch it
# ---------------------------------------------------------------------------
W, H, T, G = 0.18, 0.28, 0.032, 0.003
SEG_Y0, SEG_Y1 = SCREEN_Y - 0.002, SCREEN_Y - 0.008   # proud of the glass
DIGIT_X = {"Tens": -0.125, "Units": 0.125}


def h_poly(cx, cz):
    a = W / 2 - T / 2 - G
    return [(cx - a, cz), (cx - a + T / 2, cz + T / 2), (cx + a - T / 2, cz + T / 2),
            (cx + a, cz), (cx + a - T / 2, cz - T / 2), (cx - a + T / 2, cz - T / 2)]


def v_poly(cx, cz):
    b = H / 4 - G
    return [(cx, cz + b), (cx + T / 2, cz + b - T / 2), (cx + T / 2, cz - b + T / 2),
            (cx, cz - b), (cx - T / 2, cz - b + T / 2), (cx - T / 2, cz + b - T / 2)]


for dname, dx in DIGIT_X.items():
    d_empty = new_empty("Mon_Digit_" + dname, col, parent=root, location=(dx, 0, 0))
    xs = W / 2 - T / 2
    segs = {
        "A": h_poly(dx, H / 2 - T / 2),
        "G": h_poly(dx, 0.0),
        "D": h_poly(dx, -H / 2 + T / 2),
        "B": v_poly(dx + xs, H / 4),
        "C": v_poly(dx + xs, -H / 4),
        "F": v_poly(dx - xs, H / 4),
        "E": v_poly(dx - xs, -H / 4),
    }
    for letter in "ABCDEFG":
        pts = segs[letter]
        cx = sum(p[0] for p in pts) / 6
        cz = sum(p[1] for p in pts) / 6
        b = bmesh.new()
        add_prism(b, pts, SEG_Y0, SEG_Y1, 0)
        finalize("Mon_Seg_%s_%s" % (dname, letter), b, col, [DIGIT],
                 origin=(cx, (SEG_Y0 + SEG_Y1) / 2, cz), parent=d_empty)

# ---------------------------------------------------------------------------
# Indicator lights: status lamp (left), four capacity pips (right)
# ---------------------------------------------------------------------------
b = bmesh.new()
add_box(b, (-0.48, FRONT - 0.003, 0.05), (0.09, 0.006, 0.14), 0)
finalize("Mon_Status_Lamp", b, col, [AMBER], origin=(-0.48, FRONT - 0.003, 0.05),
         parent=root)
for i, z in enumerate((0.12, 0.04, -0.04, -0.12), start=1):
    b = bmesh.new()
    add_box(b, (0.48, FRONT - 0.003, z), (0.04, 0.006, 0.04), 0)
    finalize("Mon_Pip_%d" % i, b, col, [WHITE], origin=(0.48, FRONT - 0.003, z),
             parent=root)

# ---------------------------------------------------------------------------
os.makedirs(OUT_DIR, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "door_monitor.blend"))
roots = [o for o in col.objects if o.parent is None]
export_glb(roots, os.path.join(OUT_DIR, "door_monitor.glb"))
total, rows = report(roots)
print("=== door_monitor ===")
for r in rows:
    if r[0].startswith("Mon_Seg") and not r[0].endswith("_A"):
        continue
    print(r)
print("TOTAL TRIS:", total)
