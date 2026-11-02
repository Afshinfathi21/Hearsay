"""Build Props/*.glb  (run: blender -b --python build_props.py)

Wall props: origin = centre of the back plate (the mount point), front faces -Y
(-> +Z in Godot), so you place them with their back on a wall face.
Ceiling vent: origin = centre of the ceiling underside (like env_ceiling_4m).
Floor markings: origin = centre on the floor plane, 3 mm thick, no collision.
"""
import os
import sys
import math
import bpy
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *  # noqa

OUT = "/home/claude/asset_pack/Props"
os.makedirs(OUT, exist_ok=True)
reset_scene()
col = new_collection("Props")
STEEL = get_material("M_Steel_Dark_Brushed")
PAINT = get_material("M_Paint_Worn")
RUBBER = get_material("M_Polymer_Rubber")
GLASS = get_material("M_Glass_Frosted")
RED = get_material("M_Emissive_Light_Red")
AMBER = get_material("M_Emissive_Light_Amber")
WHITE = get_material("M_Emissive_Light_White")

props = []          # (file stem, root object)


def screws(bm, pts, y, r=0.007, mat=0):
    for x, z in pts:
        add_cyl(bm, (x, y, z), r, 0.006, 'Y', mat, 8)


# ---------------------------------------------------------------- wall camera
b = bmesh.new()
add_box(b, (0, -0.006, 0), (0.12, 0.012, 0.12), 0, bevel=0.003)
screws(b, [(sx * 0.045, sz * 0.045) for sx in (-1, 1) for sz in (-1, 1)], -0.015, 0.008)
add_box(b, (0, -0.062, 0), (0.045, 0.10, 0.045), 0, bevel=0.004)           # arm
cam = finalize("Prop_Camera_Wall", b, col, [STEEL])
PIV = (0, -0.11, 0)                                                          # swivel axis (Z)
b = bmesh.new()
add_box(b, (0, -0.20, -0.055), (0.11, 0.30, 0.10), 0, bevel=0.010)          # housing
add_box(b, (0, -0.215, 0.003), (0.13, 0.26, 0.008), 0, bevel=0.002)         # sun visor
add_cyl(b, (0, -0.354, -0.055), 0.036, 0.016, 'Y', 1, 16)                    # lens barrel
add_cyl(b, (0, -0.363, -0.055), 0.022, 0.004, 'Y', 1, 16)
add_box(b, (0.040, -0.352, -0.020), (0.012, 0.004, 0.012), 2)                # status LED
finalize("Prop_Camera_Head", b, col, [STEEL, RUBBER, RED], origin=PIV, parent=cam)
props.append(("prop_camera_wall", cam))

# ------------------------------------------------------------ emergency light
b = bmesh.new()
add_box(b, (0, -0.01, 0), (0.22, 0.02, 0.14), 0, bevel=0.004)
screws(b, [(sx * 0.09, sz * 0.05) for sx in (-1, 1) for sz in (-1, 1)], -0.022, 0.006)
for x in (-0.06, -0.03, 0.0, 0.03, 0.06):                                    # guard cage
    add_box(b, (x, -0.100, 0), (0.006, 0.006, 0.13), 0)
for z in (-0.065, 0.065):
    add_box(b, (0, -0.100, z), (0.14, 0.006, 0.006), 0)
for sx in (-1, 1):
    for sz in (-1, 1):
        add_box(b, (sx * 0.07, -0.062, sz * 0.065), (0.006, 0.075, 0.006), 0)
em = finalize("Prop_EmergencyLight", b, col, [STEEL])
b = bmesh.new()
add_ellipsoid(b, (0, -0.045, 0), 0.075, 0.050, 0.055, 0)
finalize("Prop_EmergencyLight_Dome", b, col, [GLASS], origin=(0, -0.045, 0), parent=em)
b = bmesh.new()
add_ellipsoid(b, (0, -0.045, 0), 0.035, 0.030, 0.035, 0)
finalize("Prop_EmergencyLight_Bulb", b, col, [RED], origin=(0, -0.045, 0), parent=em)
props.append(("prop_emergency_light", em))

