"""Verify every exported slice .glb against docs/v2/ASSET_SPEC_V2.md (§2, §16, §17) + the slice
contract it inherits (docs/ASSET_SPEC.md §4-§6: names, hierarchy, pivots, sizes, budgets, collision).

Run:  cd winter-survival/blender && python3 verify_assets.py      (exit code 0 = ALL OK)
Prints one line per asset (`OK name tris=.. surfaces=.. dims=.. objects=[..]` or `FAIL name: reason`) and
ends with `ALL OK` or `N FAILURES`.

v2 checks on top of the slice ones:
  * front = -Y Blender (+Z Godot): front anchors (Muzzle, BreathAnchor, DoorAnchor, StoveAnchor, TextTop, ...)
    at y < 0; the stone_axe blade toward -Y;
  * glTF level: every primitive of a mesh whose material is palette_vcol carries COLOR_0; <= 2 primitives
    (surfaces) per mesh; only palette_vcol + the named exception materials; no TEXCOORD, no images;
    no '.' in any node/mesh/material name (no `.001`); every COLOR_0 value, as Godot stores it (RGBA8
    linear, truncated), is exactly the nearest 8-bit linear value of a palette colour (white on exception
    primitives) -- see lib/palette.py GODOT_BIAS;
  * re-import: exactly one corner colour attribute on every mesh that uses palette_vcol; one colour per
    face; palette_vcol faces carry a palette colour (+-1/255 of the stored value); exception faces white;
  * cabin <= 12 surfaces (cutaway groups + window panes).
v2.1 checks (milestone G1, docs/research/05_graficos_arte.md §4.5/§4.6):
  * COLOR_0 is VEC4 on every primitive: RGB = palette (above), A = baked AO in [0, 1]; per primitive the most
    open corner >= 0.5 (no part baked black / buried); per asset min <= 0.9 (AO present) and 95th percentile
    >= 0.85 (open surfaces stay open); every primitive carries NORMAL (smooth shading + custom normals are
    allowed, the "all flat" rule of v2 is gone);
  * snow may sink into the ground: grounded assets have their lowest vertex in [-0.25, +0.02] m;
  * v2.1 triangle budgets per asset (HD assets: no slack) and the "typical clearing view" of doc 05 §4.5:
    instances of TYPICAL_VIEW x tris + VIEW_RESERVE (zombies, kit houses, terrain) <= 270 k.
M3 checks (ASSET_SPEC_V2 "M3"):
  * assets in sub-folders (vegetation/, props/, poi/) are named by their path (`vegetation/pine_d`);
  * MultiMesh rule (§13, `mm=`): exactly ONE object (the mesh `Tree` / `Bush` / `Rock` / `Snow` / `Log` / `Icicles`),
    no parent / children / empties / Col*, ONE surface, origin at the base centre (bbox centre within 25 % of its
    size), collision-proxy extras (family, col, col_center, col_size, height, radius, choppable) consistent with the
    geometry and with <folder>/manifest.json;
  * v2 cutaway structure (§8.4, `poi=True`): every Walls<k>_<dir> has its _Stub with the same outline (same extent
    along the facade, inside the full wall in plan), cut_group / floor props on every group, floor_z on Floor<k>,
    Door_n (kind, exterior, cut_group), Window_n (material window only, boarded, cut_group), Spawn_* (pure yaw, kind,
    table on containers), convex closed Col* (6-8 vertices, ramps allowed), exact boxes where a table is given;
  * typical FOREST view (M3 streaming, default camera): instances x tris + reserve <= 270 k;
  * no visible BACK faces (M3 assets + the HD clearing props): orthographic rays from the game camera directions
    must not first hit a back face (open ends, flipped / folded faces, coplanar overlaps) -- backface_problems().
Assets marked R180 were authored in the slice convention and rotated 180 degrees about Z by lib.lowpoly
(new_scene(authored_front="+Y")); their slice pivots/collision boxes below are rotated the same way here.
"""
import json
import math
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import palette  # noqa: E402

PIVOT_TOL = 0.03
DIM_TOL = 0.10
COL_TOL = 0.02
BUDGET_SLACK = 1.2               # v2 (unchanged) assets; v2.1 HD assets (hd=True) get no slack
MAX_SURFACES_PER_MESH = 2
SINK_TOL = 0.25                  # snow mounds / drifts may sink this far below z = 0 (v2.1)
AO_ASSET_MIN = 0.9               # the most occluded corner of an asset
AO_ASSET_P95 = 0.85              # 95th percentile of all corners (open surfaces stay open)
AO_PRIM_MAX = 0.5                # the most open corner of every primitive
# doc 05 §4.5: a typical clearing view (instances on screen + in the shadow range at the default camera)
VIEW_BUDGET = 270000
VIEW_RESERVE = {"zombies (30 x 2 000)": 60000, "kit houses (2 x 10 000)": 20000, "terrain": 30000}
TYPICAL_VIEW = {
    "cabin": 1, "a_frame_cabin": 1, "pickup_truck": 1, "pine_a": 20, "pine_b": 12, "pine_c": 8, "dead_tree": 10,
    "stump": 4, "rock_a": 6, "rock_b": 3, "rock_c": 3, "berry_bush": 4, "firewood": 10, "stone": 6, "fallen_log": 2,
    "campfire": 1, "signpost": 1, "fence": 6, "tent": 1, "storage_box": 1, "lantern": 1, "wood_stove": 1, "bed": 1,
    "desk": 1, "chair": 1, "shelf": 1, "clock": 1, "cabinet": 1, "wolf": 2, "deer": 2, "chars/survivor_red": 4,
}

ZERO = (0.0, 0.0, 0.0)


def a(pri, budget, pivots, parents=None, dims=None, minz=0.0, extra=None, col=None, dims_of=None, r180=False,
      max_surfaces=None, hd=False, mm=None, poi=False, bf=None):
    """mm = MultiMesh family (M3 rule set); poi = v2 cutaway structure (M3); col=None (with poi) = any Col* set
    (structural checks only)."""
    return dict(pri=pri, budget=budget, pivots=pivots, parents=parents or {}, dims=dims or {}, minz=minz,
                extra=extra or {}, col=col if col is not None else ({} if not poi else None), dims_of=dims_of or {},
                r180=r180, max_surfaces=max_surfaces, hd=hd, mm=mm, poi=poi,
                bf=bf if bf is not None else bool(mm or poi))


QUAD_PARENTS = {"Head": "Body", "Tail": "Body", "LegFL": "Body", "LegFR": "Body", "LegBL": "Body",
                "LegBR": "Body", "Muzzle": "Head"}

# slice coordinates (porch toward +Y); the cabin is R180 -> e.g. ColWallFrontL x 1.4..3.0, y -2.5..-2.32
CABIN_COL = {
    "ColFoundation": ((-3.0, -2.5, 0.0), (3.0, 2.5, 0.30)),
    "ColPorch": ((-3.0, 2.5, 0.0), (3.0, 4.5, 0.30)),
    "ColSteps": ((-1.5, 4.5, 0.0), (-0.3, 5.3, 0.30)),
    "ColWallBack": ((-3.0, -2.5, 0.30), (3.0, -2.32, 3.0)),
    "ColWallLeft": ((-3.0, -2.5, 0.30), (-2.82, 2.5, 3.0)),
    "ColWallRight": ((2.82, -2.5, 0.30), (3.0, 2.5, 3.0)),
    "ColWallFrontL": ((-3.0, 2.32, 0.30), (-1.4, 2.5, 3.0)),
    "ColWallFrontR": ((-0.4, 2.32, 0.30), (3.0, 2.5, 3.0)),
    "ColDoorTop": ((-1.4, 2.32, 2.40), (-0.4, 2.5, 3.0)),
    "ColChimney": ((-3.7, 0.25, 0.0), (-3.0, 0.95, 3.0)),
    "ColRailFrontL": ((-3.0, 4.42, 0.30), (-1.5, 4.5, 1.3)),
    "ColRailFrontR": ((-0.3, 4.42, 0.30), (3.0, 4.5, 1.3)),
    "ColRailLeft": ((-3.0, 2.5, 0.30), (-2.92, 4.5, 1.3)),
    "ColRailRight": ((2.92, 2.5, 0.30), (3.0, 4.5, 1.3)),
}

