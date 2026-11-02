"""Shared door-frame builder (used by build_door.py and build_environment.py)
so the frame in the door asset and the stand-alone Env_Door_Frame are identical."""
import bmesh
from common import *  # noqa

HALF_T = 0.15
HINGE_Z = (0.40, 1.10, 1.80)
BOLT_Z = (0.60, 1.60)


def build_frame(col, steel, rubber, light, name="Door_Frame", parent=None,
                with_lights=True):
    """Frame filling a 1.60 x 2.30 m cutout in a 0.30 m wall.
    Origin: bottom-centre of the opening on the wall mid-plane."""
    bm = bmesh.new()
    profile = [(-0.80, 0.0), (-0.70, 0.0), (-0.70, 2.20), (0.70, 2.20),
               (0.70, 0.0), (0.80, 0.0), (0.80, 2.30), (-0.80, 2.30)]
    add_prism(bm, profile, -HALF_T, HALF_T, mat=0)
    pockets = [((0.72, 0.0, z), (0.06, 0.05, 0.06)) for z in BOLT_Z]
    bm = boolean_cut(bm, pockets, col)
    for f in bm.faces:          # boolean output can carry stray slot indices
        f.material_index = 0

    t = 0.015                   # surround trim hides the wall/frame seam
    for s in (-1, 1):
        yc = s * (HALF_T + t / 2)
        add_box(bm, (-0.83, yc, 1.15), (0.06, t, 2.30), 0, bevel=0.004)
        add_box(bm, (0.83, yc, 1.15), (0.06, t, 2.30), 0, bevel=0.004)
        add_box(bm, (0.0, yc, 2.33), (1.72, t, 0.06), 0, bevel=0.004)

    for hz in HINGE_Z:          # static hinge leaves
        add_box(bm, (-0.6975, 0.0525, hz), (0.011, 0.045, 0.24), 0)

    add_box(bm, (0.0, 0.0, 2.196), (1.40, 0.09, 0.008), 1)       # gaskets
    add_box(bm, (-0.696, -0.0125, 1.096), (0.008, 0.065, 2.192), 1)
    for z0, z1 in [(0.0, 0.56), (0.64, 1.56), (1.64, 2.192)]:
        add_box(bm, (0.696, 0.0, (z0 + z1) / 2), (0.008, 0.09, z1 - z0), 1)

    frame = finalize(name, bm, col, [steel, rubber], parent=parent)

    if with_lights:
        for lname, s in (("Door_Status_Light_Front", -1), ("Door_Status_Light_Back", 1)):
            b = bmesh.new()
            c = (0.75, s * (HALF_T + 0.001), 1.50)
            add_box(b, c, (0.04, 0.004, 0.20), 0)
            finalize(lname, b, col, [light], origin=c, parent=frame)

    b = bmesh.new()             # collision: jambs + header (trimesh, static)
    add_box(b, (-0.75, 0, 1.15), (0.10, 0.30, 2.30), 0)
    add_box(b, (0.75, 0, 1.15), (0.10, 0.30, 2.30), 0)
    add_box(b, (0.0, 0, 2.25), (1.40, 0.30, 0.10), 0)
    finalize(name + "_Col-colonly", b, col, [steel], parent=frame, uv=None)
    return frame
