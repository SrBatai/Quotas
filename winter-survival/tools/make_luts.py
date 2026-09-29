#!/usr/bin/env python3
"""G2b colour grading LUTs (PLAN v3.8.2 G2b, docs/research/08_graficos_g2.md §3.7).

Writes the 32³ 3D LUTs the game blends on the CPU (scripts/world/atmosphere/lut_grade.gd) and feeds to
Environment.adjustment_color_correction (Forward+, Compatibility and the Web build alike):

    python3 tools/make_luts.py                 # (re)write assets/luts/*.png + assets/luts/luts.json
    python3 tools/make_luts.py --check         # rebuild in memory, compare with the files (pixels ±1/255; exit 1 if not)
    python3 tools/make_luts.py --preview in.jpg out.jpg   # every LUT applied to a capture (review sheet)

Layout (the usual "horizontal strip"): a 1024 × 32 PNG, slice z = blue along x in blocks of 32, red = x within the
block, green = y (top row = 0). Texel (r, g, b) holds the graded colour of the display (sRGB-encoded) input
(r/31, g/31, b/31): Godot's tonemap samples the LUT with the tonemapped sRGB colour as the texture coordinate
(checked in 4.7.2, both renderers), so a texel sits at the input i/31 (exact at 0, 0.5 and 1; ±2/255 in between).
The alpha channel is 128 on purpose: the CPU blend (Image.blend_rect with src alpha 128/255 after an
Image.adjust_bcs pre-scale, LutGrade) needs a constant half alpha; the tonemapper ignores alpha.

Grading ops per LUT (all deterministic, numpy): ASC-CDL slope / offset / power per channel in display space, then in
OKLab: shadow / highlight tint (a, b shifts weighted by lightness), saturation by lightness band (shadows / mids /
highlights — warm lights keep their colour at night), contrast around a pivot and a black lift (fog / overcast).
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "luts"
N = 32
ALPHA = 128

# Order = LUT id in the game (LutGrade.NAMES). Tuned on the G2b contact sheet (docs/screenshots/g2b/).
LUTS = {
    # crisp, a touch of contrast, cool shadows and neutral-warm whites: close to the G1 look (the owner approved it)
    "dia_claro": dict(slope=(1.015, 1.0, 0.99), offset=(0.0, 0.0, 0.004), power=(1.0, 1.0, 1.0),
                      sh=(-0.003, -0.014), hi=(0.002, 0.005), sat=(1.02, 1.06, 1.04), contrast=1.06, pivot=0.52,
                      black=0.0),
    # flat grey light: less contrast and chroma, lifted blacks, a cold grey cast
    "nublado": dict(slope=(0.97, 0.98, 1.0), offset=(0.008, 0.01, 0.017), power=(1.03, 1.03, 1.01),
                    sh=(-0.002, -0.012), hi=(-0.001, -0.006), sat=(0.72, 0.74, 0.8), contrast=0.93, pivot=0.55,
                    black=0.018),
    # white-out: strong desaturation, blue-cyan cast, very lifted blacks, low contrast
    "ventisca": dict(slope=(0.95, 0.98, 1.02), offset=(0.022, 0.03, 0.045), power=(1.0, 1.0, 0.98),
                     sh=(-0.006, -0.02), hi=(-0.004, -0.01), sat=(0.5, 0.55, 0.62), contrast=0.84, pivot=0.58,
                     black=0.05),
    # golden hour / dusk: orange highlights, violet-blue shadows, a little more chroma
    "atardecer": dict(slope=(1.05, 0.99, 0.93), offset=(0.0, 0.0, 0.012), power=(1.0, 1.0, 1.0),
                      sh=(0.012, -0.03), hi=(0.012, 0.034), sat=(1.08, 1.12, 1.15), contrast=1.05, pivot=0.5,
                      black=0.0),
    # moonlit snow: blue, desaturated mids; warm lights (fire, lantern, windows) keep their chroma
    "noche": dict(slope=(0.93, 0.96, 1.03), offset=(0.0, 0.004, 0.014), power=(1.02, 1.02, 1.0),
                  sh=(-0.004, -0.03), hi=(0.012, 0.03), sat=(0.74, 0.84, 1.3), contrast=1.18, pivot=0.36,
                  black=0.006),
    # city night: sodium orange highlights over teal-grey streets, harder contrast
    "noche_ciudad": dict(slope=(1.0, 0.97, 0.95), offset=(0.0, 0.005, 0.008), power=(1.03, 1.02, 1.02),
                         sh=(-0.014, -0.012), hi=(0.02, 0.045), sat=(0.66, 0.72, 1.35), contrast=1.22, pivot=0.36,
                         black=0.008),
    # blackout: very cold and dark, crushed shadows; a candle or a fire still burns orange
    "apagon": dict(slope=(0.84, 0.88, 0.96), offset=(0.0, 0.002, 0.01), power=(1.08, 1.08, 1.04),
                   sh=(-0.004, -0.026), hi=(0.016, 0.038), sat=(0.5, 0.58, 1.4), contrast=1.3, pivot=0.36,
                   black=0.0),
    # by the fire: amber lift in shadows and mids, softer contrast
    "calor": dict(slope=(1.05, 1.0, 0.94), offset=(0.012, 0.006, 0.0), power=(1.0, 1.0, 1.02),
                  sh=(0.008, 0.022), hi=(0.006, 0.02), sat=(1.08, 1.1, 1.1), contrast=0.98, pivot=0.5, black=0.0),
}
# Not blended in game: the tests' reference (texel = its own input).
EXTRA = {"identity": None}


# ---------------------------------------------------------------- colour maths
def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0.0, None)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def linear_to_oklab(rgb):
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]])
    lms = rgb @ m1.T
    return np.cbrt(lms) @ m2.T


def oklab_to_linear(lab):
    m2i = np.array([[1.0, 0.3963377774, 0.2158037573],
                    [1.0, -0.1055613458, -0.0638541728],
                    [1.0, -0.0894841775, -1.2914855480]])
    m1i = np.array([[4.0767416621, -3.3077115913, 0.2309699292],
                    [-1.2684380046, 2.6097574011, -0.3413193965],
                    [-0.0041960863, -0.7034186147, 1.7076147010]])
    lms = (lab @ m2i.T) ** 3
    return lms @ m1i.T


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def grade(v, p):
    """v: (..., 3) display-sRGB inputs in [0, 1] -> graded display-sRGB in [0, 1]."""
    if p is None:
        return v.copy()
    slope = np.array(p["slope"])
    offset = np.array(p["offset"])
    power = np.array(p["power"])
    x = np.clip(v * slope + offset, 0.0, 1.0) ** power
    lab = linear_to_oklab(srgb_to_linear(x))
    L = lab[..., 0]
    ws = 1.0 - smoothstep(0.0, 0.6, L)
    wh = smoothstep(0.45, 1.0, L)
    lab[..., 1] += ws * p["sh"][0] + wh * p["hi"][0]
    lab[..., 2] += ws * p["sh"][1] + wh * p["hi"][1]
    s_sh, s_mid, s_hi = p["sat"]
    band_lo = smoothstep(0.15, 0.5, L)
    band_hi = smoothstep(0.55, 0.9, L)
    sat = s_sh + (s_mid - s_sh) * band_lo + (s_hi - s_mid) * band_hi
    lab[..., 1] *= sat
    lab[..., 2] *= sat
    piv = p["pivot"]
    # contrast as a soft S around the pivot (keeps 0 and 1 fixed)
    c = p["contrast"]
    Lc = np.clip(L, 0.0, 1.0)
    lo = piv * np.power(np.clip(Lc / piv, 0.0, 1.0), c)
    hi = 1.0 - (1.0 - piv) * np.power(np.clip((1.0 - Lc) / (1.0 - piv), 0.0, 1.0), c)
    Ls = np.where(Lc < piv, lo, hi)
    Ls = p["black"] + Ls * (1.0 - p["black"])
    lab[..., 0] = Ls
    out = linear_to_srgb(oklab_to_linear(lab))
    return np.clip(out, 0.0, 1.0)


def lut_cube(p):
    """(z=b, y=g, x=r, 3) float cube of the graded display colours."""
    i = np.arange(N) / (N - 1.0)
    b, g, r = np.meshgrid(i, i, i, indexing="ij")
    v = np.stack([r, g, b], axis=-1)
    return grade(v, p)


def cube_to_strip(cube):
    """(32, 32, 32, 3) -> (32, 1024, 4) uint8 strip, alpha = ALPHA."""
    q = np.clip(np.round(cube * 255.0), 0, 255).astype(np.uint8)
    strip = np.zeros((N, N * N, 4), dtype=np.uint8)
    for z in range(N):
        strip[:, z * N:(z + 1) * N, :3] = q[z]
    strip[..., 3] = ALPHA
    return strip


def png_bytes(strip):
    import io
    buf = io.BytesIO()
    Image.fromarray(strip, "RGBA").save(buf, format="PNG", optimize=False, compress_level=9)
    return buf.getvalue()


IMPORT = """[remap]