ASSETS = {
    "player": a(0, 700, {"Hips": (0, 0, 0.80), "Torso": (0, 0, 0.80), "Head": (0, 0, 1.36),
                         "BreathAnchor": (0, 0.20, 1.52), "ArmL": (-0.36, 0, 1.32), "ArmR": (0.36, 0, 1.32),
                         "ToolSocket": (0.36, 0.05, 0.80), "LegL": (-0.12, 0, 0.80), "LegR": (0.12, 0, 0.80)},
                parents={"ToolSocket": "ArmR", "BreathAnchor": "Head", "Head": "Torso", "ArmL": "Torso",
                         "ArmR": "Torso", "Torso": "Hips", "LegL": "Hips", "LegR": "Hips"},
                dims={"z": 1.80}, extra={"forward": ["BreathAnchor"]}, r180=True),
    "wolf": a(0, 600, {"Body": (0, 0, 0.55), "Head": (0, 0.45, 0.62), "Muzzle": (0, 0.93, 0.58),
                       "Tail": (0, -0.45, 0.62), "LegFL": (-0.13, 0.30, 0.42), "LegFR": (0.13, 0.30, 0.42),
                       "LegBL": (-0.13, -0.30, 0.42), "LegBR": (0.13, -0.30, 0.42)},
              parents=QUAD_PARENTS, dims={"y": 1.85, "x": 0.36}, dims_of={"Body": {"zmax": 0.75}},
              extra={"forward": ["Muzzle"]}, r180=True),
    "deer": a(1, 800, {"Body": (0, 0, 0.90), "Head": (0, 0.60, 1.00), "Muzzle": (0, 1.05, 1.35),
                       "LegFL": (-0.14, 0.42, 0.70), "LegFR": (0.14, 0.42, 0.70),
                       "LegBL": (-0.14, -0.42, 0.70), "LegBR": (0.14, -0.42, 0.70), "Tail": None},
              parents=QUAD_PARENTS, dims={"z": 1.65}, extra={"forward": ["Muzzle"]}, r180=True),
    # v2.1 HD (G1): pine 700-1 200, bare tree 1 500-2 600, rock / stump 150-700 (doc 05 §4.5)
    "pine_a": a(0, 1200, {"Tree": ZERO}, dims={"z": 7.0}, hd=True),
    "pine_b": a(0, 1200, {"Tree": ZERO}, dims={"z": 5.5}, hd=True),
    "pine_c": a(0, 1000, {"Tree": ZERO}, dims={"z": 4.0}, hd=True),
    "dead_tree": a(0, 2600, {"Tree": ZERO}, dims={"z": 4.5}, hd=True),
    "stump": a(0, 500, {"Stump": ZERO}, dims={"x": 0.6, "y": 0.6, "z": 0.45}, hd=True),
    "rock_a": a(0, 700, {"Rock": ZERO}, dims={"x": 1.2, "y": 1.0, "z": 0.7}, hd=True),
    "rock_b": a(0, 700, {"Rock": ZERO}, dims={"x": 2.2, "y": 1.8, "z": 1.2}, hd=True),
    "rock_c": a(1, 400, {"Rock": ZERO}, dims={"x": 0.6, "y": 0.5, "z": 0.35}, hd=True),
    "stone": a(0, 40, {"Stone": ZERO}, dims={"x": 0.30, "y": 0.25, "z": 0.20}),
    # M3 HD (guide v2.1): same nodes / sizes, v2.1 prop budgets (no slack)
    "berry_bush": a(0, 700, {"Bush": ZERO, "Berries": ZERO}, parents={"Berries": "Bush"},
                    dims={"x": 1.0, "y": 1.0, "z": 0.55}, hd=True, bf=True),
    "firewood": a(0, 120, {"Firewood": ZERO}, dims={"x": 0.55, "y": 0.55, "z": 0.22}),
    "fallen_log": a(0, 500, {"Log": ZERO}, dims={"x": 1.6, "z": 0.40}, hd=True, bf=True),
    "campfire": a(0, 400, {"Stones": ZERO, "Logs": ZERO, "FlameAnchor": (0, 0, 0.18)},
                  dims={"x": 1.2, "y": 1.2, "z": 0.35}),
    # weapon convention (v2 §12): origin at the grip, handle +Z, useful end (blade) toward -Y
    "stone_axe": a(0, 100, {"Handle": ZERO, "Blade": ZERO}, dims={"z": 0.55}, minz=-0.05,
                   extra={"useful_end": "Blade"}),
    "torch": a(0, 80, {"Handle": ZERO, "Head": ZERO, "FlameAnchor": (0, 0, 0.54)}, dims={"z": 0.52}),
    "cabin": a(0, 24000, {"Floor": ZERO, "WallFront": ZERO, "WindowsFront": ZERO, "WallBack": ZERO,
                         "WallLeft": ZERO, "WindowsLeft": ZERO, "WallRight": ZERO, "Roof": ZERO, "Chimney": ZERO,
                         "Porch": ZERO, "DoorAnchor": (-0.9, 3.2, 0.30), "LanternSocket": (-1.6, 4.3, 2.35)},
               parents={"WindowsFront": "WallFront", "WindowsLeft": "WallLeft"},
               dims={"x": 7.1, "y": 8.2, "z": 5.3}, col=CABIN_COL,
               extra={"forward": ["DoorAnchor", "LanternSocket"], "window": ["WindowsFront", "WindowsLeft"],
                      "front_mesh": {"WallFront": "<", "WallBack": ">", "WallLeft": "x>", "WallRight": "x<",
                                     "Chimney": "x>", "Porch": "<"}},
               r180=True, max_surfaces=12, hd=True),
    "wood_stove": a(0, 250, {"Body": ZERO, "Door": ZERO, "Pipe": ZERO, "StoveAnchor": (0, 0.35, 0.45),
                             "PipeTop": (0, -0.15, 2.70)},
                    dims={"x": 0.66, "y": 0.66, "z": 2.70}, extra={"forward": ["StoveAnchor"], "ember": ["Door"]},
                    r180=True),
    # depth checked against the 0.56 cornice (the spec's own cornice is deeper than the 0.50 body)
    "cabinet": a(0, 120, {"Cabinet": ZERO}, dims={"x": 0.90, "y": 0.56, "z": 1.80}, r180=True),
    "bed": a(1, 150, {"Bed": ZERO}, dims={"x": 1.0, "y": 2.0}, r180=True),
    "desk": a(1, 150, {"Desk": ZERO}, dims={"x": 1.40, "y": 0.60}, r180=True),
    "chair": a(1, 120, {"Chair": ZERO}, dims={"x": 0.45, "y": 0.45, "z": 0.90}, r180=True),
    "shelf": a(1, 250, {"Shelf": ZERO, "Jars": ZERO}, parents={"Jars": "Shelf"}, dims={"x": 0.90, "y": 0.25},
               minz=None, extra={"front_mesh": {"Shelf": "<"}}, r180=True),
    "clock": a(1, 120, {"Clock": ZERO, "HourHand": (0, 0.07, 0), "MinuteHand": (0, 0.075, 0)},
               dims={"x": 0.36, "z": 0.36}, minz=None, extra={"forward": ["HourHand", "MinuteHand"]}, r180=True),
    "a_frame_cabin": a(1, 14000, {"Body": ZERO, "Front": ZERO, "WindowsFront": ZERO, "Deck": ZERO},
                       parents={"WindowsFront": "Front"}, dims={"x": 6.0, "y": 8.5, "z": 6.0},
                       col={"ColBody": ((-3.0, -3.5, 0.0), (3.0, 3.5, 6.0)),
                            "ColDeck": ((-2.0, 3.5, 0.0), (2.0, 5.0, 0.25))},
                       extra={"window": ["WindowsFront"], "front_mesh": {"Deck": "<", "WindowsFront": "<"}},
                       r180=True, hd=True),
    "pickup_truck": a(1, 9000, {"Body": ZERO, "Wheels": ZERO, "Snow": ZERO, "BedAnchor": (0, -1.35, 1.0)},
                      dims={"x": 2.0, "y": 5.0, "z": 1.95},
                      col={"ColChassis": ((-1.0, -2.5, 0.3), (1.0, 2.5, 1.3)),
                           "ColCab": ((-0.95, -0.2, 1.3), (0.95, 1.0, 2.0))},
                      extra={"back": ["BedAnchor"], "window": ["Body"]}, r180=True, hd=True),
    # authored directly in v2: boards point to +X, text faces -Y, text empties unrotated
    "signpost": a(1, 700, {"Post": ZERO, "BoardTop": (0, 0, 1.84), "BoardBottom": (0, 0, 1.44),
                           "TextTop": (0.28, -0.125, 1.84), "TextBottom": (0.28, -0.125, 1.44)},
                  parents={"TextTop": "BoardTop", "TextBottom": "BoardBottom"}, dims={"z": 2.2},
                  extra={"forward": ["TextTop", "TextBottom"], "tip": "BoardTop",
                         "front_mesh": {"BoardTop": "<", "BoardBottom": "<"}}, hd=True, bf=True),
    "fence": a(1, 600, {"Fence": ZERO}, dims={"x": 2.0, "z": 1.1}, hd=True, bf=True),
    "lantern": a(1, 400, {"Lantern": ZERO, "LightAnchor": (0, 0, -0.23)}, dims={"z": 0.40}, minz=-0.40,
                 extra={"maxz": 0.0, "window": ["Lantern"]}, hd=True, bf=True),
    "tent": a(2, 250, {"Tent": ZERO}, dims={"x": 2.4, "y": 2.6, "z": 1.7},
              col={"ColBack": ((-1.2, -1.3, 0.0), (1.2, -1.2, 1.7))}, r180=True),
    "storage_box": a(2, 150, {"Box": ZERO}, dims={"x": 0.8, "y": 0.6, "z": 0.6}, r180=True),
}

