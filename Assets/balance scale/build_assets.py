"""
The Auction - procedural asset kit generator.
Units: metres, Y-up (glTF standard; Godot imports 1 unit = 1 m).
Run:  python build_assets.py   ->  writes .glb files into ./out
Requires: pip install trimesh numpy

Conventions
- Every asset has a clean origin (documented in README / comments).
- Nodes named "*-col" are turned into static collision by Godot's importer
  (and their visible mesh is removed).
- No text, numbers, or UI baked in. Screens/pads are UV-mapped quads that
  you replace with a SubViewport texture in Godot.
"""
import os
import numpy as np
import trimesh
from trimesh.visual import TextureVisuals
from trimesh.visual.material import PBRMaterial
from trimesh.transformations import rotation_matrix as rot, translation_matrix as T

PI = np.pi
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- materials
def mat(name, rgb, metal=0.0, rough=0.8, emit=None, alpha=None):
    a = 255 if alpha is None else alpha
    return PBRMaterial(
        name=name,
        baseColorFactor=[rgb[0], rgb[1], rgb[2], a],
        metallicFactor=metal,
        roughnessFactor=rough,
        emissiveFactor=emit if emit else [0, 0, 0],
        alphaMode="BLEND" if alpha is not None else "OPAQUE",
        doubleSided=alpha is not None,
    )


M_CONCRETE = mat("Concrete", (92, 92, 96), 0.0, 0.95)
M_CONCRETE_DK = mat("ConcreteDark", (58, 58, 62), 0.0, 0.85)
M_METAL = mat("DarkMetal", (36, 38, 42), 0.85, 0.5)
M_PIPE = mat("PipeMetal", (74, 72, 68), 0.75, 0.55)
M_BRASS = mat("Brass", (150, 120, 60), 0.9, 0.4)
M_RED_EMIT = mat("WarningRed", (255, 30, 20), 0.0, 0.4, emit=[1.0, 0.06, 0.03])
M_LAMP = mat("LampLens", (255, 244, 220), 0.0, 0.3, emit=[1.0, 0.93, 0.75])
M_GLASS = mat("ReinforcedGlass", (200, 230, 230), 0.0, 0.05, alpha=55)
M_ACID = mat("Acid", (185, 240, 60), 0.0, 0.1, emit=[0.55, 0.85, 0.12], alpha=215)
M_MARK = mat("LevelMark", (255, 255, 255), 0.0, 0.5, emit=[0.9, 0.9, 0.9])
M_SCREEN = mat("ScreenBlank", (10, 10, 12), 0.0, 0.2)
M_VALVE = mat("ValveRed", (170, 30, 25), 0.3, 0.5)


# ---------------------------------------------------------------- primitives
# Helpers return raw meshes (no material); part() merges + paints them.
def box(ext, pos=(0, 0, 0)):
    m = trimesh.creation.box(extents=ext)
    m.apply_translation(pos)
    return m


def cyl(r, h, pos=(0, 0, 0), axis="y", sections=32):
    m = trimesh.creation.cylinder(radius=r, height=h, sections=sections)
    if axis == "y":
        m.apply_transform(rot(-PI / 2, [1, 0, 0]))
    elif axis == "x":
        m.apply_transform(rot(PI / 2, [0, 1, 0]))
    m.apply_translation(pos)
    return m


def ring(r_out, r_in, h, pos=(0, 0, 0), axis="y", sections=48):
    m = trimesh.creation.annulus(r_min=r_in, r_max=r_out, height=h, sections=sections)
    if axis == "y":
        m.apply_transform(rot(-PI / 2, [1, 0, 0]))
    elif axis == "x":
        m.apply_transform(rot(PI / 2, [0, 1, 0]))
    m.apply_translation(pos)
    return m


def ball(r, pos=(0, 0, 0)):
    m = trimesh.creation.icosphere(subdivisions=2, radius=r)
    m.apply_translation(pos)
    return m


def tube(p0, p1, r, sections=24):
    p0, p1 = np.array(p0, float), np.array(p1, float)
    v = p1 - p0
    L = np.linalg.norm(v)
    m = trimesh.creation.cylinder(radius=r, height=L, sections=sections)
    m.apply_transform(trimesh.geometry.align_vectors([0, 0, 1], v / L))
    m.apply_translation((p0 + p1) / 2)
    return m


def quad_uv(w, h):
    """Quad facing +Z with 0..1 UVs (for screens / pads)."""
    v = np.array([[-w / 2, -h / 2, 0], [w / 2, -h / 2, 0], [w / 2, h / 2, 0], [-w / 2, h / 2, 0]])
    f = np.array([[0, 1, 2], [0, 2, 3]])
    uv = np.array([[0, 0], [1, 0], [1, 1], [0, 1]])
    m = trimesh.Trimesh(vertices=v, faces=f, process=False)
    m.visual = TextureVisuals(uv=uv, material=M_SCREEN)
    return m


