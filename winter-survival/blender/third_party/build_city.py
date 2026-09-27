"""A1 — first winterized city set of Altavega from pinned CC0 sources (docs/research/07, 08, 09; contract:
docs/v2/ASSET_SPEC_V2.md section "A1").

    cd winter-survival/blender
    python3 third_party/build_city.py                  # every family (fetches missing sources first)
    python3 third_party/build_city.py towers vehicles  # some families (towers buildings vehicles props highway)
    python3 third_party/build_city.py tower_a sedan    # some assets (ids or id prefixes)
    python3 build_all.py --only city                   # the same through build_all (+ verify_assets.py)

Outputs: assets/models/city/<family>/<id>.glb (+ .import), assets/models/city/manifest.json (per asset: nodes,
tris, anchors, collision proxy, storeys, sources) and assets/third_party/manifest.json + LICENSES/ (per source file:
pack, author, licence, repository, commit, sha256, and the outputs made from it). No .blend is written: every
output is regenerated from the pinned sources (third_party/sources.json + fetch.py).
"""
import json
import math
import os
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import bpy  # noqa: E402,F401
from mathutils import Vector, noise  # noqa: E402

from lib import palette  # noqa: E402
from lib import export as ex  # noqa: E402
from third_party import cutready as CR  # noqa: E402
from third_party import fetch  # noqa: E402
from third_party import procprops as PP  # noqa: E402
from third_party import vehicles as V  # noqa: E402
from third_party import winterize as W  # noqa: E402

ROOT = HERE.parents[1]                                  # winter-survival/
CITY = ROOT / "assets" / "models" / "city"
TP = ROOT / "assets" / "third_party"
REPORT = {}                                             # id -> manifest entry (this run)

# ------------------------------------------------------------------------------------------------------------------
# node contract of city buildings = the render agent's W0 contract (scripts/world/city/city_building.gd,
# CityBuilding.validate(); README "Corte urbano y graficos G2 (W0)"): root metadata floor_h / ground_h / foundation /
# floors / generator / enterable / kind; pieces Base, Shaft_<n> (extras floor_from / floor_to, <= 4 storeys), Roof
# (crown), ShadowProxy (closed prism, the only shadow caster). Every city building has a Base; a ShadowProxy above 12 m.
# ------------------------------------------------------------------------------------------------------------------
TOWER_NODES = {"base": "Base", "shaft": "Shaft_%d", "top": "Roof", "shadow": "ShadowProxy"}
BASE_STOREYS = 4            # storeys 0..3 in Base (street level up to ~16-20 m: what the game camera sees)
GROUP_STOREYS = 4           # storeys per Shaft_<n> (W0: <= 4; the frustum culls the groups above the camera)
TOWER_FLOOR_H = 3.8
BUILDING_FLOOR_H = 3.8     # the same storey as the towers: one window-cell height for the whole city
KENNEY_STOREY = 0.4         # City Kit Commercial building module (source units per storey)

K_COM = "kenney-city-kit-commercial"
K_ROADS = "kenney-city-kit-roads"
K_CAR = "kenney-car-kit"
K_SURV = "kenney-survival-kit"
K_HOL = "kenney-holiday-kit"
K_WATER = "kenney-watercraft-pack"
Q_CARS = "quaternius-cars"
Q_ZOMB = "quaternius-zombie-apocalypse-kit"
Q_STREETS = "quaternius-modular-streets"
Q_PT = "quaternius-public-transport"
Q_SURV = "quaternius-survival"


def kglb(name):
    return "Models/GLB format/%s.glb" % name


VAR_A = "Models/Textures/variation-a.png"
VAR_B = "Models/Textures/variation-b.png"

# towers: Kenney City Kit Commercial skyscrapers, one floor band repeated `extend` times (doc 07 §3.2)
TOWERS = {
    "tower_a": dict(src=(K_COM, kglb("building-skyscraper-a")), extend=10),
    "tower_b": dict(src=(K_COM, kglb("building-skyscraper-b")), extend=12),
    "tower_c": dict(src=(K_COM, kglb("building-skyscraper-c")), extend=8),
    "tower_d": dict(src=(K_COM, kglb("building-skyscraper-d")), extend=11),
    "tower_e": dict(src=(K_COM, kglb("building-skyscraper-e")), extend=6),
}

# mid / low-rise downtown blocks: Kenney City Kit Commercial buildings (0.4-unit storey module -> 3.8 m, x9.5);
# variation-a / -b atlases (Kenney's own recolours) for warmer facades
BUILDINGS = {
    "bldg_a": dict(src=(K_COM, kglb("building-a"))),
    "bldg_c": dict(src=(K_COM, kglb("building-c")), atlas=VAR_A),
    "bldg_d": dict(src=(K_COM, kglb("building-d"))),
    "bldg_e": dict(src=(K_COM, kglb("building-e")), atlas=VAR_B),
    "bldg_f": dict(src=(K_COM, kglb("building-f"))),
    "bldg_g": dict(src=(K_COM, kglb("building-g")), atlas=VAR_A),
    "bldg_i": dict(src=(K_COM, kglb("building-i"))),
    "bldg_k": dict(src=(K_COM, kglb("building-k")), atlas=VAR_B),
    "bldg_l": dict(src=(K_COM, kglb("building-l"))),
    "bldg_m": dict(src=(K_COM, kglb("building-m")), atlas=VAR_B),
    "bldg_n": dict(src=(K_COM, kglb("building-n")), atlas=VAR_A),
}
BUILDING_BUDGET = 12000
TOWER_BUDGET = 16000
VEHICLE_BUDGET = (2500, 8000)

# vehicles: real proportions (m). classes / colours by normalised source material name; glass by atlas swatch
# above a height where the pack paints windows in its atlas (Quaternius Zombie Kit)
Q_CAR_CLASSES = {"windows": "glass", "headlights": "lamp", "taillights": "tail", "bluelights": "beacon",
                 "whitelights": "beacon"}
VEHICLES = {
    "sedan": dict(src=(Q_CARS, "S_NormalCar1.usda"), scale="dims:1.82,4.65,1.45", classes=Q_CAR_CLASSES, doors4=True,
                  colours={"blue": "#34557E"}),
    "suv": dict(src=(Q_CARS, "S_SUV.usda"), scale="dims:1.95,4.8,1.78", classes=Q_CAR_CLASSES, doors4=True,
                colours={"white": "#6E2E2A"}),
    "taxi": dict(src=(Q_CARS, "S_Taxi.usda"), scale="dims:1.82,4.65,1.52", classes=Q_CAR_CLASSES, doors4=True),
    "police": dict(src=(Q_CARS, "S_Cop.usda"), scale="dims:1.88,4.9,1.6", classes=Q_CAR_CLASSES, doors4=True, beacon=True),
    "pickup": dict(src=(Q_ZOMB, "S_VehiclePickup.usda"), scale="dims:2.05,5.6,1.95",
                   glass_rule={"hex": "#444444", "tol": 0.02, "zmin": 1.15},
                   recolour=[("#4E8AAC", "#2F5A73", 0.05)]),
    "van": dict(src=(K_CAR, kglb("van")), scale="dims:2.0,5.3,2.4", glass_rule="kenney"),
    "ambulance": dict(src=(Q_PT, "S_Ambulance.usda"), scale="dims:2.3,6.3,2.8", beacon=True,
                      colours={"white": "paint_white", "red": "paint_red", "grey": "concrete", "bumper": "concrete_dark",
                               "material": "tire"},
                      classes={"windows": "glass", "lights": "lamp"}, beacon_mats=("red", "lights"), beacon_z=0.82),
    "bus": dict(src=(Q_PT, "S_Bus.usda"), scale="dims:2.55,12.0,3.1", crash_depth=1.4,
                colours={"top": "paint_red", "bottom": "paint_white", "details": "plastic_black",
                         "bumper": "concrete_dark", "material": "tire"},
                classes={"windows": "glass", "lights": "lamp"}, door_side=-1),
    "box_truck": dict(src=(Q_ZOMB, "S_VehicleTruck.usda"), scale="dims:2.5,7.2,3.4", crash_depth=1.2,
                      glass_rule={"hex": "#2A2929", "tol": 0.02, "zmin": 1.55},
                      recolour=[("#939E3E", "paint_red", 0.06)]),
    "military_truck": dict(src=(Q_ZOMB, "S_VehicleTruck.usda"), scale="dims:2.5,7.2,3.4", crash_depth=1.2,
                           glass_rule={"hex": "#2A2929", "tol": 0.02, "zmin": 1.55},
                           recolour=[("#939E3E", "military_green", 0.06), ("#C0BFBC", "parka_olive", 0.05),
                                     ("#757A6A", "military_green", 0.05)]),
}

