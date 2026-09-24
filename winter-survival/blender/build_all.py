"""Build every VENTISCA asset (ASSET_SPEC §1), then run verify_assets.py.

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
    "build_player", "build_animals", "build_trees", "build_rocks", "build_plants", "build_pickups",
    "build_fire", "build_tools", "build_cabin", "build_furniture", "build_props", "build_optional",
]


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
    import verify_assets
    code = verify_assets.main()
    if failed:
        print("BUILD SCRIPT FAILURES: %s" % ", ".join(failed))
        code = code or 1
    return code


if __name__ == "__main__":
    sys.exit(main())
