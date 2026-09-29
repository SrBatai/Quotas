# Contact sheet helper (Pillow): python3 tools/contact.py out.png "label=path" ...  References wider than 2000 px get their phone side bars cropped.
import sys
from PIL import Image, ImageDraw
# usage: contact.py out.png label1=path1 label2=path2 ...  (2 columns grid, each cell 640x360 + label)
out = sys.argv[1]
items = [a.split("=", 1) for a in sys.argv[2:]]
W, H = 640, 360
cols = 2
rows = (len(items) + cols - 1) // cols
sheet = Image.new("RGB", (cols * W, rows * (H + 18)), (20, 20, 20))
d = ImageDraw.Draw(sheet)
for i, (label, path) in enumerate(items):
    im = Image.open(path).convert("RGB")
    # crop phone-status bars for the references (they are 2510x1156 with black side bars)
    if im.width > 2000:
        im = im.crop((int(im.width*0.09), 0, int(im.width*0.91), im.height))
    im.thumbnail((W, H))
    x = (i % cols) * W
    y = (i // cols) * (H + 18)
    sheet.paste(im, (x, y + 18))
    d.text((x + 4, y + 2), label, fill=(240, 240, 240))
sheet.save(out)
print("wrote", out)
