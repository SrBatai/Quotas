#!/usr/bin/env python3
"""VENTISCA sound build (S1): renders every shipped sound into assets/audio/<group>/*.ogg, then writes
assets/audio/manifest.json (channels, length, loudness, category of each file: the AudioManager expands the event
table's globs against it and tests/unit/audio_test.gd checks it) and assets/audio/LICENSES.md (every file → the
CC0 recordings it was made from, or "original").

    tools/audio/fetch_sources.sh          # once: CC0 recordings into ~/.cache/ventisca/audio_src
    python3 tools/audio/build_audio.py    # all groups
    python3 tools/audio/build_audio.py weapons ui   # only these recipe modules (the manifest keeps the others)

Needs numpy, scipy, pyloudnorm and ffmpeg with libvorbis (pip install numpy scipy pyloudnorm imageio-ffmpeg).
Mixing rules (docs/AUDIO.md §5): every file is DC-free, trimmed, faded, peaks ≤ −1 dBFS; one-shots are levelled
per category on their loudest 400 ms (momentary max LUFS), beds / loops on integrated LUFS (≈ −20); 3D point
sources are mono, beds and stingers stereo. Deterministic: fixed seeds per module.
"""
from __future__ import annotations

import importlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import audiolib as A  # noqa: E402
import sources  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "audio")
MANIFEST = os.path.join(OUT_DIR, "manifest.json")
LICENSES = os.path.join(OUT_DIR, "LICENSES.md")
MODULES = ["weapons", "creatures", "player", "world", "ambience", "ui"]
# files other lanes own inside assets/audio (never deleted, listed in the manifest as they are)
FOREIGN = {"ui/ui_zone_discover.wav"}

# category → (level mode, target, OGG quality, channels)   mode: "mom" = max momentary LUFS, "int" = integrated
CATEGORIES = {
    "weapons_close": ("mom", -9.0, 5.0, 1),
    "weapons_far": ("mom", -14.0, 3.0, 1),
    "weapons_tail": ("mom", -19.0, 2.0, 1),
    "weapons_mech": ("mom", -22.0, 4.0, 1),
    "weapons_casing": ("mom", -24.0, 3.0, 1),
    "weapons_bow": ("mom", -20.0, 4.0, 1),
    "weapons_impact": ("mom", -18.0, 4.0, 1),
    "creature_vocal": ("mom", -16.0, 3.0, 1),
    "creature_fx": ("mom", -16.0, 3.0, 1),
    "footstep": ("mom", -22.0, 3.0, 1),
    "foley": ("mom", -20.0, 3.0, 1),
    "melee": ("mom", -17.0, 4.0, 1),
    "player_vocal": ("mom", -18.0, 3.0, 1),
    "world": ("mom", -18.0, 3.0, 1),
    "world_loop": ("int", -22.0, 2.0, 1),
    "amb_bed": ("int", -20.0, 1.0, 2),
    "amb_layer": ("int", -24.0, 1.0, 2),
    "amb_oneshot": ("mom", -20.0, 2.0, 1),
    "ui": ("mom", -22.0, 4.0, 1),
    "stinger": ("mom", -16.0, 3.0, 2),
}


class Build:
    def __init__(self) -> None:
        self.files: dict[str, dict] = {}
        self.sources: dict[str, list[str]] = {}
        self._module = ""

    def out(self, name: str, x: np.ndarray, cat: str, used: list[str] | None = None, loop: bool = False,
            gain_db: float = 0.0, notes: str = "") -> None:
        """Levels, cleans and writes one file (name without extension, e.g. 'weapons/pistol_close_01')."""
        if cat not in CATEGORIES:
            raise KeyError(f"{name}: unknown category {cat}")
        mode, target, quality, ch = CATEGORIES[cat]
        y = np.asarray(x, dtype=np.float64)
        if ch == 1 and y.ndim == 2:
            y = y.mean(axis=1)
        if ch == 2 and y.ndim == 1:
            y = np.stack([y, y], axis=1)
        if not np.all(np.isfinite(y)):
            raise ValueError(f"{name}: NaN / inf")
        if not loop:
            y = A.finish(y)
        y = A.normalize(y, lufs=target + gain_db, mode="momentary" if mode == "mom" else "integrated", peak_cap=-1.0)
        rel = name + ".ogg"
        path = os.path.join(OUT_DIR, rel)
        A.write_ogg(path, y, quality)
        lufs = A.momentary_max_lufs(y) if mode == "mom" else A.integrated_lufs(y)
        self.files[rel] = {"cat": cat, "ch": ch, "dur": round(len(y) / A.SR, 3), "loop": loop,
                           "lufs": round(float(lufs), 1), "peak": round(A.peak_db(y), 1),
                           "bytes": os.path.getsize(path), "module": self._module}
        self.sources[rel] = sorted(set(used or []) | set(sources.CURRENT))
        sources.CURRENT.clear()
        if notes:
            self.files[rel]["notes"] = notes


