"""Shared helpers for the Psychological Survival asset pack (Blender 4.0+).

Conventions (Phase 1 style guide):
  * 1 Blender unit = 1 metre, Z up while authoring.
  * Assets are authored facing -Y (Blender "front"); the glTF exporter turns
    that into +Z, which is Godot's model-front convention.
  * UVs use box mapping at a fixed density: 1 UV unit = 4 m, so a 1024 px
    texture gives 256 px/m everywhere.
"""
import bpy
import bmesh
from mathutils import Vector, Matrix

UV_SCALE = 1.0 / 4.0


# --------------------------------------------------------------------------
# Scene / collections
# --------------------------------------------------------------------------
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.unit_settings.system = 'METRIC'
    s.unit_settings.scale_length = 1.0
    s.render.fps = 24


def new_collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def new_empty(name, col, parent=None, location=(0, 0, 0)):
    o = bpy.data.objects.new(name, None)
    o.empty_display_type = 'PLAIN_AXES'
    o.empty_display_size = 0.1
    o.location = location
    col.objects.link(o)
    bpy.context.view_layer.update()
    if parent:
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()
    return o


# --------------------------------------------------------------------------
# Materials (palette from the Phase 1 style guide)
# --------------------------------------------------------------------------
def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_lin(h):
    h = h.lstrip('#')
    r, g, b = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return (_lin(r), _lin(g), _lin(b), 1.0)


PALETTE = {
    # name: (base, metallic, roughness, emission_hex or None)
    # NOTE: differs from the Phase 1 draft (#2A2E32, metallic 1.0). Pure dark
    # metal has no diffuse, so in rooms with no reflection probes it can crush
    # to black; 0.65 metallic keeps some body so doors stay readable.
    "M_Steel_Dark_Brushed": ("#4B5258", 0.65, 0.45, None),
    "M_Concrete_Rough": ("#7B8085", 0.0, 0.90, None),
    "M_Concrete_Painted": ("#596168", 0.0, 0.70, None),
    "M_Paint_Worn": ("#B8B5AB", 0.0, 0.70, None),
    "M_Glass_Frosted": ("#C8D0D4", 0.0, 0.55, None),
    "M_Polymer_Rubber": ("#17191B", 0.0, 0.85, None),
    # Dark glass with a faint amber backlight tint
    "M_Emissive_Screen": ("#050607", 0.0, 0.25, "#3D2200"),
    # Digits get their own material so their colour can change independently
    "M_Digit_Amber": ("#1A0E00", 0.0, 0.40, "#FFA21F"),
    "M_Emissive_Light_Amber": ("#1A0E00", 0.0, 0.40, "#FFA21F"),
    "M_Emissive_Light_White": ("#101214", 0.0, 0.40, "#E9F2FF"),
    "M_Emissive_Light_Red": ("#1A0505", 0.0, 0.40, "#E5201B"),
    # --- character (Phase 4) ---
    "M_Char_Skin": ("#B58A6B", 0.0, 0.55, None),
    "M_Char_Cloth_Top": ("#A8781F", 0.0, 0.90, None),      # recoloured per player
    "M_Char_Cloth_Pants": ("#343A40", 0.0, 0.92, None),    # recoloured per player
    "M_Char_Cloth_Accent": ("#C9C6BD", 0.0, 0.90, None),   # beanie, recoloured per player
    "M_Char_Boots": ("#1D1F21", 0.0, 0.60, None),
    "M_Char_Hair": ("#2A211C", 0.0, 0.60, None),
    "M_Char_Eye": ("#0B0B0C", 0.0, 0.20, None),
}


def get_material(name):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    base, metallic, rough, emit = PALETTE[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = hex_to_lin(base)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = hex_to_lin(emit)
        b.inputs["Emission Strength"].default_value = 1.0  # boost in Godot
    else:
        b.inputs["Emission Color"].default_value = (0, 0, 0, 1)
        b.inputs["Emission Strength"].default_value = 0.0
    if name == "M_Glass_Frosted":
        b.inputs["Alpha"].default_value = 0.55
        m.blend_method = 'BLEND'
    return m


# --------------------------------------------------------------------------
# bmesh primitives. All coordinates are in the asset's root space (metres).
# --------------------------------------------------------------------------
def add_box(bm, center, size, mat=0, bevel=0.0):
    """Axis-aligned box; optional single-segment chamfer on every edge."""
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    for v in tmp.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=bevel,
                        segments=1, affect='EDGES')
    for f in tmp.faces:
        f.material_index = mat
    for v in tmp.verts:
        v.co += Vector(center)
    _merge(bm, tmp)


