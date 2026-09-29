#!/usr/bin/env python3
"""G2b smoke / flame sprites from Kenney's *Particle Pack* 1.1 (CC0) — PLAN v3.8.2 G2b «humo (sprites CC0)».

    python3 tools/fetch_fx_sprites.py            # download the pinned files (cache), verify SHA-256, rebuild the atlases
    python3 tools/fetch_fx_sprites.py --check    # rebuild in memory from the cache and compare with assets/ (exit 1)

kenney.nl is not reachable from the build machines; the files come from the same GitHub mirror as A1's city kits
(assets/third_party/README.md): series-ai/jam-ready-assets at a pinned commit, Git LFS objects from
media.githubusercontent.com. Every source file is checked against its SHA-256 (= the LFS oid in the mirror's tree =
the upstream file). The source PNGs are cached outside the repository ($VENTISCA_TP_CACHE or
~/.cache/ventisca/third_party) and never committed; only the two small atlases are:

  assets/textures/fx/smoke_atlas.png   2 × 2 frames of 128², white RGB + alpha (smoke_01, 04, 07, 08)
  assets/textures/fx/flame_atlas.png   2 × 2 frames of 128², white RGB + alpha (flame_05, 06, 01, 03)

Processing: the sprites are grey-on-transparent; alpha' = alpha × luminance normalised to the frame's peak (so the soft
grey edges fade and the core is opaque), RGB = white (the particle colour ramps tint them), resized to 128² with Lanczos,
packed row-major (frame 0 top-left).
The pack's License.txt is copied next to them with the manifest (provenance: repo, commit, path, SHA-256).
"""
import argparse
import hashlib
import io
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures" / "fx"
REPO = "series-ai/jam-ready-assets"
COMMIT = "f8206b38e4355a8b2a490e3032000d2a84883a0f"
PACK_ROOT = "kenney-particle-pack/2D/misc"
RAW = "https://raw.githubusercontent.com/%s/%s/%s"
MEDIA = "https://media.githubusercontent.com/media/%s/%s/%s"
FILES = {
    "License.txt": None,
    "PNG (Transparent)/smoke_01.png": "e8724c219e8d35859167fc0a7e207e13c72ccf0c29704909b9bb3d3dc71c6cf7",
    "PNG (Transparent)/smoke_04.png": None,
    "PNG (Transparent)/smoke_07.png": None,
    "PNG (Transparent)/smoke_08.png": None,
    "PNG (Transparent)/flame_05.png": None,
    "PNG (Transparent)/flame_06.png": None,
    "PNG (Transparent)/flame_01.png": None,
    "PNG (Transparent)/flame_03.png": None,
}
ATLASES = {
    "smoke_atlas.png": ["smoke_01", "smoke_04", "smoke_07", "smoke_08"],
    "flame_atlas.png": ["flame_05", "flame_06", "flame_01", "flame_03"],
}
FRAME = 128
LOCK = OUT / "sources.lock.json"
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/textures/fx/{name}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def cache_dir():
    base = os.environ.get("VENTISCA_TP_CACHE") or os.path.join(os.path.expanduser("~"), ".cache", "ventisca", "third_party")
    return Path(base) / "kenney-particle-pack" / COMMIT


def sha(data):
    return hashlib.sha256(data).hexdigest()


def _get(url):
    last = None
    for _ in range(4):
        try:
            with urllib.request.urlopen(url, timeout=90) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 — retried, then reported
            last = e
    raise RuntimeError("download failed: %s (%s)" % (url, last))