def part(scene, name, meshes, material, transform=None):
    """Merge meshes -> one flat-shaded mesh with one material -> one node."""
    if not isinstance(meshes, (list, tuple)):
        meshes = [meshes]
    m = trimesh.util.concatenate(meshes)
    m.unmerge_vertices()  # hard edges (industrial look)
    m.visual = TextureVisuals(material=material)
    scene.add_geometry(m, node_name=name, geom_name=name, transform=transform)


def col(scene, name, meshes):
    m = trimesh.util.concatenate(meshes if isinstance(meshes, (list, tuple)) else [meshes])
    scene.add_geometry(m, node_name=name + "-col", geom_name=name + "-col")


def save(scene, filename):
    path = os.path.join(OUT, filename)
    scene.export(path)
    print(f"{filename:28s} {os.path.getsize(path) / 1024:7.1f} KB")


# ================================================================ CHAMBER
# Origin: centre of the floor, floor top at y=0. Interior 10 x 10 x 4.5 m.
def build_chamber():
    s = trimesh.Scene()
    part(s, "Floor", box((10.8, 0.2, 10.8), (0, -0.1, 0)), M_CONCRETE_DK)
    walls = [
        box((10.8, 4.5, 0.4), (0, 2.25, -5.2)),
        box((10.8, 4.5, 0.4), (0, 2.25, 5.2)),
        box((0.4, 4.5, 10.0), (5.2, 2.25, 0)),
        box((0.4, 4.5, 10.0), (-5.2, 2.25, 0)),
    ]
    part(s, "Walls", walls, M_CONCRETE)
    wain = [
        box((9.4, 1.0, 0.04), (0, 0.5, -4.98)),
        box((9.4, 1.0, 0.04), (0, 0.5, 4.98)),
        box((0.04, 1.0, 9.4), (4.98, 0.5, 0)),
        box((0.04, 1.0, 9.4), (-4.98, 0.5, 0)),
    ]
    part(s, "WallPanels", wain, M_METAL)
    cols = [box((0.6, 4.5, 0.6), (sx * 4.7, 2.25, sz * 4.7)) for sx in (-1, 1) for sz in (-1, 1)]
    part(s, "Columns", cols, M_CONCRETE_DK)
    ceil = [box((10.8, 0.2, 10.8), (0, 4.6, 0))]
    ceil += [box((0.3, 0.4, 10.0), (x, 4.3, 0)) for x in (-4, -2, 0, 2, 4)]
    part(s, "Ceiling", ceil, M_CONCRETE)

    # perimeter main pipe at y=4.1 (feed stubs from acid pots end at +-3.1)
    h, r = 4.1, 0.12
    c = 3.1
    pts = [(-c, h, -c), (c, h, -c), (c, h, c), (-c, h, c)]
    pp = [tube(pts[i], pts[(i + 1) % 4], r) for i in range(4)] + [ball(r * 1.15, p) for p in pts]
    # wall-run conduits + corner risers
    pp += [tube((-4.8, 3.6, -4.65), (4.8, 3.6, -4.65), 0.08), tube((-4.8, 3.6, 4.65), (4.8, 3.6, 4.65), 0.08),
           tube((4.65, 3.4, -4.8), (4.65, 3.4, 4.8), 0.08), tube((-4.65, 3.4, -4.8), (-4.65, 3.4, 4.8), 0.08)]
    pp += [tube((sx * 4.3, 0, sz * 4.3), (sx * 4.3, 4.5, sz * 4.3), 0.06) for sx in (-1, 1) for sz in (-1, 1)]
    part(s, "Pipes", pp, M_PIPE)

    # spotlight housings (add SpotLight3D nodes under these in Godot)
    pos = [(0, 0)] + [(sx * 1.2, sz * 1.2) for sx in (-1, 1) for sz in (-1, 1)]
    hous, lens = [], []
    for x, z in pos:
        hous += [cyl(0.25, 0.3, (x, 4.1, z)), cyl(0.02, 0.3, (x, 4.35, z), sections=12)]
        lens.append(cyl(0.2, 0.02, (x, 3.94, z)))
    part(s, "SpotHousings", hous, M_METAL)
    part(s, "SpotLenses", lens, M_LAMP)

    # red warning lights (add OmniLight3D, energy low, red)
    cages = [box((0.2, 0.2, 0.2), (sx * 4.35, 3.7, sz * 4.35)) for sx in (-1, 1) for sz in (-1, 1)]
    part(s, "WarningLights", cages, M_RED_EMIT)

    col(s, "Floor", [box((10.8, 0.2, 10.8), (0, -0.1, 0))])
    col(s, "Walls", walls)
    col(s, "Ceiling", [box((10.8, 0.2, 10.8), (0, 4.6, 0))])
    save(s, "auction_chamber.glb")


