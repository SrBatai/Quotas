#!/usr/bin/env python3
"""Contact sheet (Pillow): python3 tools/contact_sheet.py out.png COLS "label=path" ...
Cells are 640x360 + label; reference phone captures (wider than 2000 px) get their side bars cropped.
Used by G1 to compare reference / before / after per preset (docs/research/06_graficos_render.md)."""
import sys
from PIL import Image, ImageDraw

out = sys.argv[1]
cols = int(sys.argv[2])
items = [a.split("=", 1) for a in sys.argv[3:]]
W, H = 640, 360
rows = (len(items) + cols - 1) // cols
sheet = Image.new("RGB", (cols * W, rows * (H + 18)), (20, 20, 20))
d = ImageDraw.Draw(sheet)
for i, (label, path) in enumerate(items):
    x = (i % cols) * W
    y = (i // cols) * (H + 18)
    if path:
        im = Image.open(path).convert("RGB")
        if im.width > 2000:
            im = im.crop((int(im.width * 0.09), 0, int(im.width * 0.91), im.height))
        im.thumbnail((W, H))
        sheet.paste(im, (x, y + 18))
    d.text((x + 4, y + 2), label, fill=(240, 240, 240))
sheet.save(out)
print("wrote", out)