def fetch(rel, want):
    """Bytes of one pack file at the pinned commit (cache, else download), checked against `want`."""
    local = cache_dir() / rel
    if local.exists():
        data = local.read_bytes()
    else:
        path = urllib.parse.quote("%s/%s" % (PACK_ROOT, rel))
        data = _get(RAW % (REPO, COMMIT, path))
        if data.startswith(b"version https://git-lfs.github.com/spec/v1"):
            data = _get(MEDIA % (REPO, COMMIT, path))
        local.parent.mkdir(parents=True, exist_ok=True)
        local.write_bytes(data)
    if want and sha(data) != want:
        raise SystemExit("SHA-256 mismatch for %s: %s != %s" % (rel, sha(data), want))
    return data


def frame(data):
    im = Image.open(io.BytesIO(data)).convert("RGBA")
    px = im.load()
    w, h = im.size
    vals = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
            vals.append(a / 255.0 * lum)
    # normalised so the densest texel of each frame is opaque (the pack's grey-on-transparent sprites peak at ~40 %)
    peak = max(max(vals), 1e-6)
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for i, v in enumerate(vals):
        op[i % w, i // w] = (255, 255, 255, int(round(min(1.0, v / peak) * 255.0)))
    return out.resize((FRAME, FRAME), Image.LANCZOS)


def build(lock):
    files = {}
    srcs = {}
    for rel in FILES:
        want = lock.get(rel) or FILES[rel]
        srcs[rel] = fetch(rel, want)
    for name, frames in ATLASES.items():
        atlas = Image.new("RGBA", (FRAME * 2, FRAME * 2), (255, 255, 255, 0))
        for i, fr in enumerate(frames):
            atlas.paste(frame(srcs["PNG (Transparent)/%s.png" % fr]), ((i % 2) * FRAME, (i // 2) * FRAME))
        buf = io.BytesIO()
        atlas.save(buf, format="PNG", optimize=False, compress_level=9)
        files[name] = buf.getvalue()
    files["LICENSE-kenney-particle-pack.txt"] = srcs["License.txt"]
    manifest = {
        "_doc": "G2b particle sprites (tools/fetch_fx_sprites.py). CC0 1.0: no attribution required; credited anyway.",
        "pack": {"title": "Particle Pack", "version": "1.1", "author": "Kenney (www.kenney.nl)", "license": "CC0-1.0",
                 "official_url": "https://kenney.nl/assets/particle-pack",
                 "license_file": "LICENSE-kenney-particle-pack.txt"},
        "fetched_from": {"repo": "https://github.com/" + REPO, "commit": COMMIT, "path": PACK_ROOT,
                         "via": "git-lfs (media.githubusercontent.com)",
                         "custody": "third-party curated mirror (the same as A1's city kits); LFS oid = upstream file hash"},
        "files": [{"file": rel, "sha256": sha(srcs[rel])} for rel in FILES],
        "outputs": [{"file": "res://assets/textures/fx/" + n, "frames": ATLASES[n], "frame_px": FRAME, "grid": [2, 2],
                     "sha256": sha(files[n]),
                     "modifications": "alpha x luminance normalised to the frame peak, RGB white, Lanczos to 128 px, 2 x 2 atlas"} for n in ATLASES],
    }
    files["manifest.json"] = (json.dumps(manifest, indent=1) + "\n").encode()
    return files, {rel: sha(srcs[rel]) for rel in FILES}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    lock = json.loads(LOCK.read_text()) if LOCK.exists() else {}
    files, hashes = build(lock)
    if a.check:
        bad = [f for f, d in files.items() if not (OUT / f).exists() or (OUT / f).read_bytes() != d]
        print("fetch_fx_sprites --check: %s" % ("OK" if not bad else "DIFFER: %s" % bad))
        return 1 if bad else 0
    OUT.mkdir(parents=True, exist_ok=True)
    for f, d in files.items():
        (OUT / f).write_bytes(d)
        if f.endswith(".png") and not (OUT / (f + ".import")).exists():
            (OUT / (f + ".import")).write_text(IMPORT.format(name=f))
    LOCK.write_text(json.dumps(hashes, indent=1, sort_keys=True) + "\n")
    print("wrote %s" % ", ".join(sorted(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
