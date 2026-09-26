"""Kit buildings (ASSET_SPEC_V2 §8, started in M3): every template of kits/templates/*.json in each of its styles ->
assets/models/buildings/<style>/<id>.glb (+ .import), sources/<id>__<style>.blend.

    cd winter-survival/blender && python3 kits/build_buildings.py [template_id ...]

The kit itself (grid, modules, styles, fusion per cut group, stubs, collision, doors / windows / spawns) is
lib/kit.py; this script only loops over templates x styles and exports. M3 ships the test house `house_small_A`
(8 x 10 m, 1 storey, porch, partition, chimney) in `wood_blue` and `brick`.
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


def main(ids=None):
    for tid, tpl in templates().items():
        if ids and tid not in ids:
            continue
        for style in tpl["style"]:
            build_one(tpl, style)


if __name__ == "__main__":
    main(sys.argv[1:] or None)