def add_cyl(bm, center, radius, depth, axis='Z', mat=0, seg=12):
    tmp = bmesh.new()
    rot = {'Z': Matrix.Identity(4),
           'X': Matrix.Rotation(1.5707963, 4, 'Y'),
           'Y': Matrix.Rotation(1.5707963, 4, 'X')}[axis]
    bmesh.ops.create_cone(tmp, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=radius, radius2=radius, depth=depth,
                          matrix=rot)
    for f in tmp.faces:
        f.material_index = mat
    for v in tmp.verts:
        v.co += Vector(center)
    _merge(bm, tmp)


def add_prism(bm, pts_xz, y0, y1, mat=0):
    """Extrude a closed XZ polygon from y0 to y1 (any winding; normals are
    recalculated afterwards)."""
    tmp = bmesh.new()
    a = [tmp.verts.new((x, y0, z)) for x, z in pts_xz]
    b = [tmp.verts.new((x, y1, z)) for x, z in pts_xz]
    n = len(pts_xz)
    tmp.faces.new(a)
    tmp.faces.new(list(reversed(b)))
    for i in range(n):
        j = (i + 1) % n
        tmp.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    for f in tmp.faces:
        f.material_index = mat
    _merge(bm, tmp)


def add_rect_ring(bm, outer, inner, y_back, y_front, mat=0, center=(0.0, 0.0)):
    """Rectangular bezel: outer/inner = (half_x, half_z). Front face at
    y_front, open at the back (y_back). Normals point away from the opening
    axis for the walls and toward -Y for the front (when y_front < y_back)."""
    tmp = bmesh.new()
    ox, oz = outer
    ix, iz = inner

    cx, cz = center

    def ring(hx, hz, y):
        return [tmp.verts.new(p) for p in
                ((cx - hx, y, cz - hz), (cx + hx, y, cz - hz),
                 (cx + hx, y, cz + hz), (cx - hx, y, cz + hz))]

    ob, of = ring(ox, oz, y_back), ring(ox, oz, y_front)
    ib, i_f = ring(ix, iz, y_back), ring(ix, iz, y_front)
    for i in range(4):
        j = (i + 1) % 4
        tmp.faces.new((of[i], of[j], i_f[j], i_f[i]))   # front ring
        tmp.faces.new((ob[i], ob[j], of[j], of[i]))     # outer wall
        tmp.faces.new((i_f[i], i_f[j], ib[j], ib[i]))   # inner reveal
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    # Make sure the front ring faces the viewer side (direction of y_front)
    want = -1.0 if y_front < y_back else 1.0
    probe = tmp.faces[0]
    if probe.normal.y * want < 0:
        bmesh.ops.reverse_faces(tmp, faces=tmp.faces)
    for f in tmp.faces:
        f.material_index = mat
    _merge(bm, tmp)


def add_ellipsoid(bm, center, rx, ry, rz, mat=0, u=12, v=8):
    tmp = bmesh.new()
    bmesh.ops.create_uvsphere(tmp, u_segments=u, v_segments=v, radius=1.0)
    for vt in tmp.verts:
        vt.co = Vector((vt.co.x * rx + center[0], vt.co.y * ry + center[1],
                        vt.co.z * rz + center[2]))
    for f in tmp.faces:
        f.material_index = mat
    _merge(bm, tmp)


def _prism(bm, pts, axis, a0, a1, mat):
    """Extrude a closed polygon along `axis` ('x' polygon is in (y, z); 'z' polygon is in (x, y))."""
    tmp = bmesh.new()

    def co(p, t):
        return (t, p[0], p[1]) if axis == 'x' else (p[0], p[1], t)

    a = [tmp.verts.new(co(p, a0)) for p in pts]
    b = [tmp.verts.new(co(p, a1)) for p in pts]
    n = len(pts)
    tmp.faces.new(a)
    tmp.faces.new(list(reversed(b)))
    for i in range(n):
        j = (i + 1) % n
        tmp.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    for f in tmp.faces:
        f.material_index = mat
    _merge(bm, tmp)