# ================================================================ TABLE
# Origin: floor centre under the table. Top surface y=0.80. Square 2.8 x 2.8.
# Players sit at +X, -X, +Z, -Z (pad built at +X then rotated about Y).
def build_table():
    s = trimesh.Scene()
    part(s, "Top", box((2.8, 0.1, 2.8), (0, 0.75, 0)), M_METAL)
    part(s, "Edge", [box((2.84, 0.03, 2.84), (0, 0.80, 0)).copy()] if False else
         [box((2.9, 0.06, 0.05), (0, 0.80, 1.42)), box((2.9, 0.06, 0.05), (0, 0.80, -1.42)),
          box((0.05, 0.06, 2.8), (1.42, 0.80, 0)), box((0.05, 0.06, 2.8), (-1.42, 0.80, 0))], M_PIPE)
    part(s, "Base", [box((1.0, 0.70, 1.0), (0, 0.35, 0)), box((1.8, 0.05, 1.8), (0, 0.025, 0))], M_CONCRETE_DK)

    tilt = rot(-0.2, [0, 0, 1])  # pad tilts toward the player at +X
    for i, name in enumerate(["E", "S", "W", "N"]):
        R = rot(i * PI / 2, [0, 1, 0])
        housing = box((0.45, 0.06, 0.7))
        housing.apply_transform(T([1.0, 0.86, 0]) @ tilt)
        housing.apply_transform(R)
        part(s, f"BidPadFrame_{name}", housing, M_METAL)
        q = quad_uv(0.38, 0.6)  # facing +Z -> rotate to +Y
        q.apply_transform(rot(-PI / 2, [1, 0, 0]))
        q.apply_transform(T([1.0, 0.894, 0]) @ tilt)  # sits just above housing
        q.apply_transform(R)
        s.add_geometry(q, node_name=f"BidScreen_{name}", geom_name=f"BidScreen_{name}")
    col(s, "Table", [box((2.8, 0.1, 2.8), (0, 0.75, 0)), box((1.0, 0.70, 1.0), (0, 0.35, 0))])
    save(s, "auction_table.glb")


# ================================================================ CHAIR
# Origin: floor centre under the seat. Chair faces -X (player at +X side).
def build_chair():
    s = trimesh.Scene()
    part(s, "Seat", [box((0.46, 0.05, 0.46), (0, 0.46, 0)), box((0.04, 0.5, 0.46), (0.22, 0.73, 0))], M_METAL)
    legs = [cyl(0.025, 0.44, (sx * 0.19, 0.22, sz * 0.19), sections=12) for sx in (-1, 1) for sz in (-1, 1)]
    legs.append(box((0.6, 0.02, 0.6), (0, 0.01, 0)))
    part(s, "Frame", legs, M_PIPE)
    col(s, "Chair", [box((0.5, 0.5, 0.5), (0, 0.25, 0)), box((0.04, 0.5, 0.46), (0.22, 0.73, 0))])
    save(s, "player_chair.glb")


# ================================================================ ACID POT
# Origin: bottom-centre of the pot assembly. Glass interior radius 0.31,
# glass spans y=0.06..1.0. Neck top at y=1.40 (pipes_feed attaches there).
POT_BASE, POT_TOP = 0.06, 1.0
LIQ_H = 0.80                      # liquid mesh height at scale.y = 1.0
MAX_LINE_Y = POT_BASE + LIQ_H     # 0.86


def build_pot():
    s = trimesh.Scene()
    part(s, "Glass", ring(0.33, 0.31, POT_TOP - POT_BASE, (0, (POT_TOP + POT_BASE) / 2, 0)), M_GLASS)
    frame = [ring(0.40, 0.30, 0.06, (0, 0.03, 0)), ring(0.40, 0.30, 0.06, (0, POT_TOP + 0.03, 0)),
             cyl(0.40, 0.08, (0, 1.10, 0)), cyl(0.09, 0.26, (0, 1.27, 0))]
    for k in range(4):
        a = PI / 4 + k * PI / 2
        frame.append(cyl(0.018, 1.06, (0.385 * np.cos(a), 0.53, 0.385 * np.sin(a)), sections=12))
    part(s, "Frame", frame, M_METAL)
    marks = [ring(0.336, 0.329, 0.014, (0, MAX_LINE_Y, 0))]  # MAX line (full ring, readable from any side)
    marks += [box((0.012, 0.008, 0.07), (0.335, POT_BASE + LIQ_H * f, 0)) for f in (0.25, 0.5, 0.75)]
    part(s, "MaxLine", marks[:1], M_RED_EMIT)
    part(s, "LevelTicks", marks[1:], M_MARK)
    save(s, "acid_pot.glb")


