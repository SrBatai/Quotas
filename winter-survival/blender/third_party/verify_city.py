"""A1 checks for assets/models/city/** and the third-party rules (called by verify_assets.py; also standalone):

    cd winter-survival/blender && python3 third_party/verify_city.py [ids or families ...]

Per asset (one OK / FAIL line each, like verify_assets.py):
  * glTF: no images / textures / UVs, NORMAL everywhere, COLOR_0 VEC4 on every palette_vcol primitive, AO in alpha
    (range [0, 1], every primitive has an open corner >= 0.5, asset min <= 0.9, 95th percentile >= 0.85), <= 2
    surfaces per mesh, materials palette_vcol + window / glass / emissive_lamp only, exception primitives white;
  * colour: third-party RGB is graded, not palette-exact -> every palette_vcol colour must lie inside the v2.1
    palette's own OKLab gamut (lightness and chroma range of the palette, docs/research/07 §4.1-10);
  * budgets: towers <= 16 k (all parts), buildings <= 12 k, vehicles <= 8 k, props <= 1.5 k, highway <= 4 k;
  * node contract per family (ASSET_SPEC_V2 "A1"): towers / buildings = the W0 city-building contract (root metadata
    in the glTF scene extras, Base, Shaft_<n> with floor_from / floor_to <= 4 storeys, Roof, ShadowProxy 12-400 tris
    above 12 m), vehicles Body [+ Glass] + anchors (front -Y), props Prop [+ Panel*] + LightAnchor / LightPool /
    Signal_n / TextPanel anchors matching the extras; pole props (col = cylinder) have their origin on the post;
  * cut-ready (towers, buildings): closed volume per storey (no horizontal ray from inside escapes), a slab per floor
    (a downward ray inside every storey meets an up face at the floor level), corte urbano view test;
  * back faces: no visible back face from the game-camera directions (the M3 rule);
  * provenance: listed in assets/models/city/manifest.json; every third-party source of it is in
    assets/third_party/manifest.json with the locked SHA-256 of blender/third_party/sources.json, a licence text
    exists in assets/third_party/LICENSES/, the .glb has its Godot .import next to it;
  * total size of the city set <= 40 MB.
"""
import json
import math
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import verify_assets as VA  # noqa: E402
from lib import export  # noqa: E402
from lib import palette  # noqa: E402
from third_party import cutready as CR  # noqa: E402
from third_party import fetch  # noqa: E402
from third_party import winterize as W  # noqa: E402

ROOT = HERE.parents[1]
CITY = ROOT / "assets" / "models" / "city"
TP = ROOT / "assets" / "third_party"
BUDGET = {"towers": 16000, "buildings": 12000, "vehicles": 8000, "props": 1500, "highway": 4000}
SIZE_LIMIT = 40e6
TOWER_RE = re.compile(r"^(Base|Shaft_\d+|Roof|ShadowProxy)$")
ROOT_META = ("floor_h", "ground_h", "foundation", "floors", "generator", "enterable", "kind")
EXC = {"window", "glass", "emissive_lamp"}


def palette_gamut():
    Ls, Cs = [], []
    for n in palette.BASE_NAMES:
        if palette.is_exception(n):
            continue
        L, a, b = W.lin_to_oklab(*palette.linear_rgba(n)[:3])
        Ls.append(L)
        Cs.append(math.hypot(a, b))
    return min(Ls) - 0.01, max(Ls) + 0.01, max(Cs) + 0.005