PROP_BUDGET = 1500
# street props: scale "height:<m>" / "dims:w,l,h" / number; orient: arm (lamp head / signal arm to -Y), panel (sign
# face to -Y), long_x (longest side along X) or a fixed yaw; anchors: lamp | signal | panel | none
PROPS = {
    "lamp_ornate": dict(src=(Q_STREETS, "S_StreetlightSingle.usda"), scale="height:4.4", anchors="lamp",
                        classes={"glass": "lamp", "light": "lamp"}),
    "lamp_street": dict(src=(Q_ZOMB, "S_StreetLights.usda"), scale=1.0, orient="arm", anchors="lamp",
                        classes={"light": "lamp"}),
    "lamp_highway": dict(src=(K_ROADS, kglb("light-curved")), scale="dims:0.42,2.4,9.0", orient="arm", anchors="lamp",
                         swatch_classes=[("#F1976C", "lamp", 0.06)]),
    "lamp_highway_double": dict(src=(K_ROADS, kglb("light-curved-double")), scale="dims:4.6,0.42,9.0", anchors="lamp",
                                yaw=90, swatch_classes=[("#F1976C", "lamp", 0.06)]),
    "traffic_light": dict(src=(Q_ZOMB, "S_TrafficLight_1.usda"), scale=1.0, anchors="signal"),
    "traffic_light_arm": dict(src=(Q_ZOMB, "S_TrafficLight_2.usda"), scale=1.0, orient="arm", anchors="signal"),
    "sign_stop": dict(src=(Q_STREETS, "S_SignStop.usda"), scale="height:2.6", orient="mat:red"),
    "sign_no_parking": dict(src=(Q_STREETS, "S_SignNoParking.usda"), scale="height:2.6", orient="mat:red"),
    "sign_yield": dict(src=(Q_STREETS, "S_SignTriangle.usda"), scale="height:2.6", orient="mat:white"),
    "sign_panel_a": dict(src=(Q_PT, "S_TrafficSign1.usda"), scale="height:2.9", orient="panel", anchors="panel",
                         colours={"sign": "metal_blue", "border": "paint_white", "pole": "metal_sheet"},
                         classes={"sign": "panel"}),
    "sign_panel_b": dict(src=(Q_PT, "S_TrafficSign2.usda"), scale="height:2.9", orient="panel", anchors="panel",
                         colours={"sign": "paint_white", "border": "paint_red", "pole": "metal_sheet"},
                         classes={"sign": "panel"}),
    "sign_panel_c": dict(src=(Q_PT, "S_TrafficSign3.usda"), scale="height:2.9", orient="panel", anchors="panel",
                         colours={"sign": "paint_yellow", "border": "paint_black", "pole": "metal_sheet"},
                         classes={"sign": "panel"}),
    "traffic_cone": dict(src=(Q_ZOMB, "S_TrafficCone_1.usda"), scale="height:0.7"),
    "jersey_barrier": dict(src=(K_ROADS, kglb("construction-barrier")), scale="dims:3.0,0.62,0.82", orient="long_x"),
    "barrier_striped": dict(src=(Q_ZOMB, "S_TrafficBarrier_1.usda"), scale=1.0, orient="long_x"),
    "barrier_sawhorse": dict(src=(Q_ZOMB, "S_TrafficBarrier_2.usda"), scale=1.0, orient="long_x"),
    "barrier_plastic": dict(src=(Q_ZOMB, "S_PlasticBarrier.usda"), scale="height:0.8", orient="long_x"),
    "container_green": dict(src=(Q_ZOMB, "S_ContainerGreen.usda"), scale=1.0, orient="long_x", anchors="loot",
                            snow="roof_box"),
    "container_red": dict(src=(Q_ZOMB, "S_ContainerRed.usda"), scale=1.0, orient="long_x", anchors="loot",
                          snow="roof_box"),
    "barrel": dict(src=(Q_ZOMB, "S_Barrel.usda"), scale="height:0.9"),
    "pallet": dict(src=(Q_ZOMB, "S_Pallet.usda"), scale=1.0, orient="long_x"),
    "trash_bags": dict(src=(Q_ZOMB, "S_TrashBag_1.usda"), scale=1.0),
    "bin_wheelie": dict(src=(Q_SURV, "S_Trashcan.usda"), scale="height:1.05"),
    "hydrant": dict(src=(Q_ZOMB, "S_FireHydrant.usda"), scale=1.0),
    "bench": dict(src=(K_HOL, kglb("bench")), scale="dims:1.8,0.62,0.85", orient="long_x"),
    "water_tower": dict(src=(Q_ZOMB, "S_WaterTower.usda"), scale=1.0, snow_min=1.0),
    "tent_canvas": dict(src=(Q_SURV, "S_Tent.usda"), scale="height:1.5"),
}
# highway pieces (Kenney City Kit Roads): gantries with separate text panels, overpass deck + pillar, barrier
HIGHWAY = {
    "gantry_sign": dict(src=(K_ROADS, kglb("sign-highway")), scale="dims:16.0,1.2,7.6", yaw=90, anchors="panel",
                        swatch_classes=[("#666B80", "panel", 0.03)], budget=2500, panel_colour="metal_blue"),
    "gantry_sign_wide": dict(src=(K_ROADS, kglb("sign-highway-wide")), scale="dims:16.0,1.2,7.6", yaw=90,
                             anchors="panel", swatch_classes=[("#666B80", "panel", 0.03)], budget=2500, panel_colour="metal_blue"),
    "gantry_sign_detailed": dict(src=(K_ROADS, kglb("sign-highway-detailed")), scale="dims:16.0,1.2,8.2", yaw=90,
                                 anchors="panel", swatch_classes=[("#666B80", "panel", 0.03)], budget=2500, panel_colour="metal_blue"),
    "overpass": dict(src=(K_ROADS, kglb("road-bridge")), scale="dims:12.0,12.0,6.4", budget=4000, snow_min=2.0,
                     window_rule=False),
    "bridge_pillar": dict(src=(K_ROADS, kglb("bridge-pillar-wide")), scale="height:6.0"),
    "highway_barrier": dict(src=(K_ROADS, kglb("road-straight-barrier")), scale="dims:12.0,12.0,0.9",
                            orient="long_x"),
}


# ------------------------------------------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------------------------------------------
def src_path(src):
    return fetch.pack_file(*src)


def src_record(src):
    pack, rel = src
    ent = fetch.load_sources()["packs"][pack]["files"][rel]
    return {"pack": pack, "file": rel, "sha256": ent["sha256"]}


