"""Kit buildings (ASSET_SPEC_V2 §8, started in M3): every template of kits/templates/*.json in each of its styles ->
assets/models/buildings/<style>/<id>.glb (+ .import), sources/<id>__<style>.blend.

    cd winter-survival/blender && python3 kits/build_buildings.py [template_id ...]

The kit itself (grid, modules, styles, fusion per cut group, stubs, slabs, stairs, collision, doors / windows /
spawns, ShadowProxy) is lib/kit.py; this script only loops over templates x styles and exports. M3 shipped the test
house `house_small_A`; M6a (cut-ready kit) adds `house_small_B` (6 x 8, 1 storey), `house_two_story_A` (8 x 10,
2 storeys + stair), `shop_general` (10 x 12, shopfronts + awnings, flat roof) and `apartment_small` (10 x 10,
3 storeys, scissor stairs, flat roof) in wood_blue / brick / concrete (see each template's "style"). The templates are
also copied verbatim to ../data/buildings/templates/ (read by the game's street / settlement code).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import bpy  # noqa: E402,F401

from lib import export  # noqa: E402
from lib import kit  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

TEMPLATES = os.path.join(HERE, "templates")


def templates():
    out = {}
    for f in sorted(os.listdir(TEMPLATES)):
        if f.endswith(".json"):
            t = json.load(open(os.path.join(TEMPLATES, f)))
            out[t["id"]] = t
    return out


def build_one(tpl, style):
    lp.new_scene()
    summary = kit.build(tpl, style)
    kit.bake_cut_ao(distance=1.2, samples=64)
    export.save_and_export(tpl["id"], subdir="buildings/%s" % style, blend_name="%s__%s" % (tpl["id"], style),
                           ao=dict(distance=1.2, samples=64, ground=True), import_kind="prop")
    return summary


def copy_templates():
    """data/buildings/templates/<id>.json = verbatim copies (the game reads the lot data: kind, footprint, floors,
    styles, signs, rooms) -- only rewritten when they differ."""
    out = os.path.join(os.path.dirname(os.path.dirname(HERE)), "data", "buildings", "templates")
    os.makedirs(out, exist_ok=True)
    for f in sorted(os.listdir(TEMPLATES)):
        if f.endswith(".json"):
            src = open(os.path.join(TEMPLATES, f)).read()
            dst = os.path.join(out, f)
            if not os.path.exists(dst) or open(dst).read() != src:
                open(dst, "w").write(src)


def main(ids=None):
    for tid, tpl in templates().items():
        if ids and tid not in ids:
            continue
        for style in tpl["style"]:
            build_one(tpl, style)
    copy_templates()


if __name__ == "__main__":
    main(sys.argv[1:] or None)