def gltf_city_problems(g, binary, gamut):
    probs = []
    alphas = []
    for key in ("images", "textures", "samplers"):
        if g.get(key):
            probs.append("glTF has %s" % key)
    for coll in ("nodes", "meshes", "materials"):
        for item in g.get(coll, []):
            if "." in item.get("name", ""):
                probs.append("dotted %s name %s" % (coll[:-1], item["name"]))
    mats = g.get("materials", [])
    allowed = {palette.VCOL_MATERIAL} | EXC
    for m in mats:
        if m.get("name") not in allowed:
            probs.append("material %s not allowed" % m.get("name"))
    Lmin, Lmax, Cmax = gamut
    out_gamut = 0
    for nd in g["nodes"]:
        if "mesh" not in nd:
            continue
        prims = g["meshes"][nd["mesh"]]["primitives"]
        if len(prims) > 2:
            probs.append("%s has %d surfaces (max 2)" % (nd["name"], len(prims)))
        names = [mats[p["material"]]["name"] if "material" in p else None for p in prims]
        if len(set(names)) != len(names):
            probs.append("%s has duplicated materials" % nd["name"])
        for p, mn in zip(prims, names):
            at = p["attributes"]
            if any(k.startswith("TEXCOORD") for k in at):
                probs.append("%s has UVs" % nd["name"])
            if "NORMAL" not in at:
                probs.append("%s: primitive without NORMAL" % nd["name"])
            if "COLOR_0" not in at:
                probs.append("%s[%s]: no COLOR_0" % (nd["name"], mn))
                continue
            acc = g["accessors"][at["COLOR_0"]]
            if acc["type"] != "VEC4":
                probs.append("%s: COLOR_0 is %s (VEC4 with AO in alpha)" % (nd["name"], acc["type"]))
                continue
            vals = VA.read_accessor(g, binary, at["COLOR_0"])
            al = [c[3] for c in vals]
            if min(al) < -1e-6 or max(al) > 1 + 1e-6:
                probs.append("%s: AO alpha outside [0, 1]" % nd["name"])
            if max(al) < VA.AO_PRIM_MAX:
                probs.append("%s[%s]: AO max %.2f < %.2f" % (nd["name"], mn, max(al), VA.AO_PRIM_MAX))
            alphas += al
            if mn in EXC:
                if any(palette.godot_bytes(c) != (255, 255, 255) for c in vals):
                    probs.append("%s[%s]: exception primitive not white" % (nd["name"], mn))
            else:
                for c in {tuple(round(x, 4) for x in c[:3]) for c in vals}:
                    L, a, b = W.lin_to_oklab(*c)
                    if not (Lmin <= L <= Lmax) or math.hypot(a, b) > Cmax:
                        out_gamut += 1
    if out_gamut:
        probs.append("%d colour(s) outside the v2.1 palette gamut" % out_gamut)
    probs += VA.ao_problems(alphas)
    return probs


BF_FRAC_CITY = 3e-4     # third-party meshes: grazing hits at source seams (bumper ends, trims) up to 0.03 % of rays


def backface_problems_city(vis):
    """The M3 no-visible-back-face rule with the city tolerance: fail above max(8 hits, 0.03 % of the rays) (open or
    inverted parts give hundreds to thousands of hits; third-party seams a handful)."""
    views = [VA._view_dir(48.0, 45 * k) for k in range(8)] + [VA._view_dir(25.0, 45 * k + 22.5) for k in range(8)]
    total, bad = VA._bf_hits(vis, views, True)
    nb = sum(bad.values())
    if nb > VA.BF_MAX_HITS and nb > BF_FRAC_CITY * total:
        return ["%d visible back-face hits of %d game-camera rays (%s)" % (nb, total, bad)]
    return []


def reimport(path):
    export.reimport(path)
    objs = list(bpy.context.scene.objects)
    bpy.context.view_layer.update()
    return objs


def extras_of(g, name):
    for nd in g["nodes"]:
        if nd["name"] == name:
            return nd.get("extras", {})
    return {}


def anchor_problems(objs, extras_anchors, required=()):
    probs = []
    empt = {o.name: o for o in objs if o.type == "EMPTY"}
    for r in required:
        if r not in empt:
            probs.append("anchor %s missing" % r)
    for k, v in (extras_anchors or {}).items():
        if k not in empt:
            probs.append("extras anchor %s has no Empty" % k)
            continue
        gp = W.godot_xyz(empt[k].matrix_world.translation)
        if max(abs(a - b) for a, b in zip(gp, v)) > 0.02:
            probs.append("anchor %s: extras %s != node %s" % (k, v, gp))
    for k in empt:
        if extras_anchors is not None and k not in extras_anchors:
            probs.append("Empty %s not listed in the extras anchors" % k)
    return probs


