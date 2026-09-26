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
    # M4: zombies (skeletal, share the survivor rig), zombie + combat animation libraries, melee weapons, gore-lite props
    "zombies.build_zombie", "anims.build_zombie_anims", "anims.build_combat", "weapons.build_weapons",
    "props.build_gore",
    "icons.build_icons",
]
M4_SCRIPTS = ("zombies.build_zombie", "anims.build_zombie_anims", "anims.build_combat", "weapons.build_weapons",
              "props.build_gore", "icons.build_icons")
VERIFIERS = ["verify_assets", "verify_kits", "verify_chars"]


def main(argv=()):
    argv = list(argv)
    only = None
    if "--only" in argv:
        words = argv[argv.index("--only") + 1].split(",")
        only = [n for n in SCRIPTS if any(w in n or (w == "m4" and n in M4_SCRIPTS) for w in words)]
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
    for v in (VERIFIERS if run_verifiers else []):
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
