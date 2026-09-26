#!/usr/bin/env python3
"""Genera map_albarran.svg: mapa de papel 6x6 km (propuesta) con niebla de guerra, para la maqueta f_mapa_diario.html.

Coordenadas en metros de mapa (0..6000, norte arriba). El mundo actual de 3x3 km (PoiRegistry) queda con el
claro del cazador en (2600, 3500); Albarrán (ciudad nueva) al noreste y el río Albar helado cruzando de oeste a este.
Solo documentación: la geografía de la ciudad es ilustrativa. Uso: python3 gen_map.py  (escribe junto al script)
"""
import math
import os
import random

VB = (1300, 850, 4040, 3000)          # ventana visible (x, y, w, h)
K = VB[2] / 1200.0                    # metros por píxel de pantalla (el mapa se muestra a 1200 px de ancho)
C = (2600, 3500)                      # claro del cazador
HALO = f'paint-order="stroke" stroke="#E9E1CD" stroke-width="{3.0 * 1200 / 1200 * (4040 / 1200) * 1.6:.0f}" stroke-linejoin="round"'
rnd = random.Random(7)


def px(v):
    return v * K


def poly(points, close=True):
    d = "M" + " L".join(f"{x:.0f} {y:.0f}" for x, y in points)
    return d + (" Z" if close else "")


def smooth(points):
    """Catmull-Rom → Bézier para ríos y carreteras."""
    d = f"M{points[0][0]:.0f} {points[0][1]:.0f}"
    for i in range(len(points) - 1):
        p0 = points[i - 1] if i > 0 else points[i]
        p1, p2 = points[i], points[i + 1]
        p3 = points[i + 2] if i + 2 < len(points) else p2
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f" C{c1[0]:.0f} {c1[1]:.0f} {c2[0]:.0f} {c2[1]:.0f} {p2[0]:.0f} {p2[1]:.0f}"
    return d


def wobble_ring(cx, cy, r, amp, seed, n=48):
    rr = random.Random(seed)
    ph = [rr.uniform(0, 6.28) for _ in range(3)]
    pts = []
    for i in range(n):
        a = i / n * math.tau
        k = 1 + amp * (0.5 * math.sin(3 * a + ph[0]) + 0.3 * math.sin(5 * a + ph[1]) + 0.2 * math.sin(7 * a + ph[2]))
        pts.append((cx + r * k * math.cos(a), cy + r * 0.85 * k * math.sin(a)))
    return poly(pts)


def text(x, y, s, size_px, fill="#3B3428", weight=600, family="Barlow Condensed", spacing=0.08, anchor="middle",
         style="", extra=""):
    return (f'<text x="{x:.0f}" y="{y:.0f}" font-family="{family}" font-weight="{weight}" font-size="{px(size_px):.0f}" '
            f'fill="{fill}" text-anchor="{anchor}" letter-spacing="{px(size_px) * spacing:.0f}" {style} {extra}>{s}</text>')


# ---------------------------------------------------------------- geografía
RIVER = [(1250, 1450), (1800, 1640), (2400, 1950), (3000, 2075), (3260, 2095), (3700, 2060), (4200, 2010),
         (4700, 2090), (5200, 2350), (5450, 2560)]
LAKE = [((1820, 3840), 250), ((1940, 4000), 190), ((1690, 3960), 160)]
N140 = [(3240, 3800), (3240, 3000), (3240, 2300), (3262, 2095), (3350, 1900), (3620, 1580), (3920, 1360)]
A14 = [(1250, 1150), (2300, 1330), (3100, 1450), (3560, 1580), (4100, 1640), (4700, 1600), (5400, 1520)]
RAIL = [(1250, 1560), (2000, 1700), (2800, 1880), (3500, 1760), (3900, 1700), (4400, 1760)]
LOCAL = [
    [(1832, 2860), (2150, 2870), (2496, 2860)],                  # La Herrería → Valdenieve
    [(3056, 2860), (3240, 2860)],                                # Valdenieve → N-140
    [(2600, 3500), (2605, 3300), (2640, 3198)],                  # claro → Valdenieve
    [(2600, 3500), (2900, 3520), (3240, 3500)],                  # claro → N-140
    [(2216, 3628), (2472, 3628), (2600, 3500)],                  # claro → lago
    [(3240, 3244), (3624, 3244)],                                # granja alta
    [(2472, 2604), (2560, 2778)],                                # granja del molino
    [(1720, 3520), (2050, 3560), (2216, 3628)],                  # presa
    [(1832, 2732), (1600, 2500), (1480, 2200), (1500, 1800)],    # hacia el norte (pinos)
]
HILLS = [((1448, 3372), 360, 11), ((2050, 1250), 420, 5), ((4850, 3250), 480, 9), ((1600, 2400), 260, 3)]
FIELDS = [(2472, 2604, 220, 160, 12), (3624, 3244, 200, 180, -8), (2984, 3884, 220, 180, 20)]
VALDE = (2496, 2778, 560, 420)