# ------------------------------------------------------------------------------------------------
# M3 (ASSET_SPEC_V2 "M3"): MultiMesh scatter families + POIs. dims = the built sizes (regression, +-10 %).
# Budgets (doc 05 §4.5, no slack): pine 1 200 (young 800), bare tree 2 600, bush / rock 700, snow 500, log 700,
# icicles 300, POI cabin / tower 14 000, campsite 4 000.
# ------------------------------------------------------------------------------------------------
TREE = {"Tree": ZERO}
M3_ASSETS = {
    "vegetation/pine_d": a(0, 1200, TREE, dims={"z": 9.17}, mm="pine", hd=True),
    "vegetation/pine_e": a(0, 1200, TREE, dims={"z": 7.27}, mm="pine", hd=True),
    "vegetation/pine_f": a(0, 1200, TREE, dims={"z": 6.35}, mm="pine", hd=True),
    "vegetation/pine_young": a(0, 800, TREE, dims={"z": 2.78}, mm="pine", hd=True),
    "vegetation/dead_tree_b": a(0, 2600, TREE, dims={"z": 5.77}, mm="dead_tree", hd=True),
    "vegetation/dead_tree_c": a(0, 2600, TREE, dims={"z": 3.67}, mm="dead_tree", hd=True),
    "vegetation/birch": a(1, 2600, TREE, dims={"z": 7.62}, mm="birch", hd=True),
    "vegetation/bush_a": a(0, 700, {"Bush": ZERO}, dims={"x": 1.67, "y": 1.40, "z": 0.88}, mm="bush", hd=True),
    "vegetation/bush_b": a(0, 700, {"Bush": ZERO}, dims={"x": 1.27, "y": 0.96, "z": 0.92}, mm="bush", hd=True),
    "vegetation/rock_d": a(0, 700, {"Rock": ZERO}, dims={"x": 2.69, "y": 1.85, "z": 0.70}, mm="rock", hd=True),
    "vegetation/rock_e": a(0, 700, {"Rock": ZERO}, dims={"x": 3.88, "y": 2.84, "z": 2.48}, mm="rock", hd=True),
    "vegetation/rock_f": a(0, 700, {"Rock": ZERO}, dims={"x": 1.90, "y": 1.50, "z": 0.53}, mm="rock", hd=True),
    "vegetation/snow_pile_a": a(0, 500, {"Snow": ZERO}, dims={"x": 1.90, "y": 1.63, "z": 0.59}, mm="snow", hd=True),
    "vegetation/snow_pile_b": a(0, 500, {"Snow": ZERO}, dims={"x": 3.06, "y": 2.31, "z": 0.81}, mm="snow", hd=True),
    "vegetation/snow_pile_c": a(0, 500, {"Snow": ZERO}, dims={"x": 1.13, "y": 0.86, "z": 0.34}, mm="snow", hd=True),
    "vegetation/snow_drift_4": a(0, 500, {"Snow": ZERO}, dims={"x": 4.02, "y": 1.65, "z": 0.59}, mm="snow", hd=True),
    "vegetation/fallen_log_b": a(0, 700, {"Log": ZERO}, dims={"x": 3.63, "z": 0.52}, mm="log", hd=True),
    "vegetation/fallen_log_c": a(1, 700, {"Log": ZERO}, dims={"x": 3.53, "z": 1.79}, mm="log", hd=True),
    "props/icicles": a(1, 300, {"Icicles": ZERO}, dims={"x": 2.02, "z": 0.58}, minz=None, extra={"maxz": 0.0},
                       mm="ice", hd=True),
    "poi/cabin_small": a(0, 14000, {"Floor0": ZERO, "Walls0_S": ZERO, "Walls0_N": ZERO, "Walls0_E": ZERO,
                                    "Walls0_W": ZERO, "Walls0_S_Stub": ZERO, "Walls0_N_Stub": ZERO,
                                    "Walls0_E_Stub": ZERO, "Walls0_W_Stub": ZERO, "Interior0": ZERO, "Roof": ZERO,
                                    "Door_0": (-0.48, -2.39, 0.30), "Window_0": ZERO, "Window_1": ZERO,
                                    "Window_2": ZERO, "DoorAnchor": (0.0, -3.05, 0.30), "Spawn_Stove_0": None,
                                    "Spawn_Bed_0": None, "Spawn_Container_0": None, "Spawn_Light_0": None,
                                    "Spawn_Loot_0": None, "Spawn_Zombie_0": None},
                         dims={"x": 6.70, "y": 8.06, "z": 5.00}, extra={"forward": ["DoorAnchor", "Door_0"]},
                         max_surfaces=20, hd=True, poi=True, col="poi.build_cabin_small"),
    "poi/lookout_tower": a(0, 14000, {"Floor0": ZERO, "Floor1": ZERO, "Walls1_S": ZERO, "Walls1_N": ZERO,
                                      "Walls1_E": ZERO, "Walls1_W": ZERO, "Walls1_S_Stub": ZERO, "Walls1_N_Stub": ZERO,
                                      "Walls1_E_Stub": ZERO, "Walls1_W_Stub": ZERO, "Interior1": ZERO, "Roof": ZERO,
                                      "Door_0": None, "Window_0": ZERO, "Window_1": ZERO, "Window_2": ZERO,
                                      "Window_3": ZERO, "DoorAnchor": (1.9, 0.0, 9.2), "StairFoot": (2.9, -2.85, 0.0),
                                      "ViewAnchor": (0.0, 0.0, 10.9), "Spawn_Radio_0": None, "Spawn_Loot_0": None,
                                      "Spawn_Container_0": None, "Spawn_Bed_0": None, "Spawn_Light_0": None},
                           dims={"x": 6.90, "y": 6.88, "z": 13.86}, max_surfaces=20, hd=True, poi=True),
    "poi/campsite_remains": a(0, 4000, {"Remains": ZERO, "FlameAnchor": (1.05, -0.55, 0.18),
                                        "Spawn_Container_0": (2.25, 1.25, 0.0), "Spawn_Loot_0": None,
                                        "Spawn_Loot_1": None},
                              dims={"x": 6.74, "y": 4.73, "z": 1.19}, hd=True, poi=True),
}
ASSETS.update(M3_ASSETS)
MM_NODES = {"pine": "Tree", "dead_tree": "Tree", "birch": "Tree", "bush": "Bush", "rock": "Rock", "snow": "Snow",
            "log": "Log", "ice": "Icicles"}
