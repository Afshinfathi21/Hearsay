"""Build the library's textured materials inside Blender (for preview renders only).
The shipped materials are the Godot .tres files; this mirrors them so previews match."""
import os
import bpy

TEX = "/home/claude/asset_pack/Materials/Textures/"
# material name -> (texture set, uv scale)
LIB = {
    "M_Concrete_Rough": ("concrete_rough", 1.0),
    "M_Concrete_Painted": ("concrete_painted", 1.0),
    "M_Steel_Dark_Brushed": ("steel_brushed", 1.0),
    "M_Paint_Worn": ("paint_worn", 1.0),
    "M_Polymer_Rubber": ("rubber", 2.0),
}
_cache = {}


def pbr(name):
    if name in _cache:
        return _cache[name]
    set_name, scale = LIB[name]
    m = bpy.data.materials.new(name + "_tex")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, 1)
    nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])

    def img(suffix, cs):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(TEX + "%s_%s.png" % (set_name, suffix))
        n.image.colorspace_settings.name = cs
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n

    a = img("albedo", "sRGB")
    nt.links.new(a.outputs["Color"], bsdf.inputs["Base Color"])
    o = img("orm", "Non-Color")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(o.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nrm = img("normal", "Non-Color")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nrm.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    _cache[name] = m
    return m


def apply_library(objs):
    """Swap flat materials for textured ones, by name (suffixes like .001 ignored)."""
    n = 0
    for o in objs:
        if o.type != 'MESH':
            continue
        for i, slot in enumerate(o.material_slots):
            if slot.material is None:
                continue
            base = slot.material.name.split(".")[0]
            if base in LIB:
                o.data.materials[i] = pbr(base)
                n += 1
    return n