# ---------------------------------------------------------------- niebla (zonas exploradas)
EXPLORED_DISCS = [(C, 520), ((2776, 2988), 420), ((1880, 2760), 300), ((2472, 2604), 200), ((3240, 2348), 280),
                  ((3262, 2095), 220), ((4380, 1260), 580), ((3700, 1560), 200), ((1760, 3500), 180)]
EXPLORED_PATHS = [
    ([C, (2640, 3198)], 200), ([(2496, 2860), (1880, 2800)], 170), ([(3240, 3600), (3240, 2300)], 190),
    ([(3262, 2095), (3350, 1900), (3620, 1580), (3920, 1360)], 170), ([C, (2216, 3628), (1760, 3520)], 160),
    ([(3240, 3244), (3624, 3244)], 150),
]


def explored_shapes(fill):
    out = [f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"/>' for (x, y), r in EXPLORED_DISCS]
    out += [f'<path d="{poly(p, False)}" fill="none" stroke="{fill}" stroke-width="{w * 2}" stroke-linecap="round" '
            f'stroke-linejoin="round"/>' for p, w in EXPLORED_PATHS]
    return "".join(out)


# ---------------------------------------------------------------- ciudad y pueblos
def city_blocks():
    out = []
    # Ensanche: manzanas achaflanadas regulares
    for gx in range(12):
        for gy in range(4):
            x, y = 3980 + gx * 92, 760 + gy * 92
            ch = 14
            out.append(f'<path d="{poly([(x + ch, y), (x + 70 - ch, y), (x + 70, y + ch), (x + 70, y + 70 - ch), (x + 70 - ch, y + 70), (x + ch, y + 70), (x, y + 70 - ch), (x, y + ch)])}" class="blk"/>')
    # Distrito financiero: manzanas grandes + torres
    for gx in range(5):
        for gy in range(4):
            x, y = 4150 + gx * 110, 1130 + gy * 100
            out.append(f'<rect x="{x}" y="{y}" width="92" height="82" class="blk"/>')
            for _ in range(rnd.randint(1, 3)):
                tx, ty = x + rnd.randint(6, 56), y + rnd.randint(6, 46)
                s = rnd.randint(18, 30)
                out.append(f'<rect x="{tx}" y="{ty}" width="{s}" height="{s}" class="tower"/>')
    # Casco viejo: polígonos irregulares
    for i in range(46):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0, 300)
        cx, cy = 3900 + r * math.cos(a), 1320 + r * 0.8 * math.sin(a)
        pts = [(cx + rnd.uniform(24, 48) * math.cos(t), cy + rnd.uniform(24, 48) * math.sin(t))
               for t in [k * math.tau / 5 + rnd.uniform(-.3, .3) for k in range(5)]]
        out.append(f'<path d="{poly(pts)}" class="blk"/>')
    # Polígono industrial
    for gx in range(4):
        for gy in range(3):
            x, y = 4760 + gx * 140, 1180 + gy * 140
            out.append(f'<rect x="{x}" y="{y}" width="{rnd.randint(90, 120)}" height="{rnd.randint(70, 110)}" class="blk ind"/>')
    # Ribera
    for gx in range(14):
        x = 3800 + gx * 70
        out.append(f'<rect x="{x}" y="{1880 + rnd.randint(-10, 10)}" width="52" height="40" class="blk"/>')
    return "".join(out)


