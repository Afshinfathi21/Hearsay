# Psychological Survival: Original 3D Asset Pack

Status: **Phases 1-5 complete** (Phase 5 = material library + props), plus the **GridMap room MeshLibrary**
(requested before Phase 6). Phase 6 (final export pass and import verification) is not started.

## Folder layout

```
Doors/        door_standard.glb / .blend      frame + hinged panel + bolts + collision + "Door_Open" clip
Monitors/     door_monitor.glb  / .blend      housing + screen + 2x 7-segment digits + lamp + 4 pips
Environment/  9 room-kit modules (.glb) + environment_kit.blend + alignment_test.blend
              room_grid/  room_library.meshlib (81 full rooms for a GridMap) + room_variants.glb (its source)
Characters/   character_base.glb / .blend   rigged humanoid + clothing variants
Materials/    14 Godot materials (.tres) + Textures/ (procedural, tileable PBR maps)
Props/        9 optional props (.glb) + props_kit.blend
godot/        door_monitor.gd, door_standard.gd, room_builder.gd, player_character.gd,
              first_person_player.gd, material_library.gd, apply_material_library.gd,
              build_materials.gd, room_grid.gd, room_grid_demo.gd,
              build_room_meshlibrary.gd                          drop-in scripts
godot_test_project/                               headless test scripts used for verification (asset folders are
                                                  not duplicated here: copy Doors/ Monitors/ Environment/ Characters/
                                                  Props/ Materials/ in, then run godot --headless --import)
scripts/      common.py, door_parts.py, build_door.py, build_monitor.py, build_environment.py,
              build_alignment_test.py, build_character.py, build_props.py, make_textures.py,
              build_room_variants.py, render_room_grid.py, blender_pbr.py, render_preview.py, render_character.py, render_props.py, verify_glb.py
previews/     preview_hero/open/monitor.png (Phase 2), preview_rooms_interior/overview.png (Phase 3),
              preview_char_tpose/closeup/posetest/lineup.png (Phase 4),
              preview_swatches.png, preview_props.png, preview_rooms_textured.png (Phase 5),
              preview_room_grid.png (GridMap layout)
```

Rebuild: `blender -b --python scripts/build_door.py`, `build_monitor.py`, `build_environment.py`;
alignment test: `... build_alignment_test.py -- check`
(Blender 4.0+). All dimensions are constants at the top of each script.

## Conventions (from the Phase 1 style guide)

