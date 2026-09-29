#!/usr/bin/env python3
"""Preview of the W1 macro map (data/world/macro_map.png + macro_roads.json): biome colours, hill shading, roads,
the playable walls (red) and the valley square |x|, |z| < 1152 m (yellow). Needs Pillow + numpy.
    python3 tools/macro_preview.py out.png [scale]
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ORIGIN = -1536.0
PX = 8.0
BIOME_STEP = 16
PALETTE = {0: (40, 80, 50), 1: (60, 110, 70), 2: (200, 200, 170), 3: (150, 200, 230), 4: (140, 140, 150),
           5: (180, 120, 90), 6: (170, 90, 60), 7: (200, 150, 110), 8: (90, 90, 140), 9: (160, 110, 110),
           10: (210, 180, 140), 11: (130, 120, 110), 12: (100, 110, 140), 13: (170, 170, 120), 14: (230, 230, 240),
           15: (120, 180, 220)}
ROAD_COLOURS = {"highway": (255, 60, 40), "road": (255, 160, 40), "track": (200, 200, 0), "avenue": (255, 90, 200),
                "rail": (20, 20, 20)}


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else "macro_preview.png"
    scale = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    im = np.array(Image.open(os.path.join(ROOT, "data/world/macro_map.png")).convert("RGBA")).astype(np.int64)
    rel = (im[:, :, 0] * 256 + im[:, :, 3] - 8192) * 160.0 / 65535.0
    biome = np.round(im[:, :, 1] / BIOME_STEP).astype(int)
    n = rel.shape[0]
    col = np.zeros((n, n, 3))
    for b, c in PALETTE.items():
        col[biome == b] = c
    gy, gx = np.gradient(rel, PX)
    shade = np.clip(0.75 + (-gx * 0.7 - gy * 0.7) * 0.6, 0.35, 1.25)
    h01 = np.clip(rel / 140.0, 0, 1)
    rgb = np.clip(col * shade[:, :, None] * (0.75 + 0.35 * h01[:, :, None]), 0, 255).astype(np.uint8)
    img = Image.fromarray(rgb).resize((n * scale, n * scale), Image.NEAREST)
    d = ImageDraw.Draw(img)

    def p(x: float, z: float) -> tuple:
        return ((x - ORIGIN) / PX * scale, (z - ORIGIN) / PX * scale)

    roads = json.load(open(os.path.join(ROOT, "data/world/macro_roads.json")))["roads"]
    for r in roads:
        d.line([p(*q) for q in r["points"]], fill=ROAD_COLOURS.get(r["kind"], (255, 255, 255)), width=2)
    for w in (-1450, 4420):
        d.line([p(w, -1450), p(w, 4420)], fill=(255, 0, 0))
        d.line([p(-1450, w), p(4420, w)], fill=(255, 0, 0))
    d.rectangle([p(-1152, -1152), p(1152, 1152)], outline=(255, 255, 0))
    img.save(out)
    print("macro preview %s: height %.1f … %.1f m" % (out, rel.min(), rel.max()))


if __name__ == "__main__":
    main()