def slab_problems(objs, st):
    """A slab per floor: from interior points 0.3 m above each floor level a downward ray meets, at the floor line,
    either our slab top (up face, -8 / +30 cm) or the closed bottom of the source's own storey box (down face,
    -30 / +60 cm: the cut shader paints it cap_color, i.e. solid section) for >= 90 % of the points."""
    vis = [o for o in objs if o.type == "MESH" and o.name != "ShadowProxy"]
    bvh = CR.bvh_of(vis)
    mn, mx = W.bounds(vis)
    reach = (mx - mn).length + 1.0
    bad = []
    for k, z in enumerate(st["levels"]):
        pts = CR.interior_points(bvh, mn, mx, z + 0.3, reach, 6, covered=True)
        ok = 0
        for p in pts:
            loc, nrm, _i, _d = bvh.ray_cast(p, Vector((0, 0, -1)), 2.0)
            if loc is not None and ((nrm.z > 0.5 and z - 0.08 <= loc.z <= z + 0.30) or
                                    (nrm.z < -0.5 and z - 0.30 <= loc.z <= z + 0.60)):
                ok += 1
        if not pts or ok < 0.9 * len(pts):
            bad.append("floor %d (z %.2f): slab found under %d of %d points" % (k + 1, z, ok, len(pts)))
    return bad