_DEPS = {}


def note_images(key):
    """Remember the cached texture files the importer loaded for `key` (atlases sampled for vertex colours)."""
    out = []
    for img in bpy.data.images:
        fp = bpy.path.abspath(img.filepath) if img.filepath else ""
        r = fetch.reverse(fp) if fp else None
        if r and r not in out:
            out.append(r)
    _DEPS[key] = out
    return out


def src_records(src, extra=()):
    recs = [src_record(src)]
    for d in list(_DEPS.get(tuple(src), [])) + list(extra):
        if tuple(d) != tuple(src) and all((r["pack"], r["file"]) != tuple(d) for r in recs):
            recs.append(src_record(d))
    return recs


def prepare(cfg, kind):
    """import + conform + colour extraction (+ optional swatch remap). Returns (obj, info)."""
    W.reset()
    ms = W.import_any(src_path(cfg["src"]))
    note_images(tuple(cfg["src"]))
    obj = W.join(ms, "Asset")
    W.merge_close(obj)
    W.fix_inverted_parts(obj)
    W.separate_coplanar(obj)
    tris_src = W.tri_count(obj)
    ccfg = dict(cfg, kind=kind)
    if cfg.get("atlas"):
        ccfg["atlas"] = str(src_path((cfg["src"][0], cfg["atlas"])))
    info = W.conform(obj, ccfg)
    W.extract(obj, ccfg)
    W.recolour(obj, cfg.get("recolour"), kind)
    info["tris_src"] = tris_src
    return obj, info, ccfg


def set_props(o, props):
    for k, v in props.items():
        o[k] = v


def set_root_meta(props):
    """glTF scene extras (the imported scene root's metadata "extras" in Godot)."""
    sc = bpy.context.scene
    for k, v in props.items():
        sc[k] = v


def record(aid, family, glb, objs, info, extra):
    tris = sum(W.tri_count(o) for o in objs if o.type == "MESH")
    nodes = {}
    for o in objs:
        if o.type == "MESH":
            nodes[o.name] = {"tris": W.tri_count(o), "materials": [m.name for m in o.data.materials]}
        else:
            nodes[o.name] = {"anchor": W.godot_xyz(o.location)}
    ent = {"id": aid, "family": family, "path": "res://" + str(glb.relative_to(ROOT)).replace(os.sep, "/"),
           "tris": tris, "bytes": glb.stat().st_size, "nodes": nodes, **extra}
    ent["winterize"] = W.VERSION
    ent["build"] = info
    ent = json_clean(ent)           # plain Python now: the Blender objects are freed by the next reset
    REPORT[aid] = ent
    print("built %-24s tris=%-6d %s" % (aid, tris, " ".join("%s=%s" % (k, v) for k, v in ent.get("log", {}).items())),
          flush=True)
    ent.pop("log", None)
    return ent


# ------------------------------------------------------------------------------------------------------------------
# towers
# ------------------------------------------------------------------------------------------------------------------
def build_tower(aid, cfg):
    t0 = time.time()
    obj, info, ccfg = prepare(dict(cfg, scale="floor:%.2f" % TOWER_FLOOR_H), "tower")
    st = CR.storeys(obj, TOWER_FLOOR_H)
    pod = CR.podium_level(obj)
    if pod is not None and st["ground_h"] < pod < st["ground_h"] + TOWER_FLOOR_H - 0.5:
        st = CR.storeys(obj, TOWER_FLOOR_H, ground_h=pod)       # the podium top is the first structural floor
        info["ground_from_podium"] = pod
    info["windows_fixed"] = W.fix_windows(obj, st["roof_z"])
    levels = st["levels"]
    bvh = CR.bvh_of([obj])
    slabs, srep = CR.add_slabs(obj, st, bvh)
    missing = [r for r in srep if r[1] == "none"]
    if missing:
        raise RuntimeError("%s: slabs missing at %s" % (aid, missing))
    proxy = CR.shadow_proxy(obj, st, name=TOWER_NODES["shadow"])
    # group boundaries (just under the slab of the first storey of each group)
    base_top = levels[BASE_STOREYS - 1] - 0.25 if len(levels) >= BASE_STOREYS else levels[-1] - 0.25
    top_start = levels[-1] - 0.25
    cuts = [base_top]
    k = BASE_STOREYS - 1 + GROUP_STOREYS
    while k < len(levels) - 1:
        cuts.append(levels[k] - 0.25)
        k += GROUP_STOREYS
    if top_start > cuts[-1] + 1.0:
        cuts.append(top_start)
    else:
        cuts[-1] = top_start
    # colour: grade + weather on the shell
    W.grade_mesh(obj, "tower", ccfg)
    W.weather(obj, "tower", W.seed_of(aid))
    # snow: rounded slabs where the game camera (base) or a lookout (top) sees them, painted snow on shaft ledges
    snow = []
    for n, (faces, area) in enumerate(W.up_islands(obj, z_range=(-1.0, base_top))):
        if area >= 0.6:
            s = W.snow_slab(obj, faces, area, "building", seed=n)
            if s:
                snow.append(s)
    for n, (faces, area) in enumerate(W.up_islands(obj, z_range=(top_start, 1e9))):
        if area >= 1.0:
            s = W.snow_slab(obj, faces, area, "tower", seed=100 + n, cuts_cap=1)
            if s:
                snow.append(s)
    W.paint_snow_faces(obj)
    mn, mx = W.bounds(obj)
    snow += W.base_drifts(mn, mx, "building", W.seed_of(aid), spacing=1.1)
    W.finish_materials(obj)
    # split into groups: shell bands + slabs / snow by height
    bands = CR.split_by_z(obj, cuts)
    names = [TOWER_NODES["base"]] + [TOWER_NODES["shaft"] % i for i in range(len(cuts) - 1)] + [TOWER_NODES["top"]]
    parts = {}
    for name, faces in zip(names, bands):
        parts[name] = [CR.extract_faces(obj, faces, name + "_shell")]
    bpy.data.objects.remove(obj, do_unlink=True)

    def band_of(z):
        return names[sum(1 for c in cuts if z > c)]
    for s in slabs + snow:
        zc = max(v.co.z for v in s.data.vertices) if s in slabs else sum(v.co.z for v in s.data.vertices) / len(s.data.vertices)
        W.finish_materials(s)
        parts[band_of(zc - (0.05 if s in slabs else 0.0))].append(s)
    groups = []
    for name in names:
        g = W.join(parts[name], name)
        groups.append(g)
    W.finish_materials(proxy)
    W.bake(groups, "tower")
    # storey ranges per group
    edges = [0.0] + cuts + [1e9]
    storey_z = [0.0] + levels
    extras_common = {"floor_h": st["floor_h"], "ground_h": st["ground_h"], "floors": st["floors"],
                     "roof_z": st["roof_z"], "height": st["height"], "stub": CR.STUB}
    for i, g in enumerate(groups):
        ks = [k for k, z in enumerate(storey_z) if edges[i] <= z + 0.3 < edges[i + 1]]
        set_props(g, {"cut_group": g.name, "floor_from": min(ks) if ks else -1, "floor_to": max(ks) if ks else -1,
                      "z_from": round(max(0.0, edges[i]), 3), "z_to": round(min(edges[i + 1], st["height"]), 3),
                      "window_cell": [2.4, st["floor_h"]]})
    root_meta = dict(extras_common, kind="tower", foundation=0.0, generator=False, enterable=False,
                     source=cfg["src"][0])
    set_props(groups[0], root_meta)
    set_root_meta(root_meta)
    set_props(proxy, {"shadow_only": True, "cut_group": proxy.name})
    # tests on the final geometry (closed shell per storey + corte urbano view)
    probs = CR.closed_problems(groups, st) + CR.cut_view_problems(groups, st)
    if probs:
        print("WARN %s: %s" % (aid, "; ".join(probs[:4])))
    glb = CITY / "towers" / ("%s.glb" % aid)
    W.export_glb(glb, aid)
    objs = list(bpy.context.scene.objects)
    return record(aid, "towers", glb, objs, info, {
        "sources": src_records(cfg["src"], [(cfg["src"][0], cfg["atlas"])] if cfg.get("atlas") else []),
        "storeys": dict(extras_common, levels=levels), "groups": {g.name: dict(g.items()) for g in groups},
        "problems": probs, "modifications": "rescaled x%s (floor %.1f m), +%d floors, cut-ready (slabs %d), %d groups + "
        "shadow proxy, graded, weathered, snow, AO" % (info["scale"], TOWER_FLOOR_H, cfg["extend"], len(slabs),
                                                        len(groups)),
        "log": {"h": st["height"], "floors": st["floors"], "groups": len(groups), "slabs": len(slabs),
                "t": "%.1fs" % (time.time() - t0)}})


