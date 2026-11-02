"""Build the modular room kit: one .glb per module in Environment/.
Run: blender -b --python build_environment.py

Grid: cell pitch 4.0 m. Wall centre-lines sit ON the grid lines.
  * Env_Floor_4m / Env_Ceiling_4m   4 x 4 m tiles, origin at the cell centre
  * Env_Wall_Straight               3.70 m, origin at the edge mid-point
  * Env_Wall_Doorway                3.70 m with a 1.60 x 2.30 m cutout
  * Env_Wall_Post                   0.30 x 0.30 m post at grid intersections
                                    (covers L, T and X corners)
  * wall length 3.70 + post 0.30 = 4.00 pitch, so nothing overlaps.
"""
import os
import sys
import bpy
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *          # noqa
from door_parts import build_frame  # noqa

OUT = "/home/claude/asset_pack/Environment"
os.makedirs(OUT, exist_ok=True)

reset_scene()
col = new_collection("Environment")
CONC = get_material("M_Concrete_Rough")
PAINTED = get_material("M_Concrete_Painted")
STEEL = get_material("M_Steel_Dark_Brushed")
PAINT = get_material("M_Paint_Worn")
RUBBER = get_material("M_Polymer_Rubber")
LAMP = get_material("M_Emissive_Light_Amber")
WHITE = get_material("M_Emissive_Light_White")

BEV = 0.01          # chamfer = visible formwork joint
H = 3.0
T = 0.30
modules = []        # (name, root object, display offset)


def wall_block(bm, x0, x1, y0, y1, z0, z1):
    """Wall block split at 1 m / 2 m panel joints. The lowest metre is painted
    concrete (slot 1), the rest rough concrete (slot 0)."""
    cuts = sorted(set([z0, z1] + [j for j in (1.0, 2.0) if z0 < j < z1]))
    for a, b in zip(cuts, cuts[1:]):
        mat = 1 if b <= 1.0 + 1e-6 else 0
        add_box(bm, ((x0 + x1) / 2, (y0 + y1) / 2, (a + b) / 2),
                (x1 - x0, y1 - y0, b - a), mat, bevel=BEV)


def collision(name, root, boxes, hint):
    """boxes: list of (centre, size). hint: 'convcolonly' or 'colonly'."""
    b = bmesh.new()
    for c, s in boxes:
        add_box(b, c, s, 0)
    finalize("%s_Col-%s" % (name, hint), b, col, [STEEL], parent=root, uv=None)


# ---- floor -------------------------------------------------------------
b = bmesh.new()
add_box(b, (0, 0, -0.1), (4.0, 4.0, 0.2), 0, bevel=BEV)
o = finalize("Env_Floor_4m", b, col, [PAINTED])
collision("Env_Floor_4m", o, [((0, 0, -0.1), (4, 4, 0.2))], "convcolonly")
modules.append(("env_floor_4m", o))

# ---- ceiling (origin = underside centre, slab extends UP) ---------------
b = bmesh.new()
add_box(b, (0, 0, 0.15), (4.0, 4.0, 0.3), 0, bevel=BEV)
o = finalize("Env_Ceiling_4m", b, col, [PAINTED])
collision("Env_Ceiling_4m", o, [((0, 0, 0.15), (4, 4, 0.3))], "convcolonly")
modules.append(("env_ceiling_4m", o))

# ---- straight wall --------------------------------------------------------
b = bmesh.new()
wall_block(b, -1.85, 1.85, -T / 2, T / 2, 0, H)
o = finalize("Env_Wall_Straight", b, col, [CONC, PAINTED])
collision("Env_Wall_Straight", o, [((0, 0, H / 2), (3.7, T, H))], "convcolonly")
modules.append(("env_wall_straight", o))

# ---- post (corner / T / X) ------------------------------------------------
b = bmesh.new()
wall_block(b, -T / 2, T / 2, -T / 2, T / 2, 0, H)
o = finalize("Env_Wall_Post", b, col, [CONC, PAINTED])
collision("Env_Wall_Post", o, [((0, 0, H / 2), (T, T, H))], "convcolonly")
modules.append(("env_wall_post", o))

# ---- doorway wall (cutout 1.60 x 2.30 centred) ----------------------------
b = bmesh.new()
wall_block(b, -1.85, -0.80, -T / 2, T / 2, 0, H)
wall_block(b, 0.80, 1.85, -T / 2, T / 2, 0, H)
wall_block(b, -0.80, 0.80, -T / 2, T / 2, 2.30, H)
o = finalize("Env_Wall_Doorway", b, col, [CONC, PAINTED])
collision("Env_Wall_Doorway", o,
          [((-1.325, 0, H / 2), (1.05, T, H)),
           ((1.325, 0, H / 2), (1.05, T, H)),
           ((0, 0, 2.65), (1.60, T, 0.70))], "colonly")
modules.append(("env_wall_doorway", o))

# ---- stand-alone door frame (same geometry as the door asset) -------------
o = build_frame(col, STEEL, RUBBER, LAMP, name="Env_Door_Frame", with_lights=False)
modules.append(("env_door_frame", o))

# ---- ceiling light fixture (origin = mount point, hangs 0.054 m down) -----
b = bmesh.new()
add_box(b, (0, 0, -0.025), (0.90, 0.28, 0.05), 0, bevel=0.005)
add_box(b, (0, 0, -0.052), (0.80, 0.18, 0.004), 1)
o = finalize("Env_Light_Ceiling", b, col, [STEEL, WHITE])
modules.append(("env_light_ceiling", o))

# ---- optional: wall panel (origin = back-plate centre, front faces -Y) ----
b = bmesh.new()
add_box(b, (0, -0.01, 0), (1.0, 0.02, 1.2), 0, bevel=0.004)
for sx in (-1, 1):
    for sz in (-1, 1):
        add_cyl(b, (sx * 0.45, -0.023, sz * 0.55), 0.015, 0.006, 'Y', 0, 8)
add_box(b, (0, -0.0215, 0.0), (0.80, 0.003, 0.08), 1)       # painted label bar
add_box(b, (0, -0.0215, -0.35), (0.80, 0.003, 0.012), 1)
o = finalize("Env_Wall_Panel", b, col, [STEEL, PAINT])
modules.append(("env_wall_panel", o))

# ---- optional: ventilation grille -----------------------------------------
b = bmesh.new()
add_rect_ring(b, (0.30, 0.20), (0.26, 0.16), 0.0, -0.04, 0)
add_box(b, (0, -0.005, 0), (0.60, 0.01, 0.40), 1)            # dark backing
for i in range(6):
    z = -0.125 + i * 0.05
    add_box(b, (0, -0.02, z), (0.52, 0.012, 0.012), 0)
o = finalize("Env_Grille_Wall", b, col, [STEEL, RUBBER])
modules.append(("env_grille_wall", o))

# ---- export each module on its own, then lay them out for the .blend ------
print("=== ENVIRONMENT KIT ===")
for fname, obj in modules:
    export_glb(obj, os.path.join(OUT, fname + ".glb"))
    total, rows = report(obj)
    vis = sum(r[1] for r in rows if "_Col" not in r[0])
    d = [r for r in rows if r[0] == obj.name][0][2]
    print("%-18s tris visual=%4d total=%4d  dims=%s" % (fname, vis, total, d))
x = 0.0
for fname, obj in modules:
    obj.location.x = x
    x += 5.0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "environment_kit.blend"))
