"""Build every VENTISCA asset (ASSET_SPEC_V2 §1) and the rendered item icons (icons/build_icons.py, after the models
it reuses), run the lib self-tests (lib/rig.py, lib/anim.py),
then verify_assets.py (props, slice models) and verify_chars.py (characters + animation libraries).

    cd winter-survival/blender && python3 build_all.py        # exit code 0 = everything built and ALL OK
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
    "build_optional", "icons.build_icons",
]
VERIFIERS = ["verify_assets", "verify_chars"]


def main():
    t0 = time.time()
    failed = []
    for name in SCRIPTS:
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
    for v in VERIFIERS:
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
    sys.exit(main())