# ------------------------------------------------------------------------------------------------------------------
# mid / low-rise buildings
# ------------------------------------------------------------------------------------------------------------------
def row_pitch(obj):
    rows = CR.window_rows(obj)
    d = sorted(b[0] - a[0] for a, b in zip(rows, rows[1:]) if b[0] - a[0] > 0.02)
    return d[len(d) // 2] if d else None


def build_building(aid, cfg):
    t0 = time.time()
    sc = BUILDING_FLOOR_H / cfg.get("storey_src", KENNEY_STOREY)
    obj, info, ccfg = prepare(dict(cfg, scale=sc, window_sat=0.24), "building")
    st = CR.storeys(obj, BUILDING_FLOOR_H, ground_h=cfg.get("ground_src", KENNEY_STOREY) * sc, roof_frac=0.15)
    info["windows_fixed"] = W.fix_windows(obj, st["roof_z"])
    bvh = CR.bvh_of([obj])
    slabs, srep = CR.add_slabs(obj, st, bvh)
    missing = [r for r in srep if r[1] == "none"]
    if missing:
        raise RuntimeError("%s: slabs missing at %s" % (aid, missing))
    W.grade_mesh(obj, "building", ccfg)
    W.weather(obj, "building", W.seed_of(aid))
    snow = []
    for n, (faces, area) in enumerate(W.up_islands(obj)):
        if area >= 0.6:
            s = W.snow_slab(obj, faces, area, "building", seed=n, cuts_cap=1)
            if s:
                snow.append(s)
    W.paint_snow_faces(obj)
    mn, mx = W.bounds(obj)
    snow += W.base_drifts(mn, mx, "building", W.seed_of(aid), spacing=1.0)
    proxy = CR.shadow_proxy(obj, st, name=TOWER_NODES["shadow"]) if st["height"] > 12.0 else None
    for o in [obj] + slabs + snow:
        W.finish_materials(o)
    # Base (every storey) / Roof (roof surface, parapet, rooftop boxes, roof snow)
    cut = st["roof_z"] - 0.25
    bands = CR.split_by_z(obj, [cut])
    base_parts = [CR.extract_faces(obj, bands[0], "Base_shell")]
    roof_parts = [CR.extract_faces(obj, bands[1], "Roof_shell")] if bands[1] else []
    bpy.data.objects.remove(obj, do_unlink=True)
    for o in slabs + snow:
        zc = sum(v.co.z for v in o.data.vertices) / len(o.data.vertices)
        (roof_parts if zc > cut else base_parts).append(o)
    b = W.join(base_parts, TOWER_NODES["base"])
    parts = [b]
    if roof_parts:
        parts.append(W.join(roof_parts, TOWER_NODES["top"]))
    info["backfaces_patched"] = W.patch_backfaces(parts)
    W.bake(parts, "building")
    if proxy is not None:
        W.finish_materials(proxy)
        set_props(proxy, {"shadow_only": True, "cut_group": proxy.name})
    extras = {"floor_h": st["floor_h"], "ground_h": st["ground_h"], "floors": st["floors"], "roof_z": st["roof_z"],
              "height": st["height"], "stub": CR.STUB, "kind": "building", "foundation": 0.0, "generator": False,
              "enterable": False, "window_cell": [2.4, st["floor_h"]], "source": cfg["src"][0]}
    for o in parts:
        set_props(o, {"cut_group": o.name, "window_cell": [2.4, st["floor_h"]]})
    set_props(b, extras)
    set_root_meta(extras)
    probs = CR.closed_problems(parts, st) + CR.cut_view_problems(parts, st)
    if probs:
        print("WARN %s: %s" % (aid, "; ".join(probs[:4])))
    glb = CITY / "buildings" / ("%s.glb" % aid)
    W.export_glb(glb, aid)
    return record(aid, "buildings", glb, list(bpy.context.scene.objects), info, {
        "sources": src_records(cfg["src"], [(cfg["src"][0], cfg["atlas"])] if cfg.get("atlas") else []),
        "storeys": dict(extras, levels=st["levels"]), "problems": probs,
        "modifications": "rescaled x%.2f (window rows -> %.1f m storeys)%s, cut-ready (%d slabs), graded, weathered, "
        "snow, AO" % (sc, BUILDING_FLOOR_H, ", Kenney %s atlas" % Path(cfg["atlas"]).stem if cfg.get("atlas") else "",
                      len(slabs)),
        "log": {"h": st["height"], "floors": st["floors"], "slabs": len(slabs), "t": "%.1fs" % (time.time() - t0)}})


# ------------------------------------------------------------------------------------------------------------------
# vehicles
# ------------------------------------------------------------------------------------------------------------------
def classify_glass_zmin(obj, rule):
    """Atlas-painted windows: faces of the glass swatch above `zmin` are glass (the same swatch below is grille)."""
    if not isinstance(rule, dict) or "zmin" not in rule:
        return
    me = obj.data
    cls = W.get_cls(me)
    for p in me.polygons:
        if cls[p.index] == W.CLS["glass"] and p.center.z < rule["zmin"]:
            cls[p.index] = W.CLS["body"]
    W.set_cls(me, cls)


def beacon_rule(obj, cfg, mat_of):
    if not cfg.get("beacon_mats"):
        return
    me = obj.data
    cls = W.get_cls(me)
    mn, mx = W.bounds(obj)
    zt = mn.z + cfg["beacon_z"] * (mx.z - mn.z)
    for p in me.polygons:
        if mat_of[p.index] in cfg["beacon_mats"] and p.center.z > zt:
            cls[p.index] = W.CLS["beacon"]
    W.set_cls(me, cls)


def prepare_vehicle(aid, cfg):
    W.reset()
    ms = W.import_any(src_path(cfg["src"]))
    note_images(tuple(cfg["src"]))
    V.tag_wheels(ms)
    obj = W.join(ms, "Asset")
    W.merge_close(obj)
    W.fix_inverted_parts(obj)
    W.separate_coplanar(obj)
    tris_src = W.tri_count(obj)
    ccfg = dict(cfg, kind="vehicle")
    info = W.conform(obj, ccfg)
    mat_of = [W.norm_mat(obj.data.materials[p.material_index].name) if obj.data.materials else ""
              for p in obj.data.polygons]
    W.extract(obj, ccfg)
    classify_glass_zmin(obj, cfg.get("glass_rule"))
    beacon_rule(obj, cfg, mat_of)
    # front check: headlights (or no tail lights) must be at -Y
    lamps = V.class_centres(obj, "lamp", split_x=False).get(0)
    tails = V.class_centres(obj, "tail", split_x=False).get(0)
    if (lamps is not None and lamps.y > 0) or (lamps is None and tails is not None and tails.y < 0):
        W.transform(obj, W.Matrix.Rotation(math.pi, 4, "Z"))
        info["turned"] = 180
    W.recolour(obj, cfg.get("recolour"), "vehicle")
    wheels = V.wheel_records(obj)
    info["tris_src"] = tris_src
    info["wheels"] = len(wheels)
    return obj, wheels, info, ccfg


def build_vehicle_type(aid, cfg):
    t0 = time.time()
    base, wheels, info, ccfg = prepare_vehicle(aid, cfg)
    W.grade_mesh(base, "vehicle", ccfg)
    base_me = base.data
    base_me.use_fake_user = True
    bpy.data.objects.remove(base, do_unlink=True)
    out = []
    for vi, variant in enumerate(V.VARIANTS):
        out.append(build_vehicle_variant(aid, cfg, base_me, wheels, info, variant, W.seed_of(aid) + 17 * vi))
    base_me.use_fake_user = False
    print("  %s: 5 variants in %.1fs" % (aid, time.time() - t0))
    return out


def build_vehicle_variant(aid, cfg, base_me, wheels, info, variant, seed):
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    body = bpy.data.objects.new("Body", base_me.copy())
    bpy.context.scene.collection.objects.link(body)
    mn, mx = W.bounds(body)
    L, Wd, H = mx.y - mn.y, mx.x - mn.x, mx.z - mn.z
    burnt = variant == "burnt"
    wobj = V.wheel_object(wheels, burnt=burnt)
    parts = [body, wobj]
    extra_anchors = {}
    # --- geometry per variant
    if variant == "doors":
        d1 = V.door_faces(body, side=cfg.get("door_side", 1), which="front")
        if d1:
            panel, hinge = V.open_door(body, d1, cfg.get("door_side", 1), 62, seed)
            parts.append(panel)
            extra_anchors["Door_Open"] = hinge
        if cfg.get("doors4"):
            d2 = V.door_faces(body, side=-1, which="rear")
            if d2:
                panel2, hinge2 = V.open_door(body, d2, -1, 48, seed + 1)
                parts.append(panel2)
    anchors = V.lamp_anchors(body)
    if variant == "crashed":
        V.crumple_front(parts, cfg.get("crash_depth", 0.9), 0.36 * cfg.get("crash_depth", 0.9), seed)
        anchors = V.lamp_anchors(body)
        V.frost_glass(body, "concrete", pred=lambda p: p.normal.y < -0.3)
        V.break_lamps(body)
        V.tilt(parts, 2.5, -1.2)
    if burnt:
        drop = max((r for _c, r, _w, _s in wheels), default=0.3) * 0.40
        body.data.transform(W.Matrix.Translation((0, 0, -drop)))
        for k in anchors:
            anchors[k] = anchors[k] - Vector((0, 0, drop))
        V.burn(body, seed)
    # --- weather + snow
    if not burnt:
        W.weather(body, "vehicle", seed, amount={"clean": 0.6, "snowed": 0.8}.get(variant, 1.0))
    snow = []
    thick = {"clean": 0.7, "snowed": 2.4, "crashed": 1.0, "doors": 0.9, "burnt": 0.5}[variant]
    islands = sorted(W.up_islands(body, classes=(W.CLS["body"], W.CLS["burnt"])), key=lambda t: -t[1])
    keep = {"clean": 1, "burnt": 1, "crashed": 3, "doors": 3}.get(variant, 99)     # clean-ish: the roof only
    for n, (faces, area) in enumerate(islands[:keep]):
        if area >= 0.25:
            s_ = W.snow_slab(body, faces, area, "vehicle", seed=seed + n, thick_scale=thick)
            if s_:
                snow.append(s_)
    W.paint_snow_faces(body, coverage={"clean": 0.35, "burnt": 0.3, "crashed": 0.6, "doors": 0.6}.get(variant, 1.0),
                       seed=seed)
    if variant == "snowed":
        V.frost_glass(body, "snow_packed")
        snow.append(W.mound((0.35, 0.1), Wd / 2 + 0.7, L / 2 + 0.9, 0.52 * H, seed=seed, sides=22, rings=5))
    elif variant in ("crashed", "doors"):
        snow.append(W.mound((0.0, 0.0), Wd / 2 + 0.35, L / 2 + 0.45, 0.16, seed=seed, sides=18, rings=3))
    elif burnt:
        soot = Vector(palette.vcol_rgba("paint_black")[:3])
        slush = Vector(palette.vcol_rgba("concrete_dark")[:3])
        sn = Vector(palette.vcol_rgba("snow_shadow")[:3])

        def patch_col(co, r):
            base = soot.lerp(slush, 0.5 + 0.5 * noise.noise(co * 0.9))
            return tuple(base.lerp(sn, W.smooth01(0.55, 1.0, r)))
        snow.append(V.ground_patch(0.0, 0.0, Wd / 2 + 1.2, L / 2 + 1.4, patch_col, seed))
        extra_anchors["Smoke_Engine"] = Vector((0.0, mn.y + 0.22 * L, 0.7 * H))
    if variant == "crashed":
        snow.append(V.shards(0.0, mn.y - 0.6, Wd * 0.6, 10, seed))
        extra_anchors["Smoke_Engine"] = Vector((0.0, mn.y + 0.2 * L, 0.72 * H))
    parts += snow
    # --- split glass, finish, join
    for o in parts:
        W.finish_materials(o)
    glass_objs = []
    for o in parts:
        cls = W.get_cls(o.data)
        gf = [p.index for p in o.data.polygons if cls[p.index] == W.CLS["glass"]]
        if gf:
            from third_party import cutready as CR
            g = CR.extract_faces(o, gf, "Glass_part")
            import bmesh as _bm
            bm = _bm.new()
            bm.from_mesh(o.data)
            bm.faces.ensure_lookup_table()
            _bm.ops.delete(bm, geom=[bm.faces[i] for i in gf], context="FACES")
            bm.to_mesh(o.data)
            bm.free()
            glass_objs.append(g)
    body = W.join(parts, "Body")
    W.finish_materials(body)
    objs = [body]
    if glass_objs:
        glass = W.join(glass_objs, "Glass")
        W.finish_materials(glass)
        objs.append(glass)
    patched = W.patch_backfaces(objs)
    W.bake(objs, "vehicle")
    # --- anchors (Empties) + extras
    bmn, bmx = W.bounds(objs)
    L2, W2, H2 = bmx.y - bmn.y, bmx.x - bmn.x, bmx.z - bmn.z
    anchors = dict(anchors)
    anchors.update(extra_anchors)
    anchors.setdefault("Loot", Vector((0.0, mn.y + 0.78 * L, 0.55 * H)))
    anchors.setdefault("FuelCap", Vector((mx.x - 0.02, mn.y + 0.72 * L, 0.5 * H)))
    if cfg.get("beacon") and "Beacon" not in anchors:
        anchors["Beacon"] = Vector((0.0, mn.y + 0.45 * L, H))
    for k, p in sorted(anchors.items()):
        W.empty(k, p)
    # collision proxy: the body box (without the ground patch / mound) in Godot coordinates
    cmin = Vector((mn.x, mn.y, 0.0))
    cmax = Vector((mx.x, mx.y, H if not burnt else H - 0.1))
    ctr = (cmin + cmax) / 2
    set_props(body, {"kind": "vehicle", "model": aid, "variant": variant, "length": round(L, 3),
                     "width": round(Wd, 3), "height": round(H, 3), "col": "box",
                     "col_center": W.godot_xyz(ctr), "col_size": [round(cmax.x - cmin.x, 3), round(cmax.z - cmin.z, 3),
                                                                  round(cmax.y - cmin.y, 3)],
                     "anchors": {k: W.godot_xyz(v) for k, v in sorted(anchors.items())}})
    vid = "%s_%s" % (aid, variant)
    glb = CITY / "vehicles" / ("%s.glb" % vid)
    W.export_glb(glb, vid)
    return record(vid, "vehicles", glb, list(bpy.context.scene.objects), dict(info), {
        "model": aid, "variant": variant, "sources": src_records(cfg["src"]),
        "dims": [round(W2, 2), round(L2, 2), round(H2, 2)],
        "modifications": "real proportions (%s), wheels rebuilt (16 sides), graded, %s variant, snow, AO"
        % (cfg["scale"], variant), "log": {"dims": "%.1fx%.1fx%.1f" % (W2, L2, H2)}})


# ------------------------------------------------------------------------------------------------------------------
# props + highway pieces
# ------------------------------------------------------------------------------------------------------------------
def horiz_rotate_to(obj, v, target=Vector((0, -1, 0))):
    """Yaw obj so the horizontal vector v points along target."""
    v = Vector((v.x, v.y, 0.0))
    if v.length < 1e-6:
        return 0.0
    ang = math.atan2(target.y, target.x) - math.atan2(v.y, v.x)
    W.transform(obj, W.Matrix.Rotation(ang, 4, "Z"))
    return math.degrees(ang)


def centre_on_pole(obj):
    """Pole props (lamps, traffic lights, signs): origin on the base of the post instead of the bounding-box centre,
    so the level places the post and the collision cylinder is the post (a street lamp's arm is 1.3 m off-centre).
    Returns the shift (x, y) in metres."""
    from mathutils import Matrix
    mn, _mx = W.bounds(obj)
    low = [v.co for v in obj.data.vertices if v.co.z < mn.z + 0.3]
    if not low:
        return (0.0, 0.0)
    cx = 0.5 * (min(v.x for v in low) + max(v.x for v in low))
    cy = 0.5 * (min(v.y for v in low) + max(v.y for v in low))
    obj.data.transform(Matrix.Translation((-cx, -cy, 0.0)))
    obj.data.update()
    return (round(cx, 3), round(cy, 3))


def orient(obj, how, mat_of=None):
    me = obj.data
    mn, mx = W.bounds(obj)
    H = mx.z - mn.z
    if how.startswith("mat:"):
        n = sum((p.normal * p.area for p in me.polygons if mat_of and mat_of[p.index] == how[4:]), Vector())
        return horiz_rotate_to(obj, n)
    if how == "arm":
        top = [v.co for v in me.vertices if v.co.z > mn.z + 0.8 * H]
        return horiz_rotate_to(obj, sum(top, Vector()) / max(1, len(top)))
    if how == "panel":
        cls = W.get_cls(me)
        n = sum((p.normal * p.area for p in me.polygons if cls[p.index] == W.CLS["panel"]), Vector())
        return horiz_rotate_to(obj, n)
    if how == "face":
        # the sign face: the largest vertical face above half height
        best = max((p for p in me.polygons if abs(p.normal.z) < 0.3 and p.center.z > mn.z + 0.5 * H),
                   key=lambda p: p.area, default=None)
        return horiz_rotate_to(obj, best.normal) if best else 0.0
    if how == "long_x":
        if (mx.y - mn.y) > (mx.x - mn.x):
            W.transform(obj, W.Matrix.Rotation(math.pi / 2, 4, "Z"))
            return 90.0
    return 0.0


def clusters(points, gap):
    out = []
    for p in points:
        for c in out:
            if (Vector((p.x, p.y, 0)) - Vector((c[0].x, c[0].y, 0))).length < gap:
                c[1].append(p)
                break
        else:
            out.append([p, [p]])
    return [sum(c[1], Vector()) / len(c[1]) for c in out]


def prop_anchors(obj, kind, panels=()):
    me = obj.data
    mn, mx = W.bounds(obj)
    H = mx.z - mn.z
    cls = W.get_cls(me)
    out = {}
    if kind == "lamp":
        pts = [p.center.copy() for p in me.polygons if cls[p.index] == W.CLS["lamp"]]
        cs = sorted(clusters(pts, 0.8), key=lambda c: (c.x, c.y))
        for i, c in enumerate(cs):
            suf = "" if len(cs) == 1 else "_%d" % i
            out["LightAnchor" + suf] = c - Vector((0, 0, 0.05))
            out["LightPool" + suf] = Vector((c.x, c.y, 0.02))
    elif kind == "signal":
        pts = [v.co.copy() for v in me.vertices if v.co.z > mn.z + 0.72 * H]
        cs = sorted(clusters(pts, 0.9), key=lambda c: (c.x, c.y))
        for i, c in enumerate(cs):
            out["Signal_%d" % i] = c
    elif kind == "loot":
        out["Loot"] = Vector((mx.x - 0.4, 0.0, 1.0))
    for i, pnl in enumerate(panels):
        pmn, pmx = W.bounds(pnl)
        c = (pmn + pmx) / 2
        out["TextPanel" + ("" if len(panels) == 1 else "_%d" % i)] = Vector((c.x, pmn.y - 0.03, c.z))
    return out


def split_panels(obj):
    """Faces of class panel -> separate objects Panel / Panel_<n> (one per connected group)."""
    me = obj.data
    cls = W.get_cls(me)
    faces = [p.index for p in me.polygons if cls[p.index] == W.CLS["panel"]]
    if not faces:
        return []
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    fset = set(faces)
    groups, seen = [], set()
    for fi in faces:
        if fi in seen:
            continue
        st, g = [bm.faces[fi]], []
        seen.add(fi)
        while st:
            f = st.pop()
            g.append(f.index)
            for v in f.verts:
                for h in v.link_faces:
                    if h.index in fset and h.index not in seen:
                        seen.add(h.index)
                        st.append(h)
        groups.append(g)
    bm.free()
    groups.sort(key=lambda g: sum(me.polygons[i].center.x for i in g) / len(g))
    out = []
    for i, g in enumerate(groups):
        out.append(CR.extract_faces(obj, g, "Panel" if len(groups) == 1 else "Panel_%d" % i))
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in faces], context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.update()
    return out


