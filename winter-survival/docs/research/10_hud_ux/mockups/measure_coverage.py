#!/usr/bin/env python3
"""Mide cuánta pantalla ocupa el HUD en cada maqueta (v1 y v2) y escribe coverage.json + máscaras.

Entrada: mockups/cov/<nombre>.png, la capa de HUD sola con alfa (render.cjs --measure: sin mundo, sin efectos de
pantalla completa — viñetas de frío/daño, niebla —, sin velos de degradado ≤ 45 % y sin anotaciones).

Dos cifras por maqueta, sobre 1920×1080 = 2 073 600 px:
  · tinta  = píxeles con opacidad del HUD ≥ 10 %.
  · caja   = área de la unión de las cajas envolventes de cada elemento. Para agrupar las letras de una línea (y las
             líneas de un mismo bloque) en un elemento, la máscara de tinta se cierra con un núcleo de 15×15 px antes
             de buscar componentes conexas. Es la cifra conservadora que se usa como «cobertura» en el documento.
Requisitos: numpy + opencv (venv de documentación). Uso: python3 measure_coverage.py
Las capas en bruto (cov/<nombre>.png, ~0,5 MB cada una en v1) no se guardan en el repo: se regeneran con --measure;
solo se conservan las máscaras (cov/<nombre>_mask.png) que usa v2_comparativa.html.
"""
import json
import os
import numpy as np
import cv2

HERE = os.path.dirname(os.path.abspath(__file__))
COV = os.path.join(HERE, "cov")


def measure(path):
    img = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    a = img[:, :, 3].astype(np.float32) / 255.0
    ink = (a >= 0.10).astype(np.uint8)
    closed = cv2.morphologyEx(ink, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
    n, _, stats, _ = cv2.connectedComponentsWithStats(closed, connectivity=8)
    boxes = np.zeros_like(ink)
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if area < 12:          # motas sueltas (antialias)
            continue
        boxes[y:y + h, x:x + w] = 1
    total = ink.size
    # miniatura para la comparativa: cajas en gris, tinta en blanco, sobre fondo oscuro
    thumb = np.full((1080, 1920, 3), (26, 18, 12), np.uint8)
    thumb[boxes > 0] = (92, 78, 64)
    thumb[ink > 0] = (250, 246, 240)
    thumb = cv2.resize(thumb, (480, 270), interpolation=cv2.INTER_AREA)
    return {"ink_pct": round(100.0 * ink.sum() / total, 2), "box_pct": round(100.0 * boxes.sum() / total, 2)}, thumb


def main():
    out = {}
    for f in sorted(os.listdir(COV)):
        if not f.endswith(".png") or f.endswith("_mask.png"):
            continue
        name = f[:-4]
        res, thumb = measure(os.path.join(COV, f))
        cv2.imwrite(os.path.join(COV, name + "_mask.png"), thumb)
        out[name] = res
        print(f"{name:28s} tinta {res['ink_pct']:6.2f} %   caja {res['box_pct']:6.2f} %")
    with open(os.path.join(HERE, "coverage.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
