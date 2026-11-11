# The Auction - asset kit

Procedural blockout (primitives, flat-shaded, PBR materials, no textures). Metres, Y-up.
Regenerate/modify: `pip install trimesh numpy && python build_assets.py` (writes ./out).
The Godot assets live in `res://assets/balance_scale/`. The assembled scenes are in `res://Levels/Balance Scale/`.

| File | Origin | Notes |
|---|---|---|
| auction_chamber.glb | floor centre | 10x10x4.5 m interior; `-col` nodes -> auto static collision; Spot housings/warning cages are meshes only, add lights yourself |
| auction_table.glb | floor centre | top surface y=0.80, 2.8 m square; BidScreen_E/S/W/N are UV'd quads (SubViewport texture); players at +X, +Z, -X, -Z |
| player_chair.glb | floor under seat | faces -X; rotate about Y per seat. Place seat centre at 1.9 m from table centre |
| acid_pot.glb | pot bottom-centre | place at (+-1.9, 2.2, 0) / (0, 2.2, +-1.9); glass y 0.06-1.0; MaxLine ring at y=0.86 |
| acid_liquid.glb | liquid bottom (0,0,0) | height 0.8 == MAX line; scale.y = fill (1.175 = brimming) |
| acid_stream.glb | top of stream | hangs down 1 m; scale.y to length |
| pipes_feed.glb | same as pot | rises to y=1.9 then runs +X 1.2 m; chamber ring main is at 3.1 m from centre, so rotate with the pot |
| valve.glb | pipe centreline | put at pot origin + (0, 1.6, 0); rotate ValveWheel about Y |
| release_mechanism.glb | same as pot | Hatch hinge at x=-0.34 (rotation.z = -90deg opens), LatchBolt slides +X |
| round_display.glb | centre of back face | 3.2x1.3 m; Screen quad 3.0x1.1 UV 0-1; e.g. N wall at (0, 2.6, -4.8) |
| acid_liquid.gdshader / acid_pot.gd | - | glow shader and fill/pour/overflow/drain controller with particle FX |

Pot scene layout: `AcidPot.tscn` instances the pot, liquid, stream, release mechanism, pipes, and valve. `AuctionChamber.tscn` places the four seats and overhead pots around the table.