def col_proxy(objs, kind, info=None):
    mn, mx = W.bounds(objs)
    if info and info.get("col_box"):
        mn, mx = Vector(info["col_box"][0]), Vector(info["col_box"][1])
    mn.z = max(0.0, mn.z)
    if kind == "cylinder":
        r = (info or {}).get("pole_r")
        if r is None:
            low = [v.co for o in objs for v in o.data.vertices if v.co.z < mn.z + 0.3]
            r = max(math.hypot(v.x, v.y) for v in low) if low else 0.1
        return {"col": "cylinder", "col_center": W.godot_xyz(Vector((0, 0, (mn.z + mx.z) / 2))),
                "col_size": [round(r, 3), round(mx.z - mn.z, 3)]}
    c = (mn + mx) / 2
    return {"col": "box", "col_center": W.godot_xyz(c),
            "col_size": [round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)]}


def finish_prop(aid, family, objs, anchors, info, cfg, sources, modifications, col):
    """Snow + finish + join (Prop + Panel*) + AO + anchors + export."""
    prop = objs[0]
    panels = [o for o in objs[1:]]
    snow = []
    if cfg.get("snow") == "roof_box":
        # one rounded slab over the top of the bounding box (corrugated roofs would give dozens of strips)
        import bmesh
        mn, mx = W.bounds(prop)
        bm = bmesh.new()
        bm.faces.new([bm.verts.new((x, y, mx.z)) for x, y in ((mn.x + 0.06, mn.y + 0.06), (mx.x - 0.06, mn.y + 0.06),
                                                               (mx.x - 0.06, mx.y - 0.06), (mn.x + 0.06, mx.y - 0.06))])
        tmp = W.mesh_from_bm(bm, "SnowBase")
        bm.free()
        tmp.data.materials.append(palette.get_vcol_material())
        W.set_cls(tmp.data, [W.CLS["body"]])
        s_ = W.snow_slab(tmp, [0], (mx.x - mn.x) * (mx.y - mn.y), "prop", seed=W.seed_of(aid), cuts_cap=1)
        bpy.data.objects.remove(tmp, do_unlink=True)
        if s_:
            snow.append(s_)
    else:
        for n, (faces, area) in enumerate(W.up_islands(prop)):
            if area >= cfg.get("snow_min", 0.35):
                s_ = W.snow_slab(prop, faces, area, "prop", seed=W.seed_of(aid) + n, cuts_cap=2)
                if s_:
                    snow.append(s_)
    W.paint_snow_faces(prop)
    for o in [prop] + panels + snow:
        W.finish_materials(o)
    prop = W.join([prop] + snow, "Prop")
    final = [prop] + panels
    info["backfaces_patched"] = W.patch_backfaces(final)
    W.bake(final, "prop")
    for k, p in sorted(anchors.items()):
        W.empty(k, p)
    extras = {"kind": family[:-1] if family.endswith("s") else family, "anchors":
              {k: W.godot_xyz(v) for k, v in sorted(anchors.items())}}
    extras.update(col)
    if info.get("panels"):
        extras["panels"] = info["panels"]
    set_props(prop, extras)
    glb = CITY / family / ("%s.glb" % aid)
    W.export_glb(glb, aid)
    return record(aid, family, glb, list(bpy.context.scene.objects), info, {
        "sources": sources, "modifications": modifications, "anchors": extras["anchors"],
        "col": {k: v for k, v in col.items()}, "log": {}})