# --------------------------------------------------------------- number plate
b = bmesh.new()
add_box(b, (0, -0.007, 0), (0.34, 0.014, 0.14), 0, bevel=0.004)
add_box(b, (0, -0.0155, 0), (0.30, 0.003, 0.10), 1)                          # painted face
screws(b, [(sx * 0.15, sz * 0.05) for sx in (-1, 1) for sz in (-1, 1)], -0.017, 0.007)
plate = finalize("Prop_NumberPlate", b, col, [STEEL, PAINT])
new_empty("Anchor_Label", col, parent=plate, location=(0, -0.0175, 0))       # Label3D goes here
props.append(("prop_number_plate", plate))

# ----------------------------------------------------------- electrical panel
b = bmesh.new()
add_box(b, (0, -0.005, 0), (0.60, 0.01, 0.80), 0, bevel=0.003)
add_rect_ring(b, (0.30, 0.40), (0.285, 0.385), -0.01, -0.14, 0)
add_box(b, (0, -0.02, 0), (0.56, 0.01, 0.74), 1)                             # mounting plate
for z in (0.2, 0.0, -0.2):                                                   # breaker rows
    for i in range(6):
        add_box(b, (-0.175 + i * 0.07, -0.045, z), (0.05, 0.04, 0.07), 2)
add_cyl(b, (0.20, -0.07, 0.65), 0.018, 0.50, 'Z', 0, 12)                     # conduit up
add_box(b, (0.20, -0.07, 0.43), (0.05, 0.03, 0.02), 0)                       # clamp
panel = finalize("Prop_ElectricalPanel", b, col, [STEEL, PAINT, RUBBER])
HINGE = (-0.29, -0.15, 0.0)
b = bmesh.new()
add_box(b, (0, -0.15, 0), (0.58, 0.02, 0.78), 0, bevel=0.005)                # door
add_box(b, (0.0, -0.1625, 0.30), (0.30, 0.003, 0.10), 1)                     # warning plate
add_box(b, (0.22, -0.168, 0.0), (0.03, 0.012, 0.12), 2, bevel=0.003)         # latch handle
add_box(b, (-0.22, -0.1615, 0.33), (0.04, 0.003, 0.03), 3)                   # status light
finalize("Prop_ElectricalPanel_Door", b, col, [STEEL, PAINT, RUBBER, AMBER],
         origin=HINGE, parent=panel)
b = bmesh.new()
add_box(b, (0, -0.08, 0), (0.60, 0.16, 0.80), 0)
finalize("Prop_ElectricalPanel_Col-convcolonly", b, col, [STEEL], parent=panel, uv=None)
props.append(("prop_electrical_panel", panel))

# --------------------------------------------------------------- ceiling vent
b = bmesh.new()
for y in (-0.285, 0.285):
    add_box(b, (0, y, -0.015), (0.60, 0.03, 0.03), 0, bevel=0.003)
for x in (-0.285, 0.285):
    add_box(b, (x, 0, -0.015), (0.03, 0.54, 0.03), 0, bevel=0.003)
add_box(b, (0, 0, -0.004), (0.54, 0.54, 0.008), 1)                           # dark backing
for i in range(8):
    yc = -0.21 + i * 0.06
    pts = [(yc - 0.025, -0.010), (yc + 0.025, -0.022), (yc + 0.025, -0.016), (yc - 0.025, -0.004)]
    add_prism_x(b, pts, -0.255, 0.255, 0)                                    # tilted louvres
vent = finalize("Prop_CeilingVent", b, col, [STEEL, RUBBER])
props.append(("prop_ceiling_vent", vent))