def family_problems(fam, name, g, objs):
    probs = []
    meshes = {o.name: o for o in objs if o.type == "MESH"}
    empties = {o.name for o in objs if o.type == "EMPTY"}
    mn, mx = W.bounds(list(meshes.values()))
    if not (-0.26 <= mn.z <= 0.05):
        probs.append("lowest point z=%.2f (base must sit at z = 0, snow may sink 0.25 m)" % mn.z)
    if fam in ("towers", "buildings"):
        # W0 contract (scripts/world/city/city_building.gd CityBuilding.validate): root metadata in the glTF scene
        # extras, Base always, Shaft_<n> (floor_from / floor_to, <= 4 storeys), Roof, ShadowProxy above 12 m
        names = set(meshes)
        bad = [n for n in names if not TOWER_RE.match(n)]
        if bad:
            probs.append("unexpected nodes %s (W0: Base / Shaft_<n> / Roof / ShadowProxy)" % bad)
        if "Base" not in names:
            probs.append("Base missing")
        root = (g.get("scenes") or [{}])[g.get("scene", 0)].get("extras", {})
        for k in ROOT_META:
            if k not in root:
                probs.append("root (scene extras) lacks %s" % k)
        if root.get("floor_h") and not (2.4 <= root["floor_h"] <= 6.0):
            probs.append("floor_h %.2f outside 2.4-6.0" % root["floor_h"])
        if root.get("ground_h") and root.get("floor_h") and not (0.8 * root["floor_h"] <= root["ground_h"] <= 8.0):
            probs.append("ground_h %.2f outside %.1f-8.0" % (root["ground_h"], 0.8 * root["floor_h"]))
        shafts = sorted(int(n.rsplit("_", 1)[1]) for n in names if n.startswith("Shaft_"))
        if shafts != list(range(len(shafts))):
            probs.append("Shaft_<n> not contiguous: %s" % shafts)
        for n in names:
            e = extras_of(g, n)
            if n.startswith("Shaft_"):
                if "floor_from" not in e or "floor_to" not in e:
                    probs.append("%s lacks floor_from / floor_to" % n)
                elif e["floor_to"] - e["floor_from"] + 1 > 4:
                    probs.append("%s spans %d storeys (<= 4)" % (n, e["floor_to"] - e["floor_from"] + 1))
        top = mx.z
        sh = meshes.get("ShadowProxy")
        if top > 12.0 and sh is None:
            probs.append("taller than 12 m (%.0f m) without ShadowProxy" % top)
        if sh is not None:
            if not (12 <= W.tri_count(sh) <= 400):
                probs.append("ShadowProxy has %d tris (12-400)" % W.tri_count(sh))
            if not extras_of(g, "ShadowProxy").get("shadow_only"):
                probs.append("ShadowProxy lacks shadow_only")
        if fam == "towers":
            for req in ("Roof", "ShadowProxy", "Shaft_0"):
                if req not in names:
                    probs.append("%s missing" % req)
            if root.get("height") and not (60.0 <= root["height"] <= 106.0):
                probs.append("tower height %.1f m outside 63-104 m (+-3)" % root["height"])
        if "floor_h" in root and "ground_h" in root:
            st = storey_table(root)
            vis = [o for o in objs if o.type == "MESH" and o.name != "ShadowProxy"]
            probs += CR.closed_problems(vis, st) + slab_problems(vis, st) + CR.cut_view_problems(vis, st)
    elif fam == "vehicles":
        if "Body" not in meshes or set(meshes) - {"Body", "Glass"}:
            probs.append("nodes %s (expected Body [+ Glass])" % sorted(meshes))
        if "Glass" in meshes and [m.name for m in meshes["Glass"].data.materials] != ["glass"]:
            probs.append("Glass must only use the glass material")
        ex = extras_of(g, "Body")
        for k in ("kind", "model", "variant", "col", "col_center", "col_size", "anchors"):
            if k not in ex:
                probs.append("Body extras lack %s" % k)
        probs += anchor_problems(objs, ex.get("anchors"), ("Loot", "FuelCap"))
        emp = {o.name: o.matrix_world.translation for o in objs if o.type == "EMPTY"}
        for side, sgn in (("L", 1), ("R", -1)):
            h = emp.get("Headlight_" + side)
            if h is not None and (h.y > 0 or h.x * sgn < 0):
                probs.append("Headlight_%s at %s (front = -Y, left = +X)" % (side, tuple(round(x, 2) for x in h)))
    else:
        if "Prop" not in meshes or any(not (n == "Prop" or re.match(r"^Panel(_\d+)?$", n)) for n in meshes):
            probs.append("nodes %s (expected Prop [+ Panel / Panel_<n>])" % sorted(meshes))
        ex = extras_of(g, "Prop")
        for k in ("col", "col_center", "col_size", "anchors"):
            if k not in ex:
                probs.append("Prop extras lack %s" % k)
        probs += anchor_problems(objs, ex.get("anchors"))
        panels = [n for n in meshes if n.startswith("Panel")]
        tps = [n for n in empties if n.startswith("TextPanel")]
        if len(panels) != len(tps):
            probs.append("%d Panel meshes but %d TextPanel anchors" % (len(panels), len(tps)))
        emp = {o.name: o.matrix_world.translation for o in objs if o.type == "EMPTY"}
        for k, v in emp.items():
            if k.startswith("LightPool"):
                la = emp.get(k.replace("LightPool", "LightAnchor"))
                if la is None or abs(v.z) > 0.05 or (Vector((la.x, la.y)) - Vector((v.x, v.y))).length > 1.5:
                    probs.append("%s must lie on the ground near (<= 1.5 m) its LightAnchor" % k)
        if ex.get("col") == "cylinder":
            size, cen = ex.get("col_size") or [0, 0], ex.get("col_center") or [0, 0, 0]
            if size[0] > 0.4 or abs(cen[0]) > 0.05 or abs(cen[2]) > 0.05:
                probs.append("pole prop: origin must be the post's base and the cylinder the post (r %.2f, centre %s)"
                             % (size[0], cen))
    return probs


def storey_table(ex):
    fh, gh = ex["floor_h"], ex["ground_h"]
    levels = [round(gh + k * fh, 4) for k in range(ex["floors"] - 1)]
    return {"floor_h": fh, "ground_h": gh, "levels": levels, "floors": ex["floors"], "roof_z": ex["roof_z"]}


