#!/usr/bin/env python3
"""Borra el HUD del slice de las capturas G1/M4 y las escala a 1920x1080 como fondo de las maquetas.

Relleno por reconstrucción selectiva en frecuencia (OpenCV xphoto FSR_BEST) de los rectángulos del HUD antiguo,
escalado Lanczos ×1.5 y un enfoque suave. Solo para esta documentación (no forma parte del juego).
Con --v2 escribe bg2/: igual, pero el bloque de arriba a la derecha (reloj y anillos, sobre pinos) se rellena por
«shift-map» (copia de parches: mantiene la textura de los árboles) y se funde con FSR; v1 sigue usando bg/.
Requisitos: numpy + opencv-contrib-python-headless.  ~6 min de CPU en total.
Uso: python3 prep_backgrounds.py <raíz_del_repo> [--v2] [--cache DIR]   (--cache reutiliza <nombre>_fsrbest.png / _shiftmap.png)
"""
import os
import sys
import numpy as np
import cv2

SRC = {
    "day": "docs/screenshots/g1/day.jpg",
    "night": "docs/screenshots/g1/night.jpg",
    "blizzard": "docs/screenshots/g1/blizzard.jpg",
    "zombies": "docs/screenshots/m4/zombies.jpg",
}
# rectángulos del HUD antiguo en coordenadas 1280x720 (x0, y0, x1, y1)
HUD = [
    (578, 12, 702, 84),      # banner de región + icono de montaña
    (1134, 0, 1212, 80),     # reloj de día
    (1072, 78, 1272, 142),   # tres anillos
    (1088, 138, 1252, 164),  # etiqueta VENTISCA / barra de aguante
    (1008, 234, 1270, 392),  # panel de misiones
    (10, 194, 74, 492),      # barra de categorías
    (346, 636, 934, 714),    # barra rápida
]


def clean(img):
    mask = np.full(img.shape[:2], 255, np.uint8)
    for (x0, y0, x1, y1) in HUD:
        cv2.rectangle(mask, (x0, y0), (x1, y1), 0, -1)
    out = np.zeros_like(img)
    cv2.xphoto.inpaint(img, mask, out, cv2.xphoto.INPAINT_FSR_BEST)
    return out


TOP_RIGHT = [(1134, 0, 1212, 80), (1072, 78, 1272, 142), (1088, 138, 1252, 164)]


def clean_shiftmap(img):
    mask = np.full(img.shape[:2], 255, np.uint8)
    for (x0, y0, x1, y1) in HUD:
        cv2.rectangle(mask, (x0, y0), (x1, y1), 0, -1)
    out = np.zeros_like(img)
    cv2.xphoto.inpaint(img, mask, out, cv2.xphoto.INPAINT_SHIFTMAP)
    return out


def blend_top_right(fsr, shift):
    a = np.zeros(fsr.shape[:2], np.float32)
    for (x0, y0, x1, y1) in TOP_RIGHT:
        a[y0:y1, x0:x1] = 1.0
    a = cv2.GaussianBlur(a, (0, 0), 3.0)[..., None]
    return (shift * a + fsr * (1 - a)).astype(np.uint8)


def upscale(img):
    big = cv2.resize(img, (1920, 1080), interpolation=cv2.INTER_LANCZOS4)
    blur = cv2.GaussianBlur(big, (0, 0), 1.2)
    return cv2.addWeighted(big, 1.35, blur, -0.35, 0)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    cache = sys.argv[sys.argv.index("--cache") + 1] if "--cache" in sys.argv else None
    v2 = "--v2" in sys.argv
    outdir = os.path.join(root, "docs/research/10_hud_ux/mockups/bg2" if v2 else "docs/research/10_hud_ux/mockups/bg")
    os.makedirs(outdir, exist_ok=True)
    for name, rel in SRC.items():
        cached = os.path.join(cache, f"{name}_fsrbest.png") if cache else None
        src = cv2.imread(os.path.join(root, rel))
        img = cv2.imread(cached) if cached and os.path.exists(cached) else clean(src)
        if v2:
            cs = os.path.join(cache, f"{name}_shiftmap.png") if cache else None
            shift = cv2.imread(cs) if cs and os.path.exists(cs) else clean_shiftmap(src)
            img = blend_top_right(img, shift)
        path = os.path.join(outdir, f"{name}.jpg")
        cv2.imwrite(path, upscale(img), [cv2.IMWRITE_JPEG_QUALITY, 88])
        print(name, os.path.getsize(path))


if __name__ == "__main__":
    main()