importer="image"
type="Image"

[deps]

source_file="res://assets/luts/{name}.png"

[params]

"""


def build():
    files = {}
    meta = {"_doc": "G2b 3D LUTs (tools/make_luts.py): 32^3 strips 1024x32, slice z = blue, x = red, y = green, "
                    "texel = graded display colour of the input (i/31); alpha 128 = the CPU blend's half alpha "
                    "(scripts/world/atmosphere/lut_grade.gd). Order = LutGrade.NAMES.",
            "size": N, "alpha": ALPHA, "luts": {}}
    for name, p in list(LUTS.items()) + list(EXTRA.items()):
        data = png_bytes(cube_to_strip(lut_cube(p)))
        files[name + ".png"] = data
        meta["luts"][name] = {"params": p, "sha256": hashlib.sha256(data).hexdigest()}
    files["luts.json"] = (json.dumps(meta, indent=1, sort_keys=True) + "\n").encode()
    return files


def sample(cube, img):
    """Trilinear lookup like Godot's tonemapper (texture coordinate = colour, texel i at (i + 0.5) / 32)."""
    x = np.clip(img * N - 0.5, 0.0, N - 1.0)
    i0 = np.floor(x).astype(int)
    i1 = np.minimum(i0 + 1, N - 1)
    f = x - i0
    r0, g0, b0 = i0[..., 0], i0[..., 1], i0[..., 2]
    r1, g1, b1 = i1[..., 0], i1[..., 1], i1[..., 2]
    fr, fg, fb = f[..., 0:1], f[..., 1:2], f[..., 2:3]

    def c(b, g, r):
        return cube[b, g, r]
    c00 = c(b0, g0, r0) * (1 - fr) + c(b0, g0, r1) * fr
    c01 = c(b0, g1, r0) * (1 - fr) + c(b0, g1, r1) * fr
    c10 = c(b1, g0, r0) * (1 - fr) + c(b1, g0, r1) * fr
    c11 = c(b1, g1, r0) * (1 - fr) + c(b1, g1, r1) * fr
    c0 = c00 * (1 - fg) + c01 * fg
    c1 = c10 * (1 - fg) + c11 * fg
    return c0 * (1 - fb) + c1 * fb