def build_prop(aid, cfg, family="props"):
    W.reset()
    ms = W.import_any(src_path(cfg["src"]))
    note_images(tuple(cfg["src"]))
    obj = W.join(ms, "Prop")
    W.merge_close(obj)
    W.fix_inverted_parts(obj)
    W.separate_coplanar(obj)
    info = {"tris_src": W.tri_count(obj)}
    ccfg = dict(cfg, kind="prop")
    info.update(W.conform(obj, ccfg))
    mat_of = [W.norm_mat(obj.data.materials[p.material_index].name) if obj.data.materials else ""
              for p in obj.data.polygons]
    W.extract(obj, ccfg)
    kind = "cylinder" if cfg.get("anchors") in ("lamp", "signal") or aid.startswith("sign_") else "box"
    if kind == "cylinder":                  # before orient: "arm" = from the post to the centroid of the top
        info["pole_shift"] = centre_on_pole(obj)
    if cfg.get("orient"):
        info["yaw_fix"] = round(orient(obj, cfg["orient"], mat_of), 1)
    W.recolour(obj, cfg.get("recolour"), "prop")
    W.grade_mesh(obj, "prop", ccfg)
    W.weather(obj, "prop", W.seed_of(aid), amount=0.7, rust=False)
    if cfg.get("double_sided"):
        W.double_side(obj)
    panels = split_panels(obj)
    for pnl in panels:
        if cfg.get("panel_colour"):
            W.paint_faces(pnl, range(len(pnl.data.polygons)), name=cfg["panel_colour"])
    anchors = prop_anchors(obj, cfg.get("anchors", "none"), panels)
    info["panels"] = {p.name: [round(x, 3) for x in (W.bounds(p)[1] - W.bounds(p)[0])] for p in panels} or None
    col = col_proxy([obj], kind)
    return finish_prop(aid, family, [obj] + panels, anchors, info, cfg, src_records(cfg["src"]),
                       "scale %s, graded, weathered, snow, AO%s" % (cfg.get("scale"), ", text panels split"
                                                                   if panels else ""), col)