* 1 Blender unit = 1 m, Z-up while authoring; export is glTF Y-up. Assets are authored facing
  Blender -Y, which becomes **+Z in Godot** (Godot's model-front convention).
* No root empties: Godot wraps every imported GLB in its own root node named after the file.
* Box-mapped UVs at a fixed density (1 UV = 4 m, i.e. 256 px/m on a 1024 px texture).
* Collision uses Godot import hints in the node name: `-colonly` (trimesh) and `-convcolonly`
  (convex). The suffix is stripped on import and a StaticBody3D is generated.

## Door: `Doors/door_standard.glb`

| Node | Role | Origin / pivot |
|---|---|---|
| `Door_Frame` | static frame, trim, hinge leaves, gaskets | bottom-centre of opening, wall mid-plane |
| `Door_Frame_Col` (`-colonly`) | frame collision (jambs + header) | same as frame |
| `Door_Status_Light_Front/Back` | frame-mounted status lights (static) | light centre |
| `Door_Panel` | moving steel panel | **hinge axis**, floor level, at x=-0.67, y=+0.05 (Blender) |
| `Door_Panel_Col` (`-convcolonly`) | panel collision | follows panel |
| `Door_Bolt_A/B` | deadbolts, slide along panel-local X | bolt centre |
| `AnimationPlayer` | clip `Door_Open` (1.67 s): bolts retract, panel swings 100 deg | |

| Dimension | Value |
|---|---|
| Wall cutout the frame fills | 1.60 x 2.30 m (frame depth 0.30 m = wall thickness) |
| Clear opening | 1.40 x 2.20 m |
| Frame incl. surround trim | 1.72 x 2.36 m, 0.33 m deep |
| Panel | 1.355 x 0.10 x 2.18 m |
| Swing | toward Blender +Y = **Godot -Z**, 100 deg about the panel's Y axis |

Materials: `M_Steel_Dark_Brushed` (frame, panel, bolts, trim), `M_Polymer_Rubber` (gaskets, door
sweep, lock cylinder), `M_Paint_Worn` (panel stripe), `M_Emissive_Light_Amber` (status lights).

Triangles: frame 420, panel 484, bolts 2x44, lights 2x12, collision 48 = **1,064** (1,016 visual).

## Monitor: `Monitors/door_monitor.glb`

Origin = centre of the back plate; front faces Blender -Y (Godot +Z). Housing 1.20 x 0.45 m,
0.186 m deep including bolt heads. Mount above a door at Godot **(0, 2.625, +0.15)**
(front wall face); for the rear side use (0, 2.625, -0.15) rotated 180 deg about Y.

| Node | Material | Notes |
|---|---|---|
| `Mon_Housing` | `M_Steel_Dark_Brushed`, `M_Paint_Worn` | bezel, bolts, tick marks, rules |
| `Mon_Screen` | `M_Emissive_Screen` | dark glass, faint amber backlight; clean 0-1 UVs for a SubViewport/UI texture |
| `Mon_Digit_Tens/Units` > `Mon_Seg_<Digit>_<A-G>` | `M_Digit_Amber` | 14 segment meshes; no baked numbers |
| `Mon_Status_Lamp` | `M_Emissive_Light_Amber` | amber = normal, red = locked |
| `Mon_Pip_1..4` | `M_Emissive_Light_White` | one per capacity slot |

Triangles: housing 264, screen 2, segments 14x20, lamp 12, pips 4x12 = **606**. No collision needed
(protrudes 0.19 m, above head height).

## Room kit: `Environment/*.glb`

Grid: **4.0 m cell pitch**, wall centre-lines on the grid lines, 3.0 m interior height, 0.30 m walls.
Straight walls are 3.70 m and posts are 0.30 m, so wall + post = 4.00 m with no overlap. All walls are
authored along X; rotate 90 deg about Y for the other axis. Every module is its own file.

| File | Origin | Size (m) | Tris (visual / +collision) | Collision hint |
|---|---|---|---|---|
| `env_floor_4m` | cell centre, top surface at y=0 | 4.0 x 4.0 x 0.2 (below floor) | 44 / 56 | convex box |
| `env_ceiling_4m` | cell centre, **underside** (place at y=3.0) | 4.0 x 4.0 x 0.3 (above) | 44 / 56 | convex box |
| `env_wall_straight` | bottom centre of the cell-edge midpoint | 3.70 x 0.30 x 3.0 | 132 / 144 | convex box |
| `env_wall_post` | bottom centre, on the grid intersection | 0.30 x 0.30 x 3.0 | 132 / 144 | convex box |
| `env_wall_doorway` | as straight wall; 1.60 x 2.30 cutout centred | 3.70 x 0.30 x 3.0 | 308 / 344 | trimesh (3 boxes) |
| `env_door_frame` | bottom centre of the opening | 1.72 x 0.33 x 2.36 (incl. trim) | 420 / 456 | trimesh |
| `env_light_ceiling` | mount point on the ceiling underside | 0.90 x 0.28 x 0.054 | 56 | none |
| `env_wall_panel` (optional) | centre of back plate | 1.0 x 0.026 x 1.2 | 180 | none |
| `env_grille_wall` (optional) | centre of back plate | 0.60 x 0.04 x 0.40 | 108 | none |

* **Corners:** a single post at each grid intersection covers L, T and X junctions, so there is no separate
  corner wall piece. This avoids mitred corners and keeps the wall pieces identical.
* **Look:** the lowest metre of every wall/post is `M_Concrete_Painted`, the rest `M_Concrete_Rough`, with
  chamfered 1 m panel joints (formwork seams) that line up across walls, posts and the doorway wall.
  Floors and ceilings are `M_Concrete_Painted`. The door frame uses steel/rubber like the door asset;
  `env_door_frame` is the same geometry as the frame inside `door_standard.glb` (built by `door_parts.py`)
  for open doorways without a door.
* **Light fixture:** `M_Steel_Dark_Brushed` housing + `M_Emissive_Light_White` lens. The GLB has no light
  source; add an OmniLight3D / SpotLight3D under it in Godot.
* UVs are box-mapped at 1 UV = 4 m (256 px/m on a 1024 px texture), so a tileable texture repeats once per cell.

### Alignment test (two rooms, one door, two monitors, two props)

`scripts/build_alignment_test.py -- check` imports the exported GLBs, places them on the grid and checks
(14/14 pass): floors and ceilings share edges with tops/undersides at y=0 / y=3.0; every wall line is
continuous post-to-post with zero gaps (y=0, y=4, x=0, x=4, x=8); no structural modules overlap
(136 pairs); the doorway cutout measured in the mesh (1.600 x 2.300) equals the frame body; the frame is
centred in the doorway; the monitor clears the frame trim by 4 cm and sits on the wall face. The checks use
bounding boxes, which is exact here because every piece is made of boxes.

### Procedural assembly: `godot/room_builder.gd`

`RoomBuilder.build(cells, doorways)` takes grid cells and `[front_cell, back_cell]` doorway pairs and spawns
floors, ceilings, lights, walls, posts, and for each doorway a doorway wall + door + front/rear monitors.
Verified headless in Godot 4.7 with two rooms and one door: global mesh bounds were exactly
x -0.15..8.15, y -0.2..3.3, z -0.15..4.15, with the door at (4, 0, 2) and its front facing the first cell.

## Character: `Characters/character_base.glb`

A neutral 1.75 m adult in a **T-pose** (Godot's humanoid rest pose), faces Blender -Y = Godot +Z, left = +X.
Built procedurally from lofted rings (`scripts/build_character.py`), so clothing is the body profile plus an
offset and proportions are easy to change. Eye line at 1.65 m, head 0.237 m (about 7.4 heads tall).

**Skeleton:** 23 bones named exactly as Godot's `SkeletonProfileHumanoid`: Root, Hips, Spine, Chest,
UpperChest, Neck, Head, and for each side Shoulder, UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Toes.
23 of the profile's 56 bones match by name; the rest (fingers, eyes, jaw) are intentionally absent.
In the Godot import dialog set Skeleton3D > Bone Map to a new BoneMap using `SkeletonProfileHumanoid`;
the names map automatically, which lets you retarget animation libraries onto it.

**Skinning:** 8 skinned meshes share one skin. Weights are computed from distance to bone segments with
region gates (the armpit follows the spine, not the arm; the head is rigid above the jaw). Every vertex has at most 4
influences and weights sum to 1.0. They are procedural, not hand-painted, so expect to touch up
shoulders if you see pinching with extreme animations.

| Mesh | Material | Tris | Notes |
|---|---|---|---|
| `Char_Body` | `M_Char_Skin` | 1,622 | head, neck, hands (the only visible skin) |
| `Char_Eyes` | `M_Char_Eye` | 240 | |
| `Char_Top_Jacket` | `M_Char_Cloth_Top` | 1,316 | silhouette A: fitted, zip, pocket flaps |
| `Char_Top_Hoodie` | `M_Char_Cloth_Top` | 1,672 | silhouette B: baggier, kangaroo pocket, hood bunched at the neck |
| `Char_Trousers` | `M_Char_Cloth_Pants` | 1,094 | |
| `Char_Boots` | `M_Char_Boots` | 712 | |
| `Char_Hair` | `M_Char_Hair` | 218 | silhouette: short hair |
| `Char_Beanie` | `M_Char_Cloth_Accent` | 338 | silhouette: knit cap with folded cuff |

Default outfit (jacket + hair) = **5,202 triangles**; all variants in the file = 7,212. Budget was 8-12k, so there is
headroom for a better head or extra detail later.

**Variants:** the GLB contains every variant at once. `player_character.gd` shows one top and one headwear and
tints materials from 4 player palettes (amber, steel blue, olive, bone), so players differ by colour *and*
silhouette. Without the script everything is visible.

**First-person separation:** movement, collision (1.8 m capsule, 0.35 m radius) and the Camera3D (1.65 m) live on a
`CharacterBody3D`; the character is only a child model (turn it 180 degrees about Y). `set_local_player(camera)` puts
the meshes on visual layer 2 and removes that bit from the local camera's `cull_mask`, so you never see your own
body but others do, and it still casts a shadow. `first_person_player.gd` is a working example.

**Limits:** no finger/face rig; no animation clips (animations come from retargeting a library or your own);
hidden body parts (torso, arms, legs under clothes) are not modelled, so a short-sleeve or shorts outfit needs
a body mesh added; UVs are temporary box-mapping and the materials are flat colour until Phase 5; fabric folds are
modelled as soft creases at elbows, knees, hem and cuffs, with no normal-mapped detail yet. Verified in Blender by posing
the imported GLB (relaxed, walk, crouch) and in Godot 4.7 headless; not yet tested with a retargeted animation library.

## Material library: `Materials/`

All textures are generated by `scripts/make_textures.py` (numpy + FFT noise), so they are original, seamlessly
tileable, and free to use. **1 UV unit = 4 m**, so a 1024 px map is 256 px/m at `uv1_scale = 1`. Maps: albedo (sRGB),
**ORM** (R = ambient occlusion, G = roughness, B = metallic, Godot's native packed layout) and a normal map in the
OpenGL convention (green up) that Godot expects. The `.tres` files are `ORMMaterial3D` unless noted.

| Material (name = the name inside the GLBs) | Maps | Look and values |
|---|---|---|
| `M_Concrete_Rough` | 1024 albedo/ORM/normal | cold grey, mottled, pores; roughness ~0.9, metallic 0 |
| `M_Concrete_Painted` | 1024 | slate paint with orange-peel grain, ~3% chipped to bare concrete; roughness ~0.66 |
| `M_Steel_Dark_Brushed` | 1024 | horizontal brushing, a few scratches; roughness ~0.45, metallic ~0.65 |
| `M_Paint_Worn` | 1024 | off-white paint, chips expose dark steel (roughness 0.45, metallic 0.6 only in the chips) |
| `M_Polymer_Rubber` | 512, `uv1_scale` 2 | near-black fine grain; roughness ~0.85 |
| `M_Glass_Frosted` (StandardMaterial3D) | 512 normal | alpha 0.55, roughness 0.55, fine grain |
| `M_Emissive_Screen` (Standard) | 256 emission | dark glass, amber backlight with scanlines and vignette |
| `M_Digit_Amber`, `M_Emissive_Light_Amber/White/Red` (Standard) | none | emission energy 3.0 |
| `M_Char_Cloth_Top/Pants/Accent` | 512 weave, `uv1_scale` 20 | neutral plain weave, tinted with `albedo_color` per player |

The texture set is 24 MB of PNG (Godot compresses on import). Skin, boots, hair and eyes stay flat colour.

**Using it:** copy `Materials/` (including `Textures/`) to `res://Materials/`, then either
1. set `apply_material_library.gd` as the **Import Script** of each `.glb` (Import dock > Advanced > Import Script): the
   textured materials are baked in by name at import (verified on all 21 GLBs: e.g. 22 surfaces on the monitor,
   9 on the door), or
2. call `MaterialLibrary.apply(instance)` at runtime (non-destructive surface overrides).

Tuning: normal strength is baked into the maps (constants in `make_textures.py`; the first version was too heavy and
was halved for the "subtle imperfections" brief). `normal_scale` on a material scales it further. Re-run
`build_materials.gd` to regenerate every `.tres`. `ORMMaterial3D` takes roughness and metallic straight from the
ORM texture (there are no multipliers), which is how I remember Godot's shader generation; I could not render in
Godot here, so please check that the steel looks metallic in your first lit scene.

## Props: `Props/*.glb` (optional)

Wall props have their origin at the centre of the back plate and face -Y (Godot +Z), so place them back-to-wall. Floor
markings are 3 mm thick decals (no collision); the ceiling vent's origin is on the ceiling underside.

| File | Size (m) | Tris | Parts / notes |
|---|---|---|---|
| `prop_camera_wall` | base 0.12 x 0.11 x 0.12, head reaches 0.37 out | 420 | `Prop_Camera_Head` pivots on its swivel axis (rotate Y in Godot to pan); red LED |
| `prop_emergency_light` | 0.22 x 0.10 x 0.14 | 624 | caged; `_Bulb` (red emissive) and `_Dome` (frosted glass) are separate so you can recolour/blink |
| `prop_number_plate` | 0.34 x 0.02 x 0.14 | 168 | `Anchor_Label` is the front-face point for a `Label3D` with the room number |
| `prop_electrical_panel` | 0.60 x 0.14 x 0.80 (+ conduit to 1.3 tall) | 464 | `_Door` hinged at its left edge (origin on the hinge); breaker rows inside; convex collision |
| `prop_ceiling_vent` | 0.60 x 0.60 x 0.03 | 284 | tilted louvres over a dark backing |
| `prop_floor_marking_hazard/arrow/line` | 1.0x0.3 / 0.3x0.7 / 0.95x0.08 | 136 / 24 / 48 | arrow points toward Godot +Z |
| `prop_speaker_wall` | 0.20 x 0.17 x 0.32 | 388 | bracket + grilled cabinet |

Verified in Godot 4.7 headless: all props import, library materials are applied (glass imports as alpha), the panel gets
its collision body, and the camera pivot and label anchor sit where documented. The two-room test scene
(`preview_rooms_textured.png`) places eight of them in context with the textured materials.

## Full-room MeshLibrary for GridMap: `Environment/room_grid/`

`room_library.meshlib` holds **81 complete rooms**, one per GridMap cell. A cell is one 4 x 4 m room: floor, ceiling,
light fixture, four corner posts and four sides. Each side is one of **W**all, **D**oor (doorway wall + door frame) or
**O**pen (no geometry). There is one item per combination: `Room_<N><E><S><W>`, e.g. `Room_WWWW` (closed box),
`Room_WDWW` (door on the east side), `Room_OOOO` (just floor, ceiling, light and four corner columns).
Compass: N = -Z, E = +X, S = +Z, W = -X. Item id = `((N*3+E)*3+S)*3+W` with W=0, D=1, O=2.

| | |
|---|---|
| GridMap settings | cell size **4 x 3.5 x 4**, Cell Center X and Z **on**, Y **off** (`RoomGrid.setup(gridmap)` does this) |
| Per item | 672-3,584 triangles (average 1,819; closed room 1,200), textured library materials, collision boxes |
| Collision | floor, ceiling, 4 posts, and for each wall/doorway the wall blocks (+ frame jambs); 13 shared `BoxShape3D`s |
| Stacking | 3.5 m cells: an upper floor slab starts exactly where the lower ceiling slab ends (verified, no overlap) |

**The one rule: a shared edge is drawn by exactly ONE of the two cells; the other uses Open on that side.** Two
neighbouring cells that both carry a wall (or a door) would double it, and a solid wall next to a doorway would seal
it. `RoomGrid.place_rooms()` applies the rule for you:

```gdscript
var gm := GridMap.new(); add_child(gm)
RoomGrid.setup(gm)
var A := Vector2i(0, 0); var B := Vector2i(1, 0); var C := Vector2i(1, 1)
var cells: Array[Vector2i] = [A, B, C]
RoomGrid.place_rooms(gm, cells, [
    {"a": A, "b": B, "type": RoomGrid.Side.DOOR},   # doorway owned by A, door front faces into A
    {"a": B, "b": C, "type": RoomGrid.Side.OPEN}])  # no wall: B and C become one long room
RoomGrid.spawn_doors(gm, self, load("res://Doors/door_standard.glb"), load("res://Monitors/door_monitor.glb"))
RoomGrid.add_lights(gm, self)
```

Neighbours with no link get a plain wall (drawn by the cell with the smaller x/z); edges toward empty cells are walls.
Join several cells with OPEN links to make a bigger room; the corner posts remain as columns. `room_grid_demo.gd` is
this example as a runnable script. To paint by hand in the editor: add a GridMap, load the `.meshlib`, set the cell
size and centring above, and pick items by name (mind the rule).

What a GridMap cannot hold is handled by helpers: **doors** are animated scenes, so `spawn_doors()` instances
`door_standard.glb` at every Door side (its own frame is removed because the doorway frame is already in the room mesh;
status lights are kept) plus a front and a rear monitor; **lights** are not meshes, so `add_lights()` adds one OmniLight3D
per room under the fixture. Props (cameras, panels, plates, markings) are scenes you place yourself.

**Verified in Godot 4.7 (headless):** the library builds with 81 items; for a 4-room layout the chosen items, the
one-cell-per-edge rule (door edge: 1, plain wall: 1, open link: 0), the combined bounds (x -0.15..12.15, z -0.15..8.15,
y -0.2..3.3), and physics rays (west wall hit; open doorway passes through and stops at the far wall; closed door blocks
at its panel; frame jamb, floor, ceiling and the open-link passage all behave) all match. The item choice was
cross-checked in a second implementation (Python) and agreed.

**Notes:** the library stores meshes inline (8 MB) but references materials externally, so keep `Materials/` at
`res://Materials/`. Corner posts shared by neighbouring rooms are duplicated, identical geometry (invisible in Godot;
it only shows as black squares in a Cycles render). No navigation mesh is baked: bake after placing the rooms.
Rebuild the library with `build_room_variants.py` (Blender) then `build_room_meshlibrary.gd` (Godot).

## Godot setup

1. Copy the `.glb` files and `godot/*.gd` into your project; Godot imports the GLBs automatically.
2. Right-click a GLB > **New Inherited Scene**; attach `door_standard.gd` / `door_monitor.gd` to the root; save as `.tscn`.
3. Doors: `open()`, `close()`, `set_locked(bool)`. Monitor: `show_number(n)`, `set_capacity(n)`, `set_locked(bool)`.
4. Emissive materials import at strength 1.0; the scripts raise it to 3.0 at runtime. Enable Glow in
   your WorldEnvironment for the screen look.
5. The panel collider is a StaticBody3D riding on the moving mesh. That works for prototyping; for
   robust player-vs-door collisions switch it to an `AnimatableBody3D` in the inherited scene.

## Export settings (Blender 4.0.2 glTF exporter)

GLB; +Y Up; Apply Modifiers on; materials exported; normals + UVs on, tangents off (no normal maps
yet); cameras/lights off; Draco off; animations from NLA tracks (clip name = track name).

## Known limits at this stage

* Materials are flat PBR values from the style-guide palette. Textures (concrete grain, brushed
  steel, wear) arrive with the shared material library in Phase 5, using the existing UVs.
* Phase 1 listed `M_Steel_Dark_Brushed` as #2A2E32 / metallic 1.0. Pure dark metal has no diffuse
  and can crush to black where there is little to reflect, so as a readability hedge it is now #4B5258 / metallic 0.65 / roughness 0.45. The digits also got
  their own material, `M_Digit_Amber`, so they can change colour independently of the lamps.
* Verified in Godot 4.7-stable headless: import, node tree, collision generation, animation, scripts, room builder, character skeleton/skin/variants.
  Not yet verified visually in the Godot renderer (previews are Blender/Cycles renders of the exported GLBs).