def preview(src, dst):
    from PIL import ImageDraw
    im = Image.open(src).convert("RGB")
    im.thumbnail((480, 270))
    a = np.asarray(im).astype(np.float64) / 255.0
    names = list(LUTS.keys())
    cols = 3
    rows = (len(names) + 1 + cols - 1) // cols
    W, H = im.width, im.height
    sheet = Image.new("RGB", (cols * W, rows * (H + 16)), (18, 18, 18))
    d = ImageDraw.Draw(sheet)
    cells = [("sin LUT", a)]
    for n in names:
        q = np.clip(np.round(lut_cube(LUTS[n]) * 255.0), 0, 255) / 255.0
        cells.append((n, sample(q, a)))
    for k, (label, arr) in enumerate(cells):
        x = (k % cols) * W
        y = (k // cols) * (H + 16)
        sheet.paste(Image.fromarray(np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)), (x, y + 16))
        d.text((x + 4, y + 2), label, fill=(235, 235, 235))
    sheet.save(dst, quality=88)
    print("wrote", dst)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="compare with the files on disk, write nothing")
    ap.add_argument("--preview", nargs=2, metavar=("IN", "OUT"), help="apply every LUT to an image")
    a = ap.parse_args(argv)
    if a.preview:
        preview(*a.preview)
        return 0
    files = build()
    if a.check:
        # pixels, not bytes: zlib / numpy builds may encode or round differently; ±1 / 255 per channel is the same LUT
        import io
        bad = []
        for f, data in files.items():
            path = OUT / f
            if not path.exists():
                bad.append(f)
            elif f.endswith(".png"):
                want = np.asarray(Image.open(io.BytesIO(data)).convert("RGBA")).astype(int)
                have = np.asarray(Image.open(path).convert("RGBA")).astype(int)
                if want.shape != have.shape or np.abs(want - have).max() > 1:
                    bad.append(f)
            elif json.loads(path.read_text())["luts"].keys() != json.loads(data)["luts"].keys():
                bad.append(f)
        print("make_luts --check: %d files, %s" % (len(files), "OK" if not bad else "DIFFER: %s" % bad))
        return 1 if bad else 0
    OUT.mkdir(parents=True, exist_ok=True)
    for f, data in files.items():
        (OUT / f).write_bytes(data)
        if f.endswith(".png"):
            imp = OUT / (f + ".import")
            if not imp.exists():
                imp.write_text(IMPORT.format(name=f[:-4]))
    print("wrote %d files to %s" % (len(files), OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