def build_highway(aid, cfg):
    return build_prop(aid, cfg, family="highway")


def build_procedural(aid, fn):
    W.reset()
    objs, anchors, info = fn()
    prop = objs[0]
    W.weather(prop, "prop", W.seed_of(aid), amount=0.6, rust=False)
    col = col_proxy([prop], info.get("col", "box"), info)
    return finish_prop(aid, "props", objs, anchors, dict(info, procedural=True), {}, [
        {"pack": "procedural", "file": "blender/third_party/procprops.py::%s" % aid, "sha256": None}],
        "procedural (VENTISCA, no third-party source), weathered, snow, AO", col)


PROC = {k: (lambda aid, fn=v: build_procedural(aid, fn)) for k, v in PP.PROCEDURAL.items()}
PROC_TABLE = {k: k for k in PP.PROCEDURAL}


# ------------------------------------------------------------------------------------------------------------------
FAMILIES = {"towers": (TOWERS, build_tower), "buildings": (BUILDINGS, build_building),
            "vehicles": (VEHICLES, build_vehicle_type), "props": (PROPS, build_prop),
            "highway": (HIGHWAY, build_highway),
            "procedural": (PROC_TABLE, lambda aid, cfg: PROC[aid](aid))}


# ------------------------------------------------------------------------------------------------------------------
# manifests + licences
# ------------------------------------------------------------------------------------------------------------------
def write_city_manifest():
    """assets/models/city/manifest.json: merged with the previous file (partial rebuilds), entries of deleted .glb
    files dropped, sorted by family then id."""
    path = CITY / "manifest.json"
    old = json.loads(path.read_text()).get("assets", {}) if path.exists() else {}
    old.update(json_clean(REPORT))
    assets = {k: v for k, v in old.items() if (ROOT / v["path"].replace("res://", "")).exists()}
    fams = {}
    for k, v in assets.items():
        fams.setdefault(v["family"], 0)
        fams[v["family"]] += 1
    total = sum(v["bytes"] for v in assets.values())
    data = {"schema": 1, "milestone": "A1", "winterize": W.VERSION,
            "contract": "docs/v2/ASSET_SPEC_V2.md section A1", "tower_nodes": TOWER_NODES,
            "budgets": {"tower": TOWER_BUDGET, "building": BUILDING_BUDGET, "vehicle": list(VEHICLE_BUDGET),
                        "prop": PROP_BUDGET, "highway": 4000},
            "counts": fams, "total_bytes": total,
            "assets": dict(sorted(assets.items(), key=lambda kv: (kv[1]["family"], kv[0])))}
    path.write_text(json.dumps(data, indent=1, sort_keys=False) + "\n")
    return data


