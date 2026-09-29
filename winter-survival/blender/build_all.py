"""Build every VENTISCA asset (ASSET_SPEC_V2 §1) and the rendered item icons (icons/build_icons.py, after the models
it reuses), run the lib self-tests (lib/rig.py, lib/anim.py),
then verify_assets.py (props, slice models, M3 scatter + POIs), verify_kits.py (kit buildings vs their templates) and
verify_chars.py (characters + animation libraries).

    cd winter-survival/blender && python3 build_all.py        # exit code 0 = everything built and ALL OK
    python3 build_all.py --only zombies,anims,weapons,gore    # incremental: only the scripts whose name contains one
                                                              # of these words (+ the lib self-tests and the verifiers)
    python3 build_all.py --only m4 --no-verify                # "m4" = the M4 families (zombies, zombie / combat anims,
                                                              # weapons, gore, icons); --no-verify skips the verifiers
M4: zombies/build_zombie.py, anims/build_zombie_anims.py, anims/build_combat.py (+ data/anim_events.json),
weapons/build_weapons.py, props/build_gore.py; verify_chars.py covers zombies + the new libraries, verify_assets.py the
weapons / gore.
T2: python3 build_all.py --only t2     rebuilds the firearms (weapons/build_firearms.py), the humanoid_firearms library
(anims/build_firearms.py + data/anim_events.json), the loot (props/build_loot.py), the W1 world props
(world/build_world_props.py) and the icons, then runs the verifiers.
M6a: python3 build_all.py --only m6a   rebuilds the cut-ready kit buildings (kits/build_buildings.py: 5 templates x
2 styles, + data/buildings/templates/ copies) and the diegetic signs (props/build_signs.py: mesh font + boards), then
runs the verifiers (verify_kits.py: cut-ready contract; verify_assets.py: signs/*).
M6b: python3 build_all.py --only m6b   rebuilds the kit buildings (the 6 new templates: house_small_C,
house_two_story_B, garage, gas_station, sawmill_shed, barn + style wood_red) and the village / POI props
(props/build_village_props.py -> props/village/*, 30 props + manifest.json), then runs the verifiers.
A1: python3 build_all.py --only city   rebuilds the winterized CC0 city set (third_party/build_city.py: fetches the
pinned sources first, ~2.5 min) and runs verify_assets.py, whose city part is third_party/verify_city.py.
"""
import importlib
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402,F401

# P0-heavy families first so a late failure never blocks the essentials.
SCRIPTS = [
    "build_player", "chars.build_survivor", "anims.build_loco", "build_animals", "build_trees", "build_rocks",
    "build_plants", "build_pickups", "build_fire", "build_tools", "build_cabin", "build_furniture", "build_props",
    "build_optional",
    # M3: MultiMesh scatter families, icicles, forest POIs, building kit test house
    "vegetation.build_trees", "vegetation.build_bushes", "vegetation.build_rocks", "vegetation.build_snow",
    "vegetation.build_logs", "props.build_icicles", "poi.build_cabin_small", "poi.build_lookout_tower",
    "poi.build_campsite_remains", "kits.build_buildings",
    # M6a: diegetic signs (mesh font + street / house number / shop / road boards)
    "props.build_signs",
    # M6b: village and POI props (street furniture, fences, barricades, gas station, farm, sawmill)
    "props.build_village_props",
    # M4: zombies (skeletal, share the survivor rig), zombie + combat animation libraries, melee weapons, gore-lite props
    "zombies.build_zombie", "anims.build_zombie_anims", "anims.build_combat", "weapons.build_weapons",
    "props.build_gore",
    # T2: firearms / bow / arrow / muzzle flash, firearm animation library, loot containers + pickups, W1 world props
    "weapons.build_firearms", "anims.build_firearms", "props.build_loot", "world.build_world_props",
    "icons.build_icons",
    # A1: winterized CC0 city set of Altavega (pinned third-party sources -> assets/models/city/**, manifests, licences)
    "third_party.build_city",
]
M4_SCRIPTS = ("zombies.build_zombie", "anims.build_zombie_anims", "anims.build_combat", "weapons.build_weapons",
              "props.build_gore", "icons.build_icons")
T2_SCRIPTS = ("weapons.build_firearms", "anims.build_firearms", "props.build_loot", "world.build_world_props",
              "icons.build_icons")
M6A_SCRIPTS = ("kits.build_buildings", "props.build_signs")
M6B_SCRIPTS = ("kits.build_buildings", "props.build_village_props")
VERIFIERS = ["verify_assets", "verify_kits", "verify_chars"]
CITY_SCRIPTS = ("third_party.build_city",)


def main(argv=()):
    argv = list(argv)
    only = None
    verifiers = VERIFIERS
    if "--only" in argv:
        words = argv[argv.index("--only") + 1].split(",")
        only = [n for n in SCRIPTS if any(w in n or (w == "m4" and n in M4_SCRIPTS) or (w == "t2" and n in T2_SCRIPTS)
                                          or (w == "m6a" and n in M6A_SCRIPTS) or (w == "m6b" and n in M6B_SCRIPTS)
                                          for w in words)]
        if only and all(n in CITY_SCRIPTS for n in only):
            verifiers = ["verify_assets"]      # the city set: verify_assets (it runs third_party/verify_city.py)
    run_verifiers = "--no-verify" not in argv
    t0 = time.time()
    failed = []
    for name in (SCRIPTS if only is None else only):
        try:
            importlib.import_module(name).main()
        except Exception:
            traceback.print_exc()
            failed.append(name)
    print("build finished in %.1fs" % (time.time() - t0))
    lib_failed = []
    for mod in ("lib.rig", "lib.anim"):
        try:
            if importlib.import_module(mod).selftest():
                lib_failed.append(mod)
        except Exception:
            traceback.print_exc()
            lib_failed.append(mod)
    bad = []
    for v in (verifiers if run_verifiers else []):
        print("== %s" % v)
        try:
            if importlib.import_module(v).main():
                bad.append(v)
        except Exception:
            traceback.print_exc()
            bad.append(v)
    if failed:
        print("BUILD SCRIPT FAILURES: %s" % ", ".join(failed))
    if lib_failed:
        print("LIB SELFTEST FAILURES: %s" % ", ".join(lib_failed))
    if bad:
        print("VERIFIER FAILURES: %s" % ", ".join(bad))
    n = len(failed) + len(lib_failed) + len(bad)
    print("ALL OK" if n == 0 else "%d FAILURES" % n)
    return 0 if n == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