# ================================================================ LIQUID
# Origin: bottom-centre of liquid. Height 0.8 (== max line). In Godot, set
# scale.y = fill (0..1); up to ~1.17 = overflowing to the rim.
def build_liquid():
    s = trimesh.Scene()
    part(s, "Liquid", cyl(0.305, LIQ_H, (0, LIQ_H / 2, 0), sections=40), M_ACID)
    save(s, "acid_liquid.glb")


# Pour stream: origin at TOP, hangs down 1 m. Scale Y to stream length.
def build_stream():
    s = trimesh.Scene()
    part(s, "Stream", cyl(0.025, 1.0, (0, -0.5, 0), sections=12), M_ACID)
    save(s, "acid_stream.glb")


# ================================================================ PIPES + VALVE
# Same origin as the pot. Feed rises from neck top (y=1.4) to header at 1.9,
# then runs outward along +X 1.2 m to meet the chamber ring main.
def build_pipes():
    s = trimesh.Scene()
    r = 0.07
    p = [tube((0, 1.38, 0), (0, 1.9, 0), r), ball(r * 1.3, (0, 1.9, 0)), tube((0, 1.9, 0), (1.2, 1.9, 0), r)]
    p += [ring(0.1, 0.0, 0.04, (0, y, 0)) if False else cyl(0.1, 0.04, (0, y, 0)) for y in (1.4, 1.75)]
    p += [cyl(0.1, 0.04, (1.2, 1.9, 0), axis="x"), cyl(0.1, 0.04, (0.6, 1.9, 0), axis="x")]
    part(s, "FeedPipe", p, M_PIPE)
    save(s, "pipes_feed.glb")


# Valve: origin on the pipe centreline. "ValveWheel" pivots at its own centre
# (rotate around Y). Place at pot origin + (0, 1.6, 0).
def build_valve():
    s = trimesh.Scene()
    body = [ball(0.11), cyl(0.1, 0.04, (0, -0.12, 0)), cyl(0.1, 0.04, (0, 0.12, 0)), cyl(0.018, 0.2, (0, 0.2, 0), sections=12)]
    part(s, "ValveBody", body, M_BRASS)
    wheel = [ring(0.12, 0.10, 0.02), box((0.24, 0.02, 0.02)), box((0.02, 0.02, 0.24))]
    part(s, "ValveWheel", wheel, M_VALVE, transform=T([0, 0.3, 0]))
    save(s, "valve.glb")


# ================================================================ RELEASE MECHANISM
# Origin: pot bottom-centre. "Hatch" is hinged at x=-0.34: rotate its Z by
# -90deg to swing it open downward. "LatchBolt" slides along +X to release.
def build_release():
    s = trimesh.Scene()
    part(s, "Housing", [ring(0.42, 0.30, 0.04, (0, -0.02, 0)), box((0.12, 0.16, 0.14), (0.52, -0.07, 0)),
                        cyl(0.03, 0.14, (-0.34, -0.03, 0.30), axis="x") if False else box((0.06, 0.06, 0.1), (-0.36, -0.03, 0.30)),
                        box((0.06, 0.06, 0.1), (-0.36, -0.03, -0.30))], M_METAL)
    hatch = cyl(0.34, 0.03, (0.34, 0, 0), sections=40)
    part(s, "Hatch", hatch, M_PIPE, transform=T([-0.34, -0.05, 0]))
    part(s, "LatchBolt", cyl(0.02, 0.2, (0.0, 0, 0), axis="x", sections=12), M_RED_EMIT, transform=T([0.40, -0.085, 0]))
    save(s, "release_mechanism.glb")


# ================================================================ ROUND DISPLAY
# Origin: centre of back face (mount flush to wall, +Z points into room).
# "Screen" quad 3.0 x 1.1 m, UV 0..1: assign a SubViewport texture in Godot.
def build_display():
    s = trimesh.Scene()
    part(s, "Housing", [box((3.2, 1.3, 0.3), (0, 0, 0.15)), tube((-1.2, 0.65, 0.15), (-1.2, 1.4, 0.15), 0.025, 12),
                        tube((1.2, 0.65, 0.15), (1.2, 1.4, 0.15), 0.025, 12)], M_METAL)
    q = quad_uv(3.0, 1.1)
    q.apply_translation((0, 0, 0.302))
    s.add_geometry(q, node_name="Screen", geom_name="Screen")
    part(s, "StatusLamps", [box((0.08, 0.05, 0.02), (x, -0.6, 0.31)) for x in (-1.45, 1.45)], M_RED_EMIT)
    save(s, "round_display.glb")


if __name__ == "__main__":
    for fn in (build_chamber, build_table, build_chair, build_pot, build_liquid,
               build_stream, build_pipes, build_valve, build_release, build_display):
        fn()