def town(x0, y0, w, h, cell, seed):
    rr = random.Random(seed)
    out = []
    for gx in range(int(w // cell)):
        for gy in range(int(h // cell)):
            if rr.random() < 0.22:
                continue
            x = x0 + gx * cell + rr.uniform(-6, 6)
            y = y0 + gy * cell + rr.uniform(-6, 6)
            bw, bh = cell * rr.uniform(.45, .7), cell * rr.uniform(.4, .65)
            out.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{bw:.0f}" height="{bh:.0f}" class="blk" transform="rotate({rr.uniform(-6, 6):.1f} {x:.0f} {y:.0f})"/>')
    return "".join(out)


# ---------------------------------------------------------------- iconos de PDI (tinta)
def poi(kind, x, y, s=26):
    s = px(s)
    h = s / 2
    ink = "#3B3428"
    if kind == "hospital":
        return (f'<rect x="{x - h}" y="{y - h}" width="{s}" height="{s}" fill="#F4EEE0" stroke="{ink}" stroke-width="{px(1.6)}"/>'
                f'<path d="M{x - h * .6} {y} H{x + h * .6} M{x} {y - h * .6} V{y + h * .6}" stroke="#B0302A" stroke-width="{px(3)}"/>')
    if kind == "police":
        return f'<path d="M{x} {y - h} L{x + h} {y - h * .55} V{y + h * .1} Q{x + h} {y + h} {x} {y + h} Q{x - h} {y + h} {x - h} {y + h * .1} V{y - h * .55} Z" fill="#2E4A6B" stroke="{ink}" stroke-width="{px(1.2)}"/>'
    if kind == "fuel":
        return (f'<rect x="{x - h * .7}" y="{y - h}" width="{h * 1.1}" height="{s}" fill="{ink}"/>'
                f'<path d="M{x + h * .4} {y - h * .5} h{h * .4} v{h * 1.1}" fill="none" stroke="{ink}" stroke-width="{px(1.6)}"/>')
    if kind == "church":
        return f'<path d="M{x} {y - h} V{y + h} M{x - h * .6} {y - h * .35} H{x + h * .6}" stroke="{ink}" stroke-width="{px(2.4)}"/>'
    if kind == "dam":
        return f'<path d="M{x - h * 1.6} {y - h * .3} Q{x} {y + h * .6} {x + h * 1.6} {y - h * .3}" fill="none" stroke="{ink}" stroke-width="{px(4)}"/>'
    if kind == "tower":
        return (f'<path d="M{x} {y - h} L{x - h * .7} {y + h} M{x} {y - h} L{x + h * .7} {y + h} M{x - h * .45} {y + h * .3} H{x + h * .45}" stroke="{ink}" stroke-width="{px(1.8)}" fill="none"/>'
                f'<circle cx="{x}" cy="{y - h}" r="{px(2.6)}" fill="{ink}"/>')
    if kind == "checkpoint":
        return f'<rect x="{x - h * 1.3}" y="{y - h * .35}" width="{s * 1.3}" height="{h * .7}" fill="url(#stripes)" stroke="{ink}" stroke-width="{px(1.2)}"/>'
    if kind == "sky":
        return f'<rect x="{x - h * .45}" y="{y - h * 1.3}" width="{h * .9}" height="{s * 1.3}" fill="{ink}"/><path d="M{x} {y - h * 1.3} v{-h * .6}" stroke="{ink}" stroke-width="{px(1.5)}"/>'
    return ""


# ---------------------------------------------------------------- marcadores
def diamond(x, y, color, n=None, hollow=False, size=15):
    s = px(size)
    d = f"M{x} {y - s} L{x + s} {y} L{x} {y + s} L{x - s} {y} Z"
    out = f'<path d="{d}" fill="{"#F4EEE0" if hollow else color}" stroke="{"#2A2117" if not hollow else color}" stroke-width="{px(2.2 if hollow else 1.6)}"/>'
    if n:
        out += text(x, y + px(5.5), n, 15, "#2A2117", 700, "Barlow", 0)
    return out


def label_box(x, y, s, color="#2A2117", size=16, bg="#F4EEE0"):
    w = px(size) * 0.52 * len(s) + px(14)
    return (f'<rect x="{x - w / 2:.0f}" y="{y - px(size) * .95:.0f}" width="{w:.0f}" height="{px(size) * 1.35:.0f}" fill="{bg}" opacity=".9"/>'
            + text(x, y, s, size, color, 600, "Barlow", 0))


def build():
    o = []
    x0, y0, w, h = VB
    o.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0} {y0} {w} {h}" width="1200" height="891" preserveAspectRatio="xMidYMid slice">')
    o.append(f"""<defs>
  <filter id="paper" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.012" numOctaves="4" seed="3"/>
    <feColorMatrix values="0 0 0 0 0.45  0 0 0 0 0.38  0 0 0 0 0.26  0 0 0 0.22 0"/></filter>
  <filter id="fiber" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.35" numOctaves="2" seed="8"/>
    <feColorMatrix values="0 0 0 0 0.3  0 0 0 0 0.25  0 0 0 0 0.18  0 0 0 0.10 0"/></filter>
  <filter id="rough" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.006" numOctaves="3" seed="12" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="{px(38):.0f}" xChannelSelector="R" yChannelSelector="G"/><feGaussianBlur stdDeviation="{px(1.2):.1f}"/></filter>
  <filter id="soot" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.006" numOctaves="3" seed="12" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="{px(38):.0f}" xChannelSelector="R" yChannelSelector="G" result="d"/>
    <feMorphology in="d" operator="dilate" radius="{px(5):.0f}"/><feGaussianBlur stdDeviation="{px(7):.0f}"/></filter>
  <filter id="pencil"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="1" seed="2" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="{px(1.4):.1f}"/></filter>
  <pattern id="trees" width="{px(26):.0f}" height="{px(24):.0f}" patternUnits="userSpaceOnUse">
    <circle cx="{px(6):.0f}" cy="{px(7):.0f}" r="{px(3.3):.0f}" fill="#6E7F5E" opacity=".55"/><circle cx="{px(19):.0f}" cy="{px(18):.0f}" r="{px(2.8):.0f}" fill="#6E7F5E" opacity=".45"/>
    <circle cx="{px(18):.0f}" cy="{px(5):.0f}" r="{px(1.8):.0f}" fill="#6E7F5E" opacity=".35"/></pattern>
  <pattern id="ice" width="{px(8):.0f}" height="{px(8):.0f}" patternUnits="userSpaceOnUse" patternTransform="rotate(35)">
    <rect width="{px(8):.0f}" height="{px(8):.0f}" fill="#C9DCE6"/><line x1="0" y1="0" x2="0" y2="{px(8):.0f}" stroke="#A9C3D2" stroke-width="{px(1.2):.1f}"/></pattern>
  <pattern id="field" width="{px(7):.0f}" height="{px(7):.0f}" patternUnits="userSpaceOnUse" patternTransform="rotate(12)">
    <rect width="{px(7):.0f}" height="{px(7):.0f}" fill="#E3D9BF"/><line x1="0" y1="0" x2="{px(7):.0f}" y2="0" stroke="#C9BC98" stroke-width="{px(1.2):.1f}"/></pattern>
  <pattern id="stripes" width="{px(8):.0f}" height="{px(8):.0f}" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
    <rect width="{px(4):.0f}" height="{px(8):.0f}" fill="#B0302A"/><rect x="{px(4):.0f}" width="{px(4):.0f}" height="{px(8):.0f}" fill="#F4EEE0"/></pattern>
  <pattern id="dark" width="{px(9):.0f}" height="{px(9):.0f}" patternUnits="userSpaceOnUse" patternTransform="rotate(-40)">
    <line x1="0" y1="0" x2="0" y2="{px(9):.0f}" stroke="#1D2433" stroke-width="{px(2.2):.1f}" opacity=".55"/></pattern>
  <pattern id="storm" width="{px(12):.0f}" height="{px(12):.0f}" patternUnits="userSpaceOnUse" patternTransform="rotate(28)">
    <line x1="0" y1="0" x2="0" y2="{px(12):.0f}" stroke="#4E7FA6" stroke-width="{px(1.6):.1f}" opacity=".7"/></pattern>
  <mask id="explored" maskUnits="userSpaceOnUse" x="{x0}" y="{y0}" width="{w}" height="{h}">
    <rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="black"/><g filter="url(#rough)">{explored_shapes("white")}</g></mask>
  <style>
    .blk {{ fill: #CFC5AE; stroke: #8C8270; stroke-width: {px(0.9):.1f}; }}
    .blk.ind {{ fill: #C7BFAE; }}
    .tower {{ fill: #6F6556; }}
    .road {{ fill: none; stroke-linecap: round; stroke-linejoin: round; }}
  </style>
</defs>""")
    # papel
    o.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="#E9E1CD"/>')
    o.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" filter="url(#paper)"/>')
    o.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" filter="url(#fiber)"/>')
    # cuadrícula 1 km
    for gx in range(2000, 5400, 1000):
        o.append(f'<line x1="{gx}" y1="{y0}" x2="{gx}" y2="{y0 + h}" stroke="#8C7F66" stroke-width="{px(.8):.1f}" opacity=".45"/>')
    for gy in range(1000, 3700, 1000):
        o.append(f'<line x1="{x0}" y1="{gy}" x2="{x0 + w}" y2="{gy}" stroke="#8C7F66" stroke-width="{px(.8):.1f}" opacity=".45"/>')

    # ---- capa impresa (mapa de carreteras encontrado): tenue, visible también bajo la niebla
    printed = []
    printed.append(f'<path d="{smooth(RIVER)}" class="road" stroke="#9FBCCC" stroke-width="{px(9):.0f}" opacity=".7"/>')
    for (cx, cy), r in LAKE:
        printed.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#B9CFDA" opacity=".6"/>')
    printed.append(f'<path d="{smooth(A14)}" class="road" stroke="#7A6F5E" stroke-width="{px(4.5):.0f}"/>')
    printed.append(f'<path d="{smooth(N140)}" class="road" stroke="#7A6F5E" stroke-width="{px(3.5):.0f}"/>')
    printed.append(text(4460, 1070, "ALBARRÁN", 30, "#6B604E", 700, spacing=.4))
    printed.append(text(2776, 2745, "VALDENIEVE", 20, "#6B604E", 700, spacing=.3))
    printed.append(text(1860, 2660, "LA HERRERÍA", 16, "#6B604E", 700, spacing=.25))
    o.append(f'<g opacity=".42">{"".join(printed)}</g>')

    # ---- hollín del borde de la niebla (debajo de lo explorado)
    o.append(f'<g filter="url(#soot)" opacity=".42">{explored_shapes("#4A433A")}</g>')

    # ---- capa explorada
    e = []
    e.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="#E9E1CD"/>')
    e.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" filter="url(#paper)"/>')
    e.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="url(#trees)"/>')
    for (cx, cy), r, sd in HILLS:
        for k in range(5):
            e.append(f'<path d="{wobble_ring(cx, cy, r * (1 - k * .18), .12, sd + k)}" fill="none" stroke="#A08E6C" stroke-width="{px(1.1):.1f}" opacity=".55"/>')
    for fx, fy, fw, fh, rot in FIELDS:
        e.append(f'<rect x="{fx - fw / 2}" y="{fy - fh / 2}" width="{fw}" height="{fh}" fill="url(#field)" stroke="#A59772" stroke-width="{px(.8):.1f}" transform="rotate({rot} {fx} {fy})"/>')
    # claros de asentamientos (papel liso bajo manzanas)
    e.append(f'<rect x="{VALDE[0] - 40}" y="{VALDE[1] - 40}" width="{VALDE[2] + 80}" height="{VALDE[3] + 80}" rx="60" fill="#E9E1CD"/>')
    e.append('<ellipse cx="4420" cy="1330" rx="880" ry="680" fill="#E9E1CD"/>')
    e.append('<ellipse cx="1860" cy="2740" rx="190" ry="150" fill="#E9E1CD"/>')
    e.append(f'<circle cx="{C[0]}" cy="{C[1]}" r="110" fill="#E9E1CD"/>')
    # agua helada
    e.append(f'<path d="{smooth(RIVER)}" class="road" stroke="#8FAEBF" stroke-width="{px(13):.0f}"/>')
    e.append(f'<path d="{smooth(RIVER)}" class="road" stroke="url(#ice)" stroke-width="{px(10):.0f}"/>')
    for (cx, cy), r in LAKE:
        e.append(f'<circle cx="{cx}" cy="{cy}" r="{r + 10}" fill="#8FAEBF"/>')
    for (cx, cy), r in LAKE:
        e.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#ice)"/>')
    # carreteras
    for road in LOCAL:
        e.append(f'<path d="{smooth(road)}" class="road" stroke="#5E5446" stroke-width="{px(2):.1f}"/>')
    e.append(f'<path d="{smooth(RAIL)}" class="road" stroke="#3B3428" stroke-width="{px(3):.1f}"/>')
    e.append(f'<path d="{smooth(RAIL)}" class="road" stroke="#E9E1CD" stroke-width="{px(1.6):.1f}" stroke-dasharray="{px(8):.0f} {px(8):.0f}"/>')
    e.append(f'<path d="{smooth(N140)}" class="road" stroke="#3B3428" stroke-width="{px(6):.0f}"/>')
    e.append(f'<path d="{smooth(N140)}" class="road" stroke="#E6A24C" stroke-width="{px(3.6):.0f}"/>')
    e.append(f'<path d="{smooth(A14)}" class="road" stroke="#2A2117" stroke-width="{px(8):.0f}"/>')
    e.append(f'<path d="{smooth(A14)}" class="road" stroke="#D6603C" stroke-width="{px(5.4):.0f}"/>')
    e.append(f'<path d="{smooth(A14)}" class="road" stroke="#2A2117" stroke-width="{px(.8):.1f}"/>')
    # asentamientos
    e.append(city_blocks())
    e.append(town(VALDE[0], VALDE[1], VALDE[2], VALDE[3], 70, 4))
    e.append(town(1760, 2650, 190, 170, 46, 5))
    e.append(town(C[0] - 40, C[1] - 30, 90, 60, 45, 6))
    # PDI
    e.append(poi("hospital", 2730, 2980) + poi("police", 2984, 2988) + poi("church", 2860, 3100))
    e.append(poi("fuel", 3200, 3116) + poi("fuel", 3200, 3628) + poi("checkpoint", 3240, 2348, 30))
    e.append(poi("dam", 1720, 3470, 30) + poi("tower", 1448, 3372, 30) + poi("hospital", 4060, 1180, 24) + poi("sky", 4390, 1250, 26))
    # puente norte
    e.append(f'<path d="M3225 2060 L3300 2060 M3225 2130 L3300 2130" stroke="#2A2117" stroke-width="{px(2):.1f}"/>')
    # rótulos
    e.append(text(4460, 1070, "ALBARRÁN", 30, "#2A2117", 700, spacing=.42))
    for s, x, y, sz in [("ENSANCHE", 4540, 1010, 13), ("DISTRITO FINANCIERO", 4380, 1560, 14), ("CASCO VIEJO", 3880, 1500, 13),
                        ("POLÍGONO", 5000, 1640, 13), ("RIBERA", 4250, 1975, 12), ("ESTACIÓN", 3930, 1760, 12)]:
        e.append(text(x, y, s, sz, "#4A3F31", 600, spacing=.2))
    e.append(text(2776, 2745, "VALDENIEVE", 20, "#2A2117", 700, spacing=.32))
    e.append(text(1860, 2660, "LA HERRERÍA", 16, "#2A2117", 700, spacing=.26))
    e.append(text(1820, 3780, "Lago de las Ánimas", 17, "#3E6178", 500, "Barlow", 0.02, style='font-style="italic"'))
    e.append(f'<path id="rv" d="{smooth(RIVER[1:6])}" fill="none"/>')
    e.append(f'<text font-family="Barlow" font-style="italic" font-weight="500" font-size="{px(16):.0f}" fill="#3E6178" dy="{-px(9):.0f}"><textPath href="#rv" startOffset="18%">Río Albar · helado</textPath></text>')
    # escudos de carretera
    e.append(f'<rect x="3270" y="2700" width="{px(52):.0f}" height="{px(20):.0f}" rx="{px(3):.0f}" fill="#C0392B"/>' + text(3270 + px(26), 2700 + px(15), "N‑140", 13, "#FFFFFF", 700, "Barlow", 0))
    e.append(f'<rect x="2500" y="1180" width="{px(44):.0f}" height="{px(20):.0f}" rx="{px(3):.0f}" fill="#1F5FA8"/>' + text(2500 + px(22), 1180 + px(15), "A‑14", 13, "#FFFFFF", 700, "Barlow", 0))
    o.append(f'<g mask="url(#explored)">{"".join(e)}</g>')

    for s, x, y in [("Presa", 1720, 3420), ("Control militar km 12", 3400, 2320),
                    ("Puente norte", 3380, 2150), ("Gasolinera norte", 3380, 3125), ("Área de descanso", 3380, 3636),
                    ("Granja del Molino", 2472, 2480), ("Granja Alta", 3624, 3130), ("Torre Albar", 4470, 1120)]:
        o.append(text(x, y, s, 14, "#3B3428", 500, "Barlow", 0, anchor="start" if x > 3200 and "Torre" not in s else "middle", extra=HALO))
    # ---- superposiciones (capas conmutables)
    # apagón: distrito financiero + ensanche
    o.append(f'<path d="{poly([(3990, 740), (5100, 740), (5100, 1100), (4700, 1100), (4700, 1560), (4130, 1560), (4130, 1100), (3990, 1100)])}" fill="url(#dark)" stroke="#1D2433" stroke-width="{px(1.5):.1f}" stroke-dasharray="{px(6):.0f} {px(4):.0f}" opacity=".9"/>')
    o.append(f'<circle cx="4060" cy="1180" r="{px(22):.0f}" fill="#FFD479" opacity=".45"/>' + poi("hospital", 4060, 1180, 24))
    o.append(label_box(5020, 1210, "Sin electricidad", "#1D2433", 14, "#E9E1CD"))
    # frente de ventisca (pronóstico)
    front = [(1300, 700), (2900, 700), (2600, 1150), (2200, 1500), (1700, 1900), (1300, 2150)]
    o.append(f'<path d="{poly(front)}" fill="url(#storm)" opacity=".75"/>')
    o.append(f'<path d="{smooth([(2900, 700), (2600, 1150), (2200, 1500), (1700, 1900), (1300, 2150)])}" fill="none" stroke="#2F6A96" stroke-width="{px(2.2):.1f}" stroke-dasharray="{px(10):.0f} {px(6):.0f}"/>')
    o.append(f'<path d="M2050 1350 L2330 1560" stroke="#2F6A96" stroke-width="{px(3):.0f}"/>')
    o.append(f'<path d="M2330 1560 l{-px(14):.0f} {-px(2):.0f} l{px(6):.0f} {-px(12):.0f} z" fill="#2F6A96"/>')
    o.append(label_box(1840, 1180, "Ventisca · llega en ~40 min", "#1F4E73", 15, "#E9E1CD"))

    # ---- anotaciones a lápiz (Caveat)
    def note(x, y, s, color="#5A4E3E", size=22, rot=-4):
        return (f'<text x="{x}" y="{y}" font-family="Caveat" font-weight="600" font-size="{px(size):.0f}" fill="{color}" '
                f'transform="rotate({rot} {x} {y})" filter="url(#pencil)">{s}</text>')
    o.append(note(3420, 2430, "¡mucho zombi!", "#A2302A", 23, -5))
    o.append(f'<ellipse cx="3240" cy="2348" rx="{px(34):.0f}" ry="{px(24):.0f}" fill="none" stroke="#A2302A" stroke-width="{px(1.8):.1f}" filter="url(#pencil)" transform="rotate(-8 3240 2348)"/>')
    o.append(note(3390, 3700, "2 coches con gasolina", "#5A4E3E", 20, -3))
    o.append(note(1480, 3620, "perros salvajes", "#A2302A", 20, 4))
    o.append(note(4620, 1330, "desde arriba se ve todo", "#5A4E3E", 20, -6))
    o.append(note(1560, 2980, "aserradero: plano de cadenas", "#5A4E3E", 19, -2))
    o.append(note(2690, 3690, "casa", "#5A4E3E", 22, 0))

    # ---- marcadores de juego
    # ruta a lápiz hacia el objetivo seguido
    o.append(f'<path d="{poly([(3240, 2600), (3240, 2860), (3056, 2860), (2760, 2980)], False)}" fill="none" stroke="#E08A1E" stroke-width="{px(3):.1f}" stroke-dasharray="{px(2):.1f} {px(7):.0f}" stroke-linecap="round"/>')
    # base
    bx, by = C
    o.append(f'<circle cx="{bx}" cy="{by}" r="{px(17):.0f}" fill="#2A2117"/><path d="M{bx - px(9)} {by + px(1)} L{bx} {by - px(8)} L{bx + px(9)} {by + px(1)} V{by + px(9)} H{bx - px(9)} Z" fill="#FFB454"/>')
    # misión principal: 3 componentes
    o.append(diamond(1720, 3520, "#FFB454", "1") + diamond(2730, 2930, "#FFB454", "2") + diamond(2984, 2935, "#FFB454", "3"))
    # secundarias
    o.append(diamond(3200, 3070, "#2A2117", hollow=True) + diamond(2472, 2604, "#2A2117", hollow=True))
    # dinámicas
    o.append(f'<circle cx="4700" cy="3000" r="260" fill="#5FE3C0" fill-opacity=".12" stroke="#1E9C80" stroke-width="{px(2.2):.1f}" stroke-dasharray="{px(8):.0f} {px(5):.0f}"/>')
    o.append(text(4700, 3010, "?", 34, "#1E9C80", 700, "Barlow", 0))
    o.append(label_box(4700, 2700, "Llamada de socorro · zona aprox.", "#146E5A", 14, "#E9E1CD"))
    hx, hy, hr = 3330, 2215, px(16)
    o.append(f'<path d="' + poly([(hx + hr * math.cos(a), hy + hr * math.sin(a)) for a in [math.pi / 6 + k * math.pi / 3 for k in range(6)]]) + f'" fill="#1E9C80" stroke="#0B3F33" stroke-width="{px(1.4):.1f}"/>')
    o.append(label_box(3530, 2222, "Convoy · 6:40", "#146E5A", 14, "#E9E1CD"))
    # ping de Ana
    o.append(f'<path d="M3180 2330 v{-px(34):.0f} h{px(20):.0f} l{-px(5):.0f} {px(6):.0f} l{px(5):.0f} {px(6):.0f} h{-px(20):.0f}" fill="#7CC8FF" stroke="#1D3E57" stroke-width="{px(1.4):.1f}"/>')
    # compañeros
    for (x, y, col, ini) in [(3290, 2650, "#7CC8FF", "A"), (2640, 3450, "#C9A6FF", "L"), (2520, 1360, "#9DE07F", "I")]:
        o.append(f'<circle cx="{x}" cy="{y}" r="{px(12):.0f}" fill="{col}" stroke="#1B2533" stroke-width="{px(2):.1f}"/>' + text(x, y + px(5), ini, 14, "#0B111A", 700, "Barlow", 0))
    # jugador (flecha ámbar)
    x, y = 3240, 2600
    o.append(f'<circle cx="{x}" cy="{y}" r="{px(26):.0f}" fill="#FFB454" opacity=".22"/>')
    o.append(f'<path d="M{x} {y - px(18)} L{x + px(12)} {y + px(13)} L{x} {y + px(6)} L{x - px(12)} {y + px(13)} Z" fill="#FFB454" stroke="#2A2117" stroke-width="{px(2):.1f}"/>')
    # marco
    o.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="none" stroke="#6B604E" stroke-width="{px(3):.0f}"/>')
    for i, gx in enumerate(range(2000, 5400, 1000)):
        o.append(text(gx - 500, y0 + px(18), "BCDE"[i], 13, "#6B604E", 700, spacing=0))
    for i, gy in enumerate(range(1000, 3700, 1000)):
        o.append(text(x0 + px(12), gy + 500, "234"[i], 13, "#6B604E", 700, spacing=0))
    o.append("</svg>")
    return "\n".join(o)


if __name__ == "__main__":
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "map_albarran.svg")
    with open(path, "w", encoding="utf-8") as f:
        f.write(build())
    print(path, os.path.getsize(path))