def write_third_party(city):
    """assets/third_party/{manifest.json, LICENSES/<pack>.txt, README.md} from sources.json + the city manifest."""
    src = fetch.load_sources()
    TP.mkdir(parents=True, exist_ok=True)
    (TP / "LICENSES").mkdir(exist_ok=True)
    used = {}
    for aid, ent in city["assets"].items():
        for rec in ent.get("sources", []):
            if rec["pack"] == "procedural":
                continue
            used.setdefault(rec["pack"], {}).setdefault(rec["file"], []).append(ent["path"])
    packs = {}
    for pack, files in sorted(used.items()):
        p = src["packs"][pack]
        s_ = src["sources"][p["source"]]
        lic_pack = p.get("license_pack", pack)
        lic_rel = p["license_file"]
        lic_src = fetch.pack_file(lic_pack, lic_rel)
        lic_dst = TP / "LICENSES" / ("%s.txt" % pack)
        text = lic_src.read_text(encoding="utf-8", errors="replace")
        header = ""
        if lic_pack != pack:
            header = ("# Licence of %s (%s), taken from %s/%s at commit %s (the mirror repository's LICENSE: CC0 1.0 "
                      "Universal, the licence of the original Quaternius packs).\n\n" % (p["title"], pack, s_["repo"],
                                                                                          lic_rel, s_["commit"]))
        new = header + text
        if not lic_dst.exists() or lic_dst.read_text(encoding="utf-8", errors="replace") != new:
            lic_dst.write_text(new, encoding="utf-8")
        outs = sorted({o for lst in files.values() for o in lst})
        packs[pack] = {
            "title": p["title"], "version": p.get("version"), "author": p["author"], "license": p["license"],
            "license_file": "LICENSES/%s.txt" % pack, "official_url": p.get("official_url"),
            "fetched_from": {"repo": "https://github.com/%s" % s_["repo"], "commit": s_["commit"],
                             "path": p.get("root") or "/", "via": s_.get("via"), "custody": s_.get("custody")},
            "files": [dict(file=f, sha256=p["files"][f]["sha256"], bytes=p["files"][f]["bytes"],
                           lfs=p["files"][f].get("lfs"), used_by=sorted(set(o)))
                      for f, o in sorted(files.items())] + [
                dict(file=lic_rel if lic_pack == pack else "%s:%s" % (lic_pack, lic_rel),
                     sha256=src["packs"][lic_pack]["files"][lic_rel]["sha256"], role="licence")],
            "outputs": [{"glb": o, "modifications": next(e.get("modifications") for e in city["assets"].values()
                                                           if e["path"] == o)} for o in outs],
            "attribution": "%s by %s (%s)" % (p["title"], p["author"].split(" (")[0], p["license"].replace("-1.0", "")),
        }
    for stale in (TP / "LICENSES").glob("*.txt"):          # a pack no output uses any more
        if stale.stem not in packs:
            stale.unlink()
    procedural = sorted(e["path"] for e in city["assets"].values()
                        if any(r["pack"] == "procedural" for r in e.get("sources", [])))
    data = {"schema": 1, "milestone": "A1",
            "rules": ["nothing enters assets/ without an entry here", "only CC0 (or MIT/BSD with the notice copied) "
                      "- never CC-BY-NC/ND, store EULAs or 'free for personal use'",
                      "source packages are not versioned: blender/third_party/fetch.py re-downloads them at the pinned "
                      "commits and verifies every SHA-256 (blender/third_party/sources.json)",
                      "verify_assets.py fails when an output is missing here, a licence file is missing or a source "
                      "hash differs from the lock"],
            "sources": {k: {"repo": "https://github.com/%s" % v["repo"], "commit": v["commit"], "via": v.get("via"),
                            "custody": v.get("custody")} for k, v in src["sources"].items()},
            "packs": packs, "procedural_outputs": procedural}
    (TP / "manifest.json").write_text(json.dumps(data, indent=1) + "\n")
    write_credits(data)
    return data


def write_credits(data):
    lines = ["# Third-party assets (CC0) — attribution and provenance", "",
             "Generated by `blender/third_party/build_city.py` from `manifest.json` (do not edit by hand).", "",
             "Every third-party model in VENTISCA is **CC0 1.0** (public domain dedication): no attribution is "
             "required, but we credit the authors anyway — thank you. The source packages are **not** stored in the "
             "repository: `blender/third_party/fetch.py` downloads the exact files from the pinned mirror commits "
             "and verifies their SHA-256 (`blender/third_party/sources.json`), and `build_city.py` regenerates every "
             "output (`assets/models/city/**`).", "",
             "| Pack | Author | Licence | Official page | Mirror (pinned commit) | Files | Outputs |",
             "|---|---|---|---|---|---|---|"]
    for pack, p in data["packs"].items():
        fr = p["fetched_from"]
        lines.append("| %s%s | %s | [%s](%s) | %s | [%s](%s) `%s` | %d | %d |" % (
            p["title"], " %s" % p["version"] if p.get("version") else "", p["author"], p["license"], p["license_file"],
            p.get("official_url") or "", fr["repo"].split("github.com/")[1], fr["repo"], fr["commit"][:10],
            len([f for f in p["files"] if f.get("role") != "licence"]), len(p["outputs"])))
    lines += ["", "## Credits (for the in-game credits screen)", ""]
    for pack, p in data["packs"].items():
        lines.append("- %s" % p["attribution"])
    lines += ["- Procedural city props (bus stop, sandbags, hedgehogs, military barricade and tent, guardrail, info "
              "signs): VENTISCA (no third-party source)", "",
              "## Mirrors and chain of custody", "",
              "The official sites (kenney.nl, quaternius.com) are not reachable from the build environment; the files "
              "come from GitHub mirrors (docs/research/07_assets_cc0.md §1):", ""]
    for k, v in data["sources"].items():
        lines.append("- `%s` — %s @ `%s` (%s). %s" % (k, v["repo"], v["commit"], v["via"], v["custody"]))
    lines += ["", "Each pack's own licence text is in `LICENSES/`. For Git LFS files the SHA-256 equals the LFS object "
              "id recorded in the mirror's git tree at that commit. When the official domains open, re-verify against "
              "the official downloads (doc 07 §6).", "",
              "## Adding a pack", "",
              "1. Add the pack and its files to `blender/third_party/sources.json` with `\"sha256\": null`, "
              "run `python3 third_party/fetch.py --lock` and read the pack's licence (CC0 / MIT / BSD only).",
              "2. Map the files to outputs in `blender/third_party/build_city.py` (tables TOWERS / BUILDINGS / "
              "VEHICLES / PROPS / HIGHWAY).",
              "3. `python3 build_all.py --only city` rebuilds the outputs, this README and `manifest.json`, and runs "
              "`verify_assets.py`.", ""]
    (TP / "README.md").write_text("\n".join(lines))


def json_clean(o):
    if isinstance(o, dict):
        return {str(k): json_clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [json_clean(v) for v in o]
    if hasattr(o, "to_list"):
        return json_clean(o.to_list())
    if isinstance(o, float):
        return round(o, 4)
    if hasattr(o, "__len__") and not isinstance(o, str):
        return [json_clean(v) for v in o]
    return o


def main(argv=()):
    argv = [a for a in argv if not a.startswith("-")]
    todo = []
    for fam, (table, fn) in FAMILIES.items():
        for aid, cfg in table.items():
            if not argv or fam in argv or any(aid == a or aid.startswith(a) for a in argv):
                todo.append((fam, aid, cfg, fn))
    failed = []
    t0 = time.time()
    for fam, aid, cfg, fn in todo:
        try:
            fn(aid, cfg)
        except Exception:
            import traceback
            traceback.print_exc()
            failed.append(aid)
    print("city: %d built, %d failed in %.1fs" % (len(todo) - len(failed), len(failed), time.time() - t0))
    if REPORT:
        city = write_city_manifest()
        write_third_party(city)
        print("city manifest: %d assets, %.1f MB" % (len(city["assets"]), city["total_bytes"] / 1e6))
    if failed:
        print("CITY BUILD FAILURES: %s" % ", ".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