# ------------------------------------------------------------- floor markings
def clip(poly, xmin, xmax, ymin, ymax):
    """Sutherland-Hodgman clip of a convex polygon to a rectangle."""
    def run(pts, inside, inter):
        out = []
        for i, p in enumerate(pts):
            q = pts[(i + 1) % len(pts)]
            if inside(p):
                out.append(p)
                if not inside(q):
                    out.append(inter(p, q))
            elif inside(q):
                out.append(inter(p, q))
        return out
    ix = lambda v: (lambda p, q: (v, p[1] + (q[1] - p[1]) * (v - p[0]) / (q[0] - p[0])))
    iy = lambda v: (lambda p, q: (p[0] + (q[0] - p[0]) * (v - p[1]) / (q[1] - p[1]), v))
    for inside, inter in ((lambda p: p[0] >= xmin, ix(xmin)), (lambda p: p[0] <= xmax, ix(xmax)),
                          (lambda p: p[1] >= ymin, iy(ymin)), (lambda p: p[1] <= ymax, iy(ymax))):
        poly = run(poly, inside, inter)
        if not poly:
            return []
    return poly


b = bmesh.new()
add_box(b, (0, 0, 0.0015), (1.0, 0.30, 0.003), 1)                            # dark base
x0 = -0.5 - 0.30
while x0 < 0.5:
    quad = [(x0, -0.15), (x0 + 0.07, -0.15), (x0 + 0.07 + 0.30, 0.15), (x0 + 0.30, 0.15)]
    poly = clip(quad, -0.5, 0.5, -0.15, 0.15)
    if len(poly) >= 3:
        add_prism_z(b, poly, 0.003, 0.0045, 0)
    x0 += 0.14
haz = finalize("Prop_FloorMarking_Hazard", b, col, [PAINT, RUBBER])
for p in haz.data.polygons:
    pass
props.append(("prop_floor_marking_hazard", haz))

b = bmesh.new()
arrow = [(-0.05, 0.35), (0.05, 0.35), (0.05, -0.05), (0.15, -0.05), (0.0, -0.35),
         (-0.15, -0.05), (-0.05, -0.05)]
add_prism_z(b, arrow, 0.0, 0.003, 0)
arr = finalize("Prop_FloorMarking_Arrow", b, col, [PAINT])
props.append(("prop_floor_marking_arrow", arr))

b = bmesh.new()
for i in range(4):
    add_box(b, (-0.375 + i * 0.25, 0, 0.0015), (0.20, 0.08, 0.003), 0)
line = finalize("Prop_FloorMarking_Line", b, col, [PAINT])
props.append(("prop_floor_marking_line", line))

# ------------------------------------------------------------ wall speaker
b = bmesh.new()
add_box(b, (0, -0.005, 0), (0.12, 0.01, 0.10), 0, bevel=0.003)
screws(b, [(sx * 0.045, sz * 0.035) for sx in (-1, 1) for sz in (-1, 1)], -0.013, 0.006)
add_box(b, (0, -0.04, 0), (0.04, 0.07, 0.04), 0, bevel=0.003)               # bracket arm
add_box(b, (0, -0.11, -0.14), (0.20, 0.08, 0.26), 0, bevel=0.006)           # cabinet
add_rect_ring(b, (0.10, 0.13), (0.085, 0.115), -0.15, -0.17, 0, center=(0, -0.14))
add_box(b, (0, -0.158, -0.14), (0.17, 0.004, 0.23), 1)                       # dark cloth behind grille
for i in range(9):
    add_box(b, (0, -0.166, -0.14 + (i - 4) * 0.024), (0.17, 0.006, 0.008), 0)
spk = finalize("Prop_Speaker_Wall", b, col, [STEEL, RUBBER])
props.append(("prop_speaker_wall", spk))

# ------------------------------------------------ smooth only the organic bits
for o in (bpy.data.objects["Prop_EmergencyLight_Dome"], bpy.data.objects["Prop_EmergencyLight_Bulb"]):
    for p in o.data.polygons:
        p.use_smooth = True

# ---------------------------------------------------------------- export
print("=== PROPS ===")
for stem, obj in props:
    export_glb(obj, os.path.join(OUT, stem + ".glb"))
    total, rows = report(obj)
    vis = sum(r[1] for r in rows if "_Col" not in r[0])
    dims = [r for r in rows if r[0] == obj.name][0][2]
    print("%-28s tris visual=%4d total=%4d  root dims=%s" % (stem, vis, total, dims))
x = 0.0
for stem, obj in props:
    obj.location.x = x
    x += 1.5
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "props_kit.blend"))