def add_prism_x(bm, pts_yz, x0, x1, mat=0):
    _prism(bm, pts_yz, 'x', x0, x1, mat)


def add_prism_z(bm, pts_xy, z0, z1, mat=0):
    _prism(bm, pts_xy, 'z', z0, z1, mat)


def _merge(bm, tmp):
    me = bpy.data.meshes.new("_tmp")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


# --------------------------------------------------------------------------
# Boolean cut (used for the bolt pockets in the door frame)
# --------------------------------------------------------------------------
def boolean_cut(bm, cutter_boxes, col):
    """cutter_boxes: list of (center, size). Returns a new bmesh."""
    me = bpy.data.meshes.new("_bt")
    bm.to_mesh(me)
    obj = bpy.data.objects.new("_bt", me)
    col.objects.link(obj)
    cutters = []
    for i, (c, s) in enumerate(cutter_boxes):
        cb = bmesh.new()
        add_box(cb, c, s)
        cme = bpy.data.meshes.new("_bc%d" % i)
        cb.to_mesh(cme)
        cb.free()
        co = bpy.data.objects.new("_bc%d" % i, cme)
        col.objects.link(co)
        cutters.append(co)
        mod = obj.modifiers.new("cut%d" % i, 'BOOLEAN')
        mod.operation = 'DIFFERENCE'
        mod.solver = 'EXACT'
        mod.object = co
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me_eval = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    out = bmesh.new()
    out.from_mesh(me_eval)
    for o in [obj] + cutters:
        m = o.data
        bpy.data.objects.remove(o)
        bpy.data.meshes.remove(m)
    bpy.data.meshes.remove(me_eval)
    bm.free()
    return out


# --------------------------------------------------------------------------
# Finishing: normals, UVs, origin, parenting
# --------------------------------------------------------------------------
def box_uv(bm):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for l in f.loops:
            c = l.vert.co
            if az >= ax and az >= ay:
                u, v = c.x, c.y
            elif ay >= ax:
                u, v = c.x, c.z
            else:
                u, v = c.y, c.z
            l[uv].uv = (u * UV_SCALE, v * UV_SCALE)


def finalize(name, bm, col, mats, origin=(0, 0, 0), parent=None,
             recalc=True, uv='box'):
    """Turn a bmesh built in root space into an object whose origin sits at
    `origin` (root-space coordinates). World position is preserved."""
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    else:
        bm.normal_update()
    if uv == 'box':
        box_uv(bm)
    bmesh.ops.translate(bm, vec=-Vector(origin), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = False
    obj = bpy.data.objects.new(name, me)
    obj.location = origin
    col.objects.link(obj)
    bpy.context.view_layer.update()
    if parent:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


# --------------------------------------------------------------------------
# Reporting + export
# --------------------------------------------------------------------------
def tri_count(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def walk(obj):
    yield obj
    for c in obj.children:
        yield from walk(c)


def report(roots):
    total = 0
    rows = []
    roots = roots if isinstance(roots, (list, tuple)) else [roots]
    objs = [o for r in roots for o in walk(r)]
    for o in objs:
        if o.type == 'MESH':
            t = tri_count(o)
            total += t
            d = o.dimensions
            rows.append((o.name, t, tuple(round(x, 3) for x in d),
                         [m.name for m in o.data.materials]))
        else:
            rows.append((o.name, 0, None, []))
    return total, rows


def export_glb(roots, path):
    """roots: top-level objects of the asset (children are included)."""
    roots = roots if isinstance(roots, (list, tuple)) else [roots]
    bpy.ops.object.select_all(action='DESELECT')
    for r in roots:
        for o in walk(r):
            o.select_set(True)
    bpy.context.view_layer.objects.active = roots[0]
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    kw = dict(filepath=path, export_format='GLB', use_selection=True,
              export_apply=True, export_yup=True, export_materials='EXPORT',
              export_cameras=False, export_lights=False, export_normals=True,
              export_texcoords=True, export_extras=False,
              export_image_format='AUTO')
    if 'export_draco_mesh_compression_enable' in props:
        kw['export_draco_mesh_compression_enable'] = False
    if 'export_animation_mode' in props:
        kw['export_animation_mode'] = 'NLA_TRACKS'
    kw = {k: v for k, v in kw.items() if k in props}
    bpy.ops.export_scene.gltf(**kw)
