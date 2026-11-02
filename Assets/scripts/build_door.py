"""Build Doors/door_standard.glb  (run: blender -b --python build_door.py)

Door root space: X = across the opening (centred), Y = through the wall
(centred on the wall mid-plane, front = -Y), Z = up from the floor line.

Phase 1 numbers: wall cutout 1.60 x 2.30, clear opening 1.40 x 2.20,
wall thickness 0.30, door panel ~1.355 x 0.10 x 2.18, hinged.
"""
import os
import sys
import math
import bpy
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *  # noqa

OUT_DIR = "/home/claude/asset_pack/Doors"

reset_scene()
col = new_collection("Doors")
STEEL = get_material("M_Steel_Dark_Brushed")
PAINT = get_material("M_Paint_Worn")
RUBBER = get_material("M_Polymer_Rubber")
LIGHT = get_material("M_Emissive_Light_Amber")

# ---- layout constants ------------------------------------------------------
HALF_T = 0.15                 # half wall thickness
OPEN_HALF_W = 0.70            # clear opening half width
OPEN_H = 2.20                 # clear opening height
FRAME_OUT_HALF_W = 0.80
FRAME_H = 2.30
HINGE_AXIS = (-0.67, 0.05)    # (x, y) of the vertical hinge axis
PANEL_X0, PANEL_X1 = -0.665, 0.690
PANEL_Z0, PANEL_Z1 = 0.01, 2.19
PANEL_HALF_T = 0.05
HINGE_Z = (0.40, 1.10, 1.80)
BOLT_Z = (0.60, 1.60)

root = None   # no root empty: Godot already wraps the file in a root node

# ============================================================================
# FRAME (static): shared with the stand-alone Env_Door_Frame (door_parts.py)
# ============================================================================
from door_parts import build_frame  # noqa
frame = build_frame(col, STEEL, RUBBER, LIGHT, name="Door_Frame", parent=root)

# ============================================================================
# PANEL (moving) -- origin on the hinge axis at floor level
#   slots: 0 steel, 1 worn paint, 2 polymer
# ============================================================================
bm = bmesh.new()
px_c = (PANEL_X0 + PANEL_X1) / 2
pz_c = (PANEL_Z0 + PANEL_Z1) / 2
add_box(bm, (px_c, 0, pz_c), (PANEL_X1 - PANEL_X0, 2 * PANEL_HALF_T,
                              PANEL_Z1 - PANEL_Z0), 0, bevel=0.008)

for s in (-1, 1):
    ya = s * (PANEL_HALF_T + 0.004)
    # raised border rim
    add_box(bm, (-0.585, ya, 1.10), (0.04, 0.008, 2.06), 0)
    add_box(bm, (0.610, ya, 1.10), (0.04, 0.008, 2.06), 0)
    add_box(bm, (0.0125, ya, 0.09), (1.155, 0.008, 0.04), 0)
    add_box(bm, (0.0125, ya, 2.11), (1.155, 0.008, 0.04), 0)
    # worn-paint stripe: the one bright element on the door
    add_box(bm, (-0.10, s * (PANEL_HALF_T + 0.003), 1.53), (0.80, 0.006, 0.06), 1)
    # lock housing + cylinder
    add_box(bm, (0.50, s * (PANEL_HALF_T + 0.007), 1.10), (0.12, 0.014, 0.30), 0,
            bevel=0.004)
    add_cyl(bm, (0.50, s * (PANEL_HALF_T + 0.019), 1.10), 0.022, 0.010,
            axis='Y', mat=2, seg=12)

# hinge barrels (rotate with the panel)
for hz in HINGE_Z:
    add_cyl(bm, (HINGE_AXIS[0], HINGE_AXIS[1], hz), 0.022, 0.18, 'Z', 0, 12)

# rubber door sweep along the bottom edge
add_box(bm, (px_c, 0, 0.02), (1.28, 0.06, 0.04), 2)

panel = finalize("Door_Panel", bm, col, [STEEL, PAINT, RUBBER],
                 origin=(HINGE_AXIS[0], HINGE_AXIS[1], 0.0), parent=root)

# panel collision: one convex box
b = bmesh.new()
add_box(b, (px_c, 0, pz_c), (PANEL_X1 - PANEL_X0, 2 * PANEL_HALF_T,
                             PANEL_Z1 - PANEL_Z0), 0)
finalize("Door_Panel_Col-convcolonly", b, col, [STEEL],
         origin=(HINGE_AXIS[0], HINGE_AXIS[1], 0.0), parent=panel, uv=None)

# deadbolts (slide along the panel's local X; origin at bolt centre)
bolts = []
for i, bz in zip("AB", BOLT_Z):
    b = bmesh.new()
    add_box(b, (0.68, 0, bz), (0.12, 0.04, 0.05), 0, bevel=0.004)
    bolts.append(finalize("Door_Bolt_" + i, b, col, [STEEL],
                          origin=(0.68, 0, bz), parent=panel))

# ============================================================================
# Animation: one clip "Door_Open" (bolts retract, then panel swings 100 deg
# toward +Y). Close it in Godot with play_backwards().
# ============================================================================
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 40


def push_track(obj, clip_name):
    ad = obj.animation_data
    act = ad.action
    tr = ad.nla_tracks.new()
    tr.name = clip_name
    st = tr.strips.new(clip_name, 1, act)
    ad.action = None
    return st


def key(obj, path, idx, frame, value):
    getattr(obj, path)[idx] = value
    obj.keyframe_insert(data_path=path, index=idx, frame=frame)


def smooth(obj):
    for fc in obj.animation_data.action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'


# panel: hold closed while the bolts retract (frames 1-10), then swing open
panel.animation_data_create()
key(panel, "rotation_euler", 2, 1, 0.0)
key(panel, "rotation_euler", 2, 10, 0.0)
key(panel, "rotation_euler", 2, 40, math.radians(100))
panel.rotation_euler[2] = 0.0
panel.animation_data.action.name = "Door_Panel_Open"
smooth(panel)
push_track(panel, "Door_Open")

# bolts: retract 5 cm along the panel's local X (frames 1-10), then stay
for bo in bolts:
    x0 = bo.location.x
    bo.animation_data_create()
    key(bo, "location", 0, 1, x0)
    key(bo, "location", 0, 10, x0 - 0.05)
    key(bo, "location", 0, 40, x0 - 0.05)
    bo.location[0] = x0
    bo.animation_data.action.name = "Door_Bolt_Open_" + bo.name[-1]
    smooth(bo)
    push_track(bo, "Door_Open")
bpy.context.view_layer.update()

# ============================================================================
# Save + export + report
# ============================================================================
os.makedirs(OUT_DIR, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "door_standard.blend"))
roots = [frame, panel]
export_glb(roots, os.path.join(OUT_DIR, "door_standard.glb"))
total, rows = report(roots)
print("=== Door_Standard ===")
for r in rows:
    print(r)
print("TOTAL TRIS (visual+collision):", total)