def provenance_problems(rel, entry, tpm, lock):
    probs = []
    if entry is None:
        return ["not in assets/models/city/manifest.json"]
    for s in entry.get("sources", []):
        if s["pack"] == "procedural":
            if rel not in tpm.get("procedural_outputs", []):
                probs.append("procedural output not listed in assets/third_party/manifest.json")
            continue
        p = tpm["packs"].get(s["pack"])
        if p is None:
            probs.append("pack %s not in assets/third_party/manifest.json" % s["pack"])
            continue
        f = next((f for f in p["files"] if f["file"] == s["file"]), None)
        locked = lock["packs"][s["pack"]]["files"].get(s["file"], {}).get("sha256")
        if f is None or rel not in f.get("used_by", []):
            probs.append("%s/%s does not list this output" % (s["pack"], s["file"]))
        elif f["sha256"] != locked or s["sha256"] != locked:
            probs.append("%s/%s sha256 differs from the lock" % (s["pack"], s["file"]))
        if not (TP / p["license_file"]).exists():
            probs.append("licence %s missing" % p["license_file"])
        if p["license"] not in ("CC0-1.0", "MIT", "BSD-2-Clause", "BSD-3-Clause"):
            probs.append("licence %s not allowed" % p["license"])
    return probs


def verify(path, rel, fam, manifest, tpm, lock, gamut):
    name = rel.replace("res://assets/models/city/", "")
    g, binary = VA.load_glb(path)
    probs = gltf_city_problems(g, binary, gamut)
    tris = VA.glb_tris(path)
    if tris > BUDGET[fam]:
        probs.append("%d tris > %d (%s budget)" % (tris, BUDGET[fam], fam))
    if not Path(str(path) + ".import").exists():
        probs.append("no .import next to the .glb")
    objs = reimport(path)
    probs += family_problems(fam, name, g, objs)
    vis = [o for o in objs if o.type == "MESH" and o.name != "ShadowProxy"]
    probs += backface_problems_city(vis)
    probs += provenance_problems(rel, manifest.get("assets", {}).get(Path(name).stem), tpm, lock)
    surf = sum(len(m["primitives"]) for m in g["meshes"])
    if probs:
        return False, "FAIL city/%s: %s" % (name, "; ".join(probs)), tris
    return True, "OK   city/%-28s tris=%-6d surfaces=%-2d %s" % (name, tris, surf, VA.ao_summary(g, binary)), tris


def main(argv=()):
    want = [a for a in argv if not a.startswith("-")]
    man_path = CITY / "manifest.json"
    manifest = json.loads(man_path.read_text()) if man_path.exists() else {}
    tpm = json.loads((TP / "manifest.json").read_text()) if (TP / "manifest.json").exists() else {"packs": {}}
    lock = fetch.load_sources()
    gamut = palette_gamut()
    files = sorted(CITY.glob("*/*.glb"))
    failures, total_bytes, per_fam = 0, 0, {}
    for f in files:
        fam = f.parent.name
        rel = "res://" + str(f.relative_to(ROOT)).replace(os.sep, "/")
        total_bytes += f.stat().st_size
        if want and not any(w == fam or f.stem.startswith(w) for w in want):
            continue
        if fam not in BUDGET:
            print("FAIL city/%s/%s: unknown family" % (fam, f.name))
            failures += 1
            continue
        ok, msg, tris = verify(f, rel, fam, manifest, tpm, lock, gamut)
        per_fam.setdefault(fam, []).append(tris)
        print(msg, flush=True)
        failures += 0 if ok else 1
    listed = set(manifest.get("assets", {}))
    stems = {f.stem for f in files}
    if listed - stems:
        print("FAIL city manifest lists missing files: %s" % sorted(listed - stems))
        failures += 1
    for fam, t in sorted(per_fam.items()):
        print("     city/%-9s %3d assets, tris min/median/max %d / %d / %d" % (fam, len(t), min(t), sorted(t)[len(t) // 2],
                                                                           max(t)))
    ok_size = total_bytes <= SIZE_LIMIT
    print("%s city set size %.1f MB (limit %.0f MB), %d files" % ("OK  " if ok_size else "FAIL", total_bytes / 1e6,
                                                                SIZE_LIMIT / 1e6, len(files)))
    failures += 0 if ok_size else 1
    probs = []
    for pack, p in tpm.get("packs", {}).items():
        if not (TP / p["license_file"]).exists():
            probs.append("licence file %s missing" % p["license_file"])
    for p in probs:
        print("FAIL third_party: %s" % p)
    failures += len(probs)
    print("city: %s" % ("ALL OK" if failures == 0 else "%d FAILURES" % failures))
    return failures


if __name__ == "__main__":
    sys.exit(1 if main(sys.argv[1:]) else 0)