COL_KINDS = {"cylinder": 2, "sphere": 1, "box": 3, "none": 0}

# M3 streaming: a typical forest view at the default camera (instances on screen + shadow range) + a forest POI
FOREST_VIEW = {
    "pine_a": 8, "pine_b": 7, "pine_c": 6, "vegetation/pine_d": 6, "vegetation/pine_e": 4, "vegetation/pine_f": 6,
    "vegetation/pine_young": 8, "dead_tree": 3, "vegetation/dead_tree_b": 3, "vegetation/dead_tree_c": 2,
    "vegetation/birch": 4, "vegetation/bush_a": 8, "vegetation/bush_b": 4, "berry_bush": 3, "rock_a": 3,
    "rock_b": 2, "vegetation/rock_d": 2, "vegetation/rock_e": 1, "vegetation/rock_f": 3,
    "vegetation/snow_pile_a": 4, "vegetation/snow_pile_b": 2, "vegetation/snow_pile_c": 4,
    "vegetation/snow_drift_4": 2, "fallen_log": 1, "vegetation/fallen_log_b": 2, "vegetation/fallen_log_c": 1,
    "stump": 3, "poi/cabin_small": 1, "chars/survivor_red": 4,
}
FOREST_RESERVE = {"zombies (30 x 2 000)": 60000, "terrain": 30000, "wolves / deer": 3000}

# final (exported) XYZ Euler degrees of the only rotated empty
ROTATED = dict(export.ROTATED_SOCKETS)


def rot180(p):
    return (-p[0], -p[1], p[2])


def rot180_box(box):
    mn, mx = box
    return ((-mx[0], -mx[1], mn[2]), (-mn[0], -mn[1], mx[2]))


def final_spec(spec):
    """Expected values in final (FRONT = -Y) coordinates."""
    if not spec["r180"]:
        return spec
    s = dict(spec)
    s["pivots"] = {k: (rot180(v) if v is not None else None) for k, v in spec["pivots"].items()}
    s["col"] = {k: rot180_box(v) for k, v in spec["col"].items()}
    return s


def is_col(o):
    return export.is_col(o.name)