def main(argv: list[str]) -> int:
    only = [a for a in argv if not a.startswith("-")]
    mods = only or MODULES
    old: dict = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            old = json.load(f)
    b = Build()
    t0 = time.time()
    for m in mods:
        b._module = m
        sources.CURRENT.clear()
        mod = importlib.import_module("recipes_" + m)
        t = time.time()
        mod.build(b.out)
        print(f"{m:10s} {sum(1 for v in b.files.values() if v['module'] == m):4d} files  {time.time() - t:5.1f} s")
    # keep the manifest entries of modules not rebuilt this time
    files = {k: v for k, v in old.get("files", {}).items() if v.get("module") not in mods and v.get("module")}
    srcs = {k: v for k, v in old.get("sources", {}).items() if k in files}
    files.update(b.files)
    srcs.update(b.sources)
    # delete stale .ogg of the rebuilt modules (never the foreign files)
    for m in mods:
        for k, v in list(old.get("files", {}).items()):
            if v.get("module") == m and k not in b.files and k not in FOREIGN:
                for p in (os.path.join(OUT_DIR, k), os.path.join(OUT_DIR, k + ".import")):
                    if os.path.exists(p):
                        os.remove(p)
    for k in FOREIGN:
        p = os.path.join(OUT_DIR, k)
        if os.path.exists(p):
            x = A.load(p)
            files[k] = {"cat": "ui", "ch": 1, "dur": round(len(x) / A.SR, 3), "loop": False,
                        "lufs": round(float(A.momentary_max_lufs(x)), 1), "peak": round(A.peak_db(x), 1),
                        "bytes": os.path.getsize(p), "module": "", "owner": "H2 (tools/gen_ui_sounds.py)"}
    rec = dict(old.get("recordings", {}))
    for k, v in sources.USED.items():
        rec[k] = {kk: v[kk] for kk in ("pack", "author", "license", "url", "mirror", "file")}
    used_keys = {s for lst in srcs.values() for s in lst}
    rec = {k: v for k, v in rec.items() if k in used_keys}
    total = sum(v["bytes"] for v in files.values())
    manifest = {"version": 1, "generator": "tools/audio/build_audio.py", "total_bytes": total,
                "files": dict(sorted(files.items())), "sources": dict(sorted(srcs.items())),
                "recordings": dict(sorted(rec.items()))}
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
        f.write("\n")
    write_licenses(manifest)
    print(f"total {len(files)} files, {total / 1e6:.2f} MB, {time.time() - t0:.1f} s")
    return 0


def write_licenses(m: dict) -> None:
    rec = m["recordings"]
    lines = ["# VENTISCA — audio licences (assets/audio/)", "",
             "Every file here is **CC0 1.0 / public domain** or original work of the VENTISCA project dedicated to "
             "the public domain under **CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/).",
             "Written by `tools/audio/build_audio.py` from the recipes in `tools/audio/recipes_*.py`; do not edit by "
             "hand. Sources are fetched by `tools/audio/fetch_sources.sh` (pinned commits of two GitHub mirrors, "
             "because the original sites are not reachable from the build machine):", "",
             f"- Kenney packs: {sources.KENNEY_MIRROR} — each pack ships a License.txt «Creative Commons Zero, CC0».",
             f"- OpenGameArt packs published under CC0: {sources.OGA_MIRROR} — one pack.json per pack with the "
             "author, `\"license\": \"CC0-1.0\"` and the OpenGameArt page.", "",
             "«original» = synthesised from scratch by the recipe (no recording). A file made from recordings was "
             "processed (trimmed, filtered, pitched, layered, levelled): the list names every recording it uses.", "",
             "## Recordings used", "", "| Recording | Pack | Author | Licence | Page |", "|---|---|---|---|---|"]
    for k, v in sorted(rec.items()):
        lines.append(f"| `{v['file']}` | {v['pack']} | {v['author']} | {v['license']} | {v['url']} |")
    lines += ["", "## Files", "", "| File | Made from |", "|---|---|"]
    for f, v in m["files"].items():
        if v.get("owner"):
            lines.append(f"| `{f}` | {v['owner']}: original, CC0 1.0 (see ui/LICENSE.txt) |")
            continue
        s = m["sources"].get(f, [])
        lines.append(f"| `{f}` | " + ("original (CC0)" if not s else ", ".join(f"`{x}`" for x in s)) + " |")
    lines.append("")
    with open(LICENSES, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