def world_bounds(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return mn, mx


def tris_of(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def winding_problems(o):
    """Closed components (vertices merged by position) must be consistently wound with positive volume."""
    me = o.data
    key = {}
    vid = []
    for v in me.vertices:
        k = tuple(round(c, 4) for c in v.co)
        vid.append(key.setdefault(k, len(key)))
    pos = {i: Vector(k) for k, i in key.items()}
    polys = [[vid[i] for i in p.vertices] for p in me.polygons]
    edges = {}
    for pi, p in enumerate(polys):
        for i in range(len(p)):
            e = (p[i], p[(i + 1) % len(p)])
            edges.setdefault(frozenset(e), []).append((pi, e))
    parent = list(range(len(polys)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for lst in edges.values():
        for (pa, _), (pb, _) in zip(lst, lst[1:]):
            parent[find(pa)] = find(pb)
    comps = {}
    for pi in range(len(polys)):
        comps.setdefault(find(pi), []).append(pi)
    bad = 0
    for faces in comps.values():
        fs = set(faces)
        closed = True
        consistent = True
        for lst in edges.values():
            if lst[0][0] not in fs:
                continue
            if len(lst) != 2:
                closed = False
                break
            if lst[0][1] == lst[1][1]:
                consistent = False
        if not closed:
            continue
        vol = 0.0
        for pi in faces:
            p = polys[pi]
            for i in range(1, len(p) - 1):
                vol += pos[p[0]].dot(pos[p[i]].cross(pos[p[i + 1]])) / 6.0
        if not consistent or vol < -1e-9:
            bad += 1
    return bad


def check_collision(o, box):
    problems = []
    if o.parent is not None:
        problems.append("%s has a parent" % o.name)
    pts = {tuple(round(c, 4) for c in (o.matrix_world @ v.co)) for v in o.data.vertices}
    if len(pts) not in (6, 8):
        problems.append("%s has %d unique vertices" % (o.name, len(pts)))
    planes = []
    mw = o.matrix_world
    for p in o.data.polygons:
        n = (mw.to_3x3() @ p.normal).normalized()
        d = n.dot(mw @ o.data.vertices[p.vertices[0]].co)
        if not any((n - q[0]).length < 1e-3 and abs(d - q[1]) < 1e-3 for q in planes):
            planes.append((n, d))
    if len(planes) not in (5, 6):
        problems.append("%s has %d faces" % (o.name, len(planes)))
    for n, d in planes:
        if any(n.dot(Vector(p)) - d > 1e-3 for p in pts):
            problems.append("%s is not convex/outward" % o.name)
            break
    mn = [min(p[i] for p in pts) for i in range(3)]
    mx = [max(p[i] for p in pts) for i in range(3)]
    for i in range(3):
        if abs(mn[i] - box[0][i]) > COL_TOL or abs(mx[i] - box[1][i]) > COL_TOL:
            problems.append("%s bounds %s..%s != %s..%s" % (o.name, [round(x, 3) for x in mn],
                                                              [round(x, 3) for x in mx], box[0], box[1]))
            break
    return problems


# ------------------------------------------------------------------------------------------------
# glTF JSON level (what Godot actually receives)
# ------------------------------------------------------------------------------------------------
def load_glb(path):
    """(json, BIN chunk bytes)."""
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 12)[0]
    g = json.loads(b[20:20 + n])
    off = 20 + n
    binary = b""
    if off + 8 <= len(b):
        blen = struct.unpack_from("<I", b, off)[0]
        binary = b[off + 8:off + 8 + blen]
    return g, binary


def read_accessor(g, binary, idx):
    acc = g["accessors"][idx]
    bv = g["bufferViews"][acc["bufferView"]]
    fmt, size, norm = {5126: ("f", 4, 1.0), 5121: ("B", 1, 255.0), 5123: ("H", 2, 65535.0)}[acc["componentType"]]
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    stride = bv.get("byteStride", size * ncomp)
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    out = []
    for i in range(acc["count"]):
        vals = struct.unpack_from("<%d%s" % (ncomp, fmt), binary, off + i * stride)
        out.append(tuple(v / norm for v in vals) if fmt != "f" else vals)
    return out


def gltf_problems(g, binary, godot_targets, alphas=None):
    """glTF-level contract. `alphas` (list) collects every COLOR_0 alpha for the asset-level AO check."""
    problems = []
    own_alphas = alphas is None
    alphas = [] if alphas is None else alphas
    allowed = export.allowed_materials()
    for key in ("images", "textures", "samplers"):
        if g.get(key):
            problems.append("glTF has %s" % key)
    for coll in ("nodes", "meshes", "materials"):
        for item in g.get(coll, []):
            if "." in item.get("name", ""):
                problems.append("dotted %s name %s" % (coll[:-1], item["name"]))
    mats = g.get("materials", [])
    for m in mats:
        if m.get("name") not in allowed:
            problems.append("material %s not allowed" % m.get("name"))
    surfaces = 0
    by_mesh = {}
    for nd in g["nodes"]:
        if "mesh" not in nd or export.is_col(nd["name"]):
            continue
        mesh = g["meshes"][nd["mesh"]]
        prims = mesh["primitives"]
        surfaces += len(prims)
        by_mesh[nd["name"]] = len(prims)
        if len(prims) > MAX_SURFACES_PER_MESH:
            problems.append("%s has %d surfaces (max %d)" % (nd["name"], len(prims), MAX_SURFACES_PER_MESH))
        names = [mats[p["material"]]["name"] if "material" in p else None for p in prims]
        if len(set(names)) != len(names):
            problems.append("%s has duplicated materials %s" % (nd["name"], names))
        for p, mn in zip(prims, names):
            if mn is None:
                problems.append("%s: primitive without material" % nd["name"])
            if any(k.startswith("TEXCOORD") for k in p["attributes"]):
                problems.append("%s has UVs" % nd["name"])
            if mn == palette.VCOL_MATERIAL and "COLOR_0" not in p["attributes"]:
                problems.append("%s: palette_vcol primitive without COLOR_0" % nd["name"])
            if "COLOR_1" in p["attributes"]:
                problems.append("%s has more than one colour set" % nd["name"])
            if "NORMAL" not in p["attributes"]:
                problems.append("%s: primitive without NORMAL" % nd["name"])
            if "COLOR_0" in p["attributes"]:
                acc = g["accessors"][p["attributes"]["COLOR_0"]]
                values = read_accessor(g, binary, p["attributes"]["COLOR_0"])
                if acc["type"] != "VEC4":
                    problems.append("%s: COLOR_0 is %s (v2.1: VEC4, alpha = AO)" % (nd["name"], acc["type"]))
                else:
                    al = [c[3] for c in values]
                    if min(al) < -1e-6 or max(al) > 1 + 1e-6:
                        problems.append("%s: AO alpha outside [0, 1]" % nd["name"])
                    if max(al) < AO_PRIM_MAX:
                        problems.append("%s[%s]: AO alpha max %.2f < %.2f (part baked black?)" % (
                            nd["name"], mn, max(al), AO_PRIM_MAX))
                    alphas.extend(al)
                got = {palette.godot_bytes(c) for c in values}
                want = godot_targets if mn == palette.VCOL_MATERIAL else {(255, 255, 255)}
                bad = sorted(got - want)
                if bad:
                    problems.append("%s[%s]: %d COLOR_0 value(s) off the palette as Godot stores them, e.g. %s"
                                    % (nd["name"], mn, len(bad), bad[:3]))
    if own_alphas:
        problems += ao_problems(alphas)
    return problems, surfaces


def ao_problems(alphas):
    """Asset-level AO sanity (v2.1): AO present and open surfaces open."""
    if not alphas:
        return ["no COLOR_0 alpha (AO) at all"]
    al = sorted(alphas)
    p95 = al[min(len(al) - 1, int(0.95 * len(al)))]
    out = []
    if al[0] > AO_ASSET_MIN:
        out.append("AO missing: min alpha %.2f > %.2f" % (al[0], AO_ASSET_MIN))
    if p95 < AO_ASSET_P95:
        out.append("AO too dark: 95th percentile %.2f < %.2f" % (p95, AO_ASSET_P95))
    return out


def ao_summary(g, binary):
    al = []
    for m in g.get("meshes", []):
        for p in m["primitives"]:
            if "COLOR_0" in p["attributes"] and g["accessors"][p["attributes"]["COLOR_0"]]["type"] == "VEC4":
                al += [c[3] for c in read_accessor(g, binary, p["attributes"]["COLOR_0"])]
    if not al:
        return "ao=none"
    al.sort()
    return "ao=%.2f/%.2f/%.2f" % (al[0], al[len(al) // 2], al[min(len(al) - 1, int(0.95 * len(al)))])


def glb_tris(path):
    """Triangles of every visual (non Col*) mesh node of a .glb, as instanced by its nodes."""
    g, _b = load_glb(path)
    n = 0
    for nd in g["nodes"]:
        if "mesh" not in nd or export.is_col(nd["name"]):
            continue
        for p in g["meshes"][nd["mesh"]]["primitives"]:
            if "indices" in p:
                n += g["accessors"][p["indices"]]["count"] // 3
            else:
                n += g["accessors"][p["attributes"]["POSITION"]]["count"] // 3
    return n


def reimport_targets():
    """sRGB bytes the Blender importer gives back for every palette colour (from the stored biased value)."""
    def srgb(x):
        return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055
    return {n: tuple(int(round(srgb(c) * 255)) for c in palette.vcol_rgba(n)[:3]) for n in palette.all_names()}


def colour_problems(o, allowed_bytes):
    """Every palette_vcol face: one palette colour (+-1/255 of the stored value); exception faces: white."""
    me = o.data
    uses_vcol = any(m is not None and m.name == palette.VCOL_MATERIAL for m in me.materials)
    attrs = list(me.color_attributes)
    if not uses_vcol:
        return []
    if len(attrs) != 1:
        return ["%s has %d colour attributes (want 1)" % (o.name, len(attrs))]
    attr = attrs[0]
    if attr.domain != 'CORNER' and attr.domain != 'POINT':
        return ["%s colour attribute domain %s" % (o.name, attr.domain)]
    n = len(attr.data)
    flat = [0.0] * (n * 4)
    key = "color_srgb" if hasattr(attr.data[0], "color_srgb") else "color"
    attr.data.foreach_get(key, flat)

    def col_of(i):
        c = flat[i * 4:i * 4 + 3]
        if key == "color":
            c = [(1.055 * x ** (1 / 2.4) - 0.055) if x > 0.0031308 else 12.92 * x for x in c]
        return tuple(int(round(x * 255)) for x in c)
    bad_face = bad_col = bad_exc = 0
    allowed = list(allowed_bytes.values())
    cache = {}
    for p in me.polygons:
        idx = p.loop_indices if attr.domain == 'CORNER' else [me.loops[li].vertex_index for li in p.loop_indices]
        cols = {col_of(i) for i in idx}
        if len(cols) != 1:
            bad_face += 1
            continue
        c = cols.pop()
        mat = me.materials[p.material_index]
        if mat is not None and mat.name == palette.VCOL_MATERIAL:
            if c not in cache:
                cache[c] = any(all(abs(c[k] - b[k]) <= 1 for k in range(3)) for b in allowed)
            if not cache[c]:
                bad_col += 1
        elif c != (255, 255, 255):
            bad_exc += 1
    out = []
    if bad_face:
        out.append("%d faces of %s with mixed corner colours" % (bad_face, o.name))
    if bad_col:
        out.append("%d palette_vcol faces of %s with a non-palette colour" % (bad_col, o.name))
    if bad_exc:
        out.append("%d exception-material faces of %s not white" % (bad_exc, o.name))
    return out


def front_mesh_problems(by, rules):
    """Coarse position checks of whole parts (e.g. the cabin's WallFront must be at y < 0)."""
    out = []
    for n, rule in rules.items():
        if n not in by:
            continue
        mn, mx = world_bounds([by[n]])
        c = (mn + mx) * 0.5
        ok = {"<": c.y < 0, ">": c.y > 0, "x>": c.x > 0, "x<": c.x < 0}[rule]
        if not ok:
            out.append("%s centre %s violates %s (front = -Y)" % (n, tuple(round(v, 2) for v in c), rule))
    return out


def col_shape_problems(o):
    """Closed convex hull with 6 (wedge / ramp) or 8 (box / slanted box) unique vertices, 5-6 planes, top level."""
    problems = []
    if o.parent is not None:
        problems.append("%s has a parent" % o.name)
    mw = o.matrix_world
    pts = {tuple(round(c, 4) for c in (mw @ v.co)) for v in o.data.vertices}
    if len(pts) not in (6, 8):
        problems.append("%s has %d unique vertices" % (o.name, len(pts)))
    planes = []
    for p in o.data.polygons:
        n = (mw.to_3x3() @ p.normal).normalized()
        d = n.dot(mw @ o.data.vertices[p.vertices[0]].co)
        if not any((n - q[0]).length < 1e-3 and abs(d - q[1]) < 1e-3 for q in planes):
            planes.append((n, d))
    if len(planes) not in (5, 6):
        problems.append("%s has %d faces" % (o.name, len(planes)))
    for n, d in planes:
        if any(n.dot(Vector(p)) - d > 1e-3 for p in pts):
            problems.append("%s is not convex/outward" % o.name)
            break
    if len(o.data.materials) or len(o.data.color_attributes):
        problems.append("%s has materials / colours" % o.name)
    return problems


BF_MAX_HITS = 8                 # grazing single rays at intersections are tolerated, open / inverted parts are not
BF_MAX_FRAC = 2e-5


_FACADE_N = {"N": Vector((0, 1, 0)), "S": Vector((0, -1, 0)), "E": Vector((1, 0, 0)), "W": Vector((-1, 0, 0))}


def _cut_hidden(objs, to_cam):
    """Names hidden in the cutaway seen from `to_cam` (ASSET_SPEC_V2 §8.6 / §9.3): Roof, every Walls<k>_<dir> whose
    normal faces the camera (> 0.15) with its doors / windows (cut_group), and the _Stub of every other facade."""
    facing = lambda n: _FACADE_N[n.split("_")[1]].dot(to_cam) > 0.15      # noqa: E731
    hidden = set()
    for o in objs:
        n = o.name
        if n == "Roof":
            hidden.add(n)
        elif re.match(r"^Walls\d+_[NSEW]$", n) and facing(n):
            hidden.add(n)
        elif re.match(r"^Walls\d+_[NSEW]_Stub$", n) and not facing(n):
            hidden.add(n)
    for o in objs:
        cg = o.get("cut_group") if o.name.startswith(("Door_", "Window_")) else None
        if cg and cg in hidden:
            hidden.add(o.name)
    return hidden


def _bf_hits(vis, views, ground, step_div=150):
    from mathutils.bvhtree import BVHTree
    verts, polys, owner = [], [], []
    for o in vis:
        mw = o.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in o.data.vertices]
        m3 = mw.to_3x3()
        for p in o.data.polygons:
            polys.append(tuple(base + i for i in p.vertices))
            owner.append((o.name, (m3 @ p.normal).normalized()))
    if not polys:
        return 0, {}
    tree = BVHTree.FromPolygons(verts, polys, epsilon=0.0)
    mn = Vector([min(v[i] for v in verts) for i in range(3)])
    mx = Vector([max(v[i] for v in verts) for i in range(3)])
    c = (mn + mx) / 2
    R = (mx - mn).length / 2 + 0.2
    step = max(0.035, R / step_div)
    n = int(2 * R / step)
    total, bad = 0, {}
    for d in views:
        u = d.cross(Vector((0, 0, 1))).normalized()
        w = u.cross(d).normalized()
        for i in range(n):
            for j in range(n):
                org = c - d * (R + 5) + u * (-R + i * step) + w * (-R + j * step)
                loc, _nrm, idx, _dist = tree.ray_cast(org, d, 2 * R + 10)
                if idx is None or (ground and loc.z < -0.001):
                    continue
                total += 1
                oname, fn = owner[idx]
                if fn.dot(d) > 1e-4:
                    bad[oname] = bad.get(oname, 0) + 1
    return total, bad


def _view_dir(pitch, yaw):
    p, y = math.radians(pitch), math.radians(yaw)
    return -Vector((math.sin(y) * math.cos(p), math.cos(y) * math.cos(p), math.sin(p)))


def backface_problems(objs, ground=True, cutaway=False):
    """M3: no BACK face may be the first thing a game-camera ray sees (open tube ends / cone tops, flipped or folded
    snow faces, coplanar overlaps show as magenta in the previews and as holes / flicker in Godot, whose game shader
    culls back faces). Orthographic rays over the asset from pitch 48 (8 yaws, the game camera) and 25 deg (8 yaws);
    hits below z = 0 are hidden by the terrain (ground=False for hanging assets); the `_Stub` walls are hidden. With
    cutaway=True (POIs / kit buildings) also the 8 cutaway states of §9.3 (Roof + camera-facing facades hidden, their
    stubs shown), seen from their own yaw."""
    meshes = [o for o in objs if o.type == 'MESH' and not is_col(o)]
    views = [_view_dir(48.0, 45 * k) for k in range(8)] + [_view_dir(25.0, 45 * k + 22.5) for k in range(8)]
    total, bad = _bf_hits([o for o in meshes if not o.name.endswith("_Stub")], views, ground)
    if cutaway and any(o.name.startswith("Walls") for o in meshes):
        for k in range(8):
            d = _view_dir(48.0, 45 * k)
            hidden = _cut_hidden(meshes, -d)
            t, b = _bf_hits([o for o in meshes if o.name not in hidden], [d], ground, step_div=200)
            total += t
            for kk, v in b.items():
                bad[kk + " (cutaway)"] = bad.get(kk + " (cutaway)", 0) + v
    nb = sum(bad.values())
    if nb > BF_MAX_HITS and nb > BF_MAX_FRAC * total:
        return ["%d visible back-face hits of %d game-camera rays (%s)" % (nb, total, bad)]
    return []


def mm_problems(name, spec, objs, g):
    """MultiMesh rule set (ASSET_SPEC_V2 §13 + M3)."""
    out = []
    node = MM_NODES[spec["mm"]]
    if [o.name for o in objs] != [node]:
        out.append("MultiMesh asset must hold exactly one object %s, has %s" % (node, sorted(o.name for o in objs)))
        return out
    o = objs[0]
    if o.type != 'MESH' or o.parent is not None or o.children:
        out.append("%s must be a top-level mesh without children" % node)
    prims = sum(len(g["meshes"][nd["mesh"]]["primitives"]) for nd in g["nodes"] if "mesh" in nd)
    if prims != 1:
        out.append("%d surfaces (MultiMesh: 1)" % prims)
    mn, mx = world_bounds([o])
    size = mx - mn
    c = (mn + mx) * 0.5
    if math.hypot(c.x, c.y) > 0.25 * max(size.x, size.y):
        out.append("origin not at the base centre (bbox centre %.2f, %.2f)" % (c.x, c.y))
    for key in ("family", "col", "col_center", "col_size", "height", "radius", "choppable"):
        if key not in o.keys():
            out.append("extras: missing %s" % key)
    if out:
        return out
    if o["family"] != spec["mm"]:
        out.append("extras family %s != %s" % (o["family"], spec["mm"]))
    kind = o["col"]
    if kind not in COL_KINDS:
        out.append("extras col %s not in %s" % (kind, sorted(COL_KINDS)))
    elif len(list(o["col_size"])) != COL_KINDS[kind] or len(list(o["col_center"])) != 3:
        out.append("extras col_size %s / col_center %s do not fit col=%s" % (list(o["col_size"]), list(o["col_center"]),
                                                                          kind))
    if abs(o["height"] - mx.z) > 0.03:
        out.append("extras height %.3f != top %.3f" % (o["height"], mx.z))
    if o["radius"] <= 0 or o["radius"] > 0.5 * math.hypot(size.x, size.y) + 0.3:
        out.append("extras radius %.3f implausible" % o["radius"])
    if kind != "none":
        cc = list(o["col_center"])
        cs = list(o["col_size"])
        top = cc[1] + (cs[1] / 2 if kind == "cylinder" else (cs[0] if kind == "sphere" else cs[1] / 2))
        if top > mx.z + 0.1 or cc[1] < -0.3:
            out.append("collision proxy outside the asset (centre %s size %s, top %.2f)" % (cc, cs, mx.z))
    folder, base = name.split("/")
    man = export.MODELS_DIR / folder / "manifest.json"
    try:
        rec = json.loads(man.read_text())[base]
    except (OSError, ValueError, KeyError):
        out.append("no entry in %s/manifest.json" % folder)
        return out
    if rec.get("node") != node or rec.get("path") != "res://assets/models/%s.glb" % name:
        out.append("manifest node/path mismatch %s %s" % (rec.get("node"), rec.get("path")))
    if rec.get("tris") != tris_of(o):
        out.append("manifest tris %s != %d" % (rec.get("tris"), tris_of(o)))
    for key in ("family", "col", "choppable"):
        if rec.get(key) != o[key]:
            out.append("manifest %s %s != extras %s" % (key, rec.get(key), o[key]))
    return out


def stub_outline_problems(full, stub):
    """_Stub: same extent along the facade, and inside the full wall in plan (+-3 cm)."""
    mn, mx = world_bounds([full])
    smn, smx = world_bounds([stub])
    out = []
    along = 0 if (mx.x - mn.x) >= (mx.y - mn.y) else 1
    if abs(smn[along] - mn[along]) > 0.05 or abs(smx[along] - mx[along]) > 0.05:
        out.append("%s extent along the facade %.2f..%.2f != %s %.2f..%.2f" % (
            stub.name, smn[along], smx[along], full.name, mn[along], mx[along]))
    for i in (0, 1):
        if smn[i] < mn[i] - 0.03 or smx[i] > mx[i] + 0.03:
            out.append("%s outline leaves %s in plan" % (stub.name, full.name))
            break
    if smx.z > mn.z + 0.8 + 0.45:
        out.append("%s too tall (top %.2f, wall base %.2f)" % (stub.name, smx.z, mn.z))
    return out


def cut_problems(by, objs):
    """v2 cutaway structure (ASSET_SPEC_V2 §8.4 / §8.6 / §16.12)."""
    out = []
    groups = [o for o in objs if o.type == 'MESH' and re.match(r"^(Floor\d+|Walls\d+_[NSEW](_Stub)?|Interior\d+|Roof)$",
                                                                o.name)]
    names = {o.name for o in groups}
    for o in groups:
        if o.get("cut_group") != o.name:
            out.append("%s: cut_group prop %r" % (o.name, o.get("cut_group")))
        if "floor" not in o.keys():
            out.append("%s: no floor prop" % o.name)
        if o.name.startswith("Floor") and "floor_z" not in o.keys():
            out.append("%s: no floor_z prop" % o.name)
        if o.parent is not None:
            out.append("%s must be top level" % o.name)
        m = re.match(r"^(Walls\d+_[NSEW])$", o.name)
        if m:
            stub = by.get(o.name + "_Stub")
            if stub is None:
                out.append("%s has no _Stub" % o.name)
            else:
                out += stub_outline_problems(o, stub)
    for o in objs:
        if re.match(r"^Door_\d+$", o.name):
            if o.get("kind") not in ("door", "double", "garage"):
                out.append("%s kind %r" % (o.name, o.get("kind")))
            if "exterior" not in o.keys():
                out.append("%s has no exterior prop" % o.name)
            if o.get("cut_group") not in names:
                out.append("%s cut_group %r is not a group" % (o.name, o.get("cut_group")))
        elif re.match(r"^Window_\d+$", o.name):
            mats = [m.name for m in o.data.materials if m]
            if mats != ["window"]:
                out.append("%s materials %s (want [window])" % (o.name, mats))
            if o.get("boarded") not in (False, 0):
                out.append("%s boarded prop %r" % (o.name, o.get("boarded")))
            if o.get("cut_group") not in names:
                out.append("%s cut_group %r is not a group" % (o.name, o.get("cut_group")))
        elif o.name.startswith("Spawn_"):
            if o.type != 'EMPTY':
                out.append("%s must be an empty" % o.name)
            if not export.is_pure_yaw(o.matrix_basis.to_3x3().normalized()):
                out.append("%s rotation is not a pure yaw" % o.name)
            if o.name.startswith("Spawn_Container_") and not o.get("table"):
                out.append("%s has no loot table prop" % o.name)
            if o.get("kind") != o.name.split("_")[1]:
                out.append("%s kind prop %r" % (o.name, o.get("kind")))
    return out


def verify(name, spec0, allowed_bytes, godot_targets):
    """Returns (status, message, tris, surfaces)."""
    spec = final_spec(spec0)
    glb = export.MODELS_DIR / ("%s.glb" % name)
    blend = export.SOURCES_DIR / ("%s.blend" % name.split("/")[-1])
    if not glb.exists() or not blend.exists():
        if spec["pri"] >= 2:
            return "SKIP", "SKIP %s (P2, not built)" % name, 0, 0
        return "FAIL", "FAIL %s: missing %s" % (name, "glb" if not glb.exists() else "blend"), 0, 0
    with open(glb, "rb") as f:
        head = f.read(4)
    if glb.stat().st_size <= 1024 or head != b"glTF":
        return "FAIL", "FAIL %s: glb too small or bad header" % name, 0, 0

    g, binary = load_glb(glb)
    problems, surfaces = gltf_problems(g, binary, godot_targets)
    if spec["max_surfaces"] is not None and surfaces > spec["max_surfaces"]:
        problems.append("%d surfaces > %d" % (surfaces, spec["max_surfaces"]))

    export.reimport(glb)
    objs = list(bpy.data.objects)
    by = {o.name: o for o in objs}

    # names
    for req in spec["pivots"]:
        if req not in by:
            problems.append("missing %s" % req)
    for o in objs:
        if "." in o.name:
            problems.append("dotted name %s" % o.name)
        if "-" in o.name and not is_col(o):
            problems.append("bad suffix %s" % o.name)
        if o.name.startswith("Col") and not is_col(o):
            problems.append("Col object without -convcolonly: %s" % o.name)
        if o.type not in ('MESH', 'EMPTY'):
            problems.append("stray %s %s" % (o.type, o.name))
    col_objs = [o for o in objs if is_col(o)]
    col_table = spec["col"]
    if isinstance(col_table, str):                        # POI builder module exposing COL_BOXES
        import importlib
        col_table = importlib.import_module(col_table).COL_BOXES
    have_col = set(o.name for o in col_objs)
    if col_table is not None:
        want_col = set(n + "-convcolonly" for n in col_table)
        if want_col != have_col:
            problems.append("collision set mismatch: missing %s extra %s" % (sorted(want_col - have_col),
                                                                           sorted(have_col - want_col)))
    # hierarchy
    for child, par in spec["parents"].items():
        if child in by and (by[child].parent is None or by[child].parent.name != par):
            problems.append("%s parent is %s, expected %s" % (
                child, by[child].parent.name if by[child].parent else None, par))
    # pivots
    for n, piv in spec["pivots"].items():
        if piv is None or n not in by:
            continue
        w = by[n].matrix_world.translation
        if (w - Vector(piv)).length > PIVOT_TOL:
            problems.append("pivot %s at %s, expected %s" % (n, tuple(round(c, 3) for c in w), piv))
    # front = -Y
    for n in spec["extra"].get("forward", []):
        if n in by and by[n].matrix_world.translation.y >= 0:
            problems.append("%s not in front (-Y)" % n)
    for n in spec["extra"].get("back", []):
        if n in by and by[n].matrix_world.translation.y <= 0:
            problems.append("%s not at the back (+Y)" % n)
    problems += front_mesh_problems(by, spec["extra"].get("front_mesh", {}))
    tip = spec["extra"].get("tip")
    if tip and tip in by:
        mx = max((by[tip].matrix_world @ v.co).x for v in by[tip].data.vertices)
        if mx <= 0.8:
            problems.append("%s tip max x %.2f <= 0.8" % (tip, mx))
    ue = spec["extra"].get("useful_end")
    if ue and ue in by:
        mn_ue, mx_ue = world_bounds([by[ue]])
        if mn_ue.y > -0.15 or mx_ue.y > 0.06:
            problems.append("%s not toward -Y (y %.2f..%.2f)" % (ue, mn_ue.y, mx_ue.y))
    # dimensions
    vis = [o for o in objs if o.type == 'MESH' and not is_col(o)]
    mn, mx = world_bounds(vis)
    size = mx - mn
    for ax, want in spec["dims"].items():
        got = size["xyz".index(ax)]
        if abs(got - want) > DIM_TOL * want:
            problems.append("size %s %.3f vs %.3f" % (ax, got, want))
    for n, d in spec["dims_of"].items():
        if n in by and "zmax" in d:
            z = world_bounds([by[n]])[1].z
            if abs(z - d["zmax"]) > DIM_TOL * d["zmax"]:
                problems.append("%s top %.3f vs %.3f" % (n, z, d["zmax"]))
    if spec["minz"] is not None:
        low = spec["minz"] - (SINK_TOL if spec["minz"] == 0.0 else 0.02)
        if not low <= mn.z <= spec["minz"] + 0.02:
            problems.append("min z %.3f, expected %.2f (snow may sink to %.2f)" % (mn.z, spec["minz"], low))
    if "maxz" in spec["extra"] and abs(mx.z - spec["extra"]["maxz"]) > 0.02:
        problems.append("max z %.3f, expected %.2f" % (mx.z, spec["extra"]["maxz"]))
    # transforms
    for o in objs:
        if o.type == 'EMPTY' and export.yaw_allowed(o.name):
            continue                                       # Spawn_*: checked by cut_problems (pure yaw)
        want = ROTATED.get(o.name, (0.0, 0.0, 0.0))
        r = o.matrix_basis.to_3x3().normalized()
        target = Euler(tuple(math.radians(x) for x in want)).to_matrix()
        if any(abs(r[i][j] - target[i][j]) > 1e-3 for i in range(3) for j in range(3)):
            problems.append("rotation on %s %s" % (o.name, tuple(round(math.degrees(x), 1)
                                                                 for x in o.matrix_basis.to_euler())))
        if any(abs(s - 1.0) > 1e-4 for s in o.matrix_basis.to_scale()):
            problems.append("scale on %s" % o.name)
    # shading / colours / materials
    if len(bpy.data.images):
        problems.append("image datablocks present")
    allowed_mats = export.allowed_materials()
    for o in objs:
        if o.type != 'MESH':
            continue
        me = o.data
        # v2.1: smooth shading and custom normals are allowed (the glTF check requires NORMAL on every primitive)
        if len(me.uv_layers):
            problems.append("UV layers on %s" % o.name)
        if is_col(o):
            if len(me.color_attributes):
                problems.append("colour attribute on collision %s" % o.name)
            continue
        if len(me.materials) == 0:
            problems.append("no material on %s" % o.name)
        if len(me.materials) > MAX_SURFACES_PER_MESH:
            problems.append("%d materials on %s" % (len(me.materials), o.name))
        for m in me.materials:
            if m is None or m.name not in allowed_mats:
                problems.append("material %s on %s not allowed" % (m.name if m else None, o.name))
        nm = len(me.materials)
        if any(p.material_index >= nm for p in me.polygons):
            problems.append("bad material index on %s" % o.name)
        problems += colour_problems(o, allowed_bytes)
        bad = winding_problems(o)
        if bad:
            problems.append("%d inverted/inconsistent closed part(s) in %s" % (bad, o.name))
    for key in ("window", "ember", "glass"):
        for n in spec["extra"].get(key, []):
            if n in by and key not in [m.name for m in by[n].data.materials if m]:
                problems.append("%s does not use material %s" % (n, key))
    # budget
    tris = sum(tris_of(o) for o in vis)
    slack = 1.0 if spec["hd"] else BUDGET_SLACK
    if tris > spec["budget"] * slack:
        problems.append("tris %d > %d x %.1f" % (tris, spec["budget"], slack))
    # collision
    for o in col_objs:
        box = col_table.get(o.name[:-len("-convcolonly")]) if col_table else None
        if box:
            problems += check_collision(o, box)
        elif spec["poi"]:
            problems += col_shape_problems(o)
            cmn, cmx = world_bounds([o])
            if any(cmn[i] < mn[i] - 0.15 or cmx[i] > mx[i] + 0.15 for i in range(3)):
                problems.append("%s outside the visual bounds" % o.name)
    if spec["mm"]:
        problems += mm_problems(name, spec, objs, g)
    if spec["bf"]:
        problems += backface_problems(objs, ground=spec["minz"] is not None and spec["minz"] >= -0.01
                                      and "maxz" not in spec["extra"], cutaway=spec["poi"])
    if spec["poi"]:
        problems += cut_problems(by, objs)

    if problems:
        return "FAIL", "FAIL %s: %s" % (name, "; ".join(problems)), tris, surfaces
    names = sorted(o.name for o in objs)
    return "OK", "OK %-14s tris=%-6d surfaces=%-3d %s dims=(%.2f,%.2f,%.2f)  objects=[%s]" % (
        name, tris, surfaces, ao_summary(g, binary), size.x, size.y, size.z, ", ".join(names)), tris, surfaces


def view_budget(per):
    """doc 05 §4.5 typical clearing view: sum of instances x tris + reserve <= VIEW_BUDGET. Returns failures."""
    view = 0
    for name, n in TYPICAL_VIEW.items():
        if name in per:
            t = per[name]
        else:
            path = export.MODELS_DIR / ("%s.glb" % name)
            t = glb_tris(path) if path.exists() else 0
        view += n * t
    reserve = sum(VIEW_RESERVE.values())
    ok = view + reserve <= VIEW_BUDGET
    print("%s typical clearing view: assets %d + reserve %d (%s) = %d tris (budget %d)" % (
        "OK  " if ok else "FAIL", view, reserve, ", ".join(VIEW_RESERVE), view + reserve, VIEW_BUDGET))
    return 0 if ok else 1


def forest_budget(per):
    """M3: typical forest view (streamed chunks at the default camera) + reserve <= VIEW_BUDGET."""
    view = 0
    for name, n in FOREST_VIEW.items():
        path = export.MODELS_DIR / ("%s.glb" % name)
        t = per[name] if name in per else (glb_tris(path) if path.exists() else 0)
        view += n * t
    reserve = sum(FOREST_RESERVE.values())
    ok = view + reserve <= VIEW_BUDGET
    print("%s typical forest view (M3): assets %d + reserve %d (%s) = %d tris (budget %d)" % (
        "OK  " if ok else "FAIL", view, reserve, ", ".join(FOREST_RESERVE), view + reserve, VIEW_BUDGET))
    return 0 if ok else 1


def main():
    failures = 0
    total = 0
    total_surf = 0
    allowed_bytes = reimport_targets()
    godot_targets = {palette.target_godot_bytes(n) for n in palette.all_names()}
    per = {}
    for name, spec in ASSETS.items():
        status, msg, tris, surfaces = verify(name, spec, allowed_bytes, godot_targets)
        total += tris
        total_surf += surfaces
        per[name] = tris
        print(msg)
        if status == "FAIL":
            failures += 1
    print("TOTAL tris=%d surfaces=%d (all %d assets once)" % (total, total_surf, len(ASSETS)))
    failures += view_budget(per)
    failures += forest_budget(per)
    print("ALL OK" if failures == 0 else "%d FAILURES" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
