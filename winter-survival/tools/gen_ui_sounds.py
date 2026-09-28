#!/usr/bin/env python3
"""Placeholder UI sounds of the HUD (H2), synthesised from scratch — no samples, no third-party material.

  ui_zone_discover.wav   zone discovered (docs/research/10_hud_ux.md appendix §5.6: «soplo de viento y campana de
                         cristal grave», 1.8 s): a breath of filtered noise under a low glass bell (A3 with inharmonic
                         partials and a slow shimmer), mono 16-bit 32 kHz, peak −3 dBFS.

Deterministic (fixed seed): running it again rewrites the same bytes. Standard library only.
Licence of the output: CC0 1.0 (own work of the project, see assets/audio/ui/LICENSE.txt).
Usage: python3 tools/gen_ui_sounds.py [out_dir]   (default assets/audio/ui)
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 32000


def zone_discover() -> list:
    n = int(RATE * 1.8)
    rng = random.Random(1337)
    out = [0.0] * n
    # 1. breath of wind: white noise through two one-pole low-passes (band ≈ 250–1 400 Hz), raised-cosine envelope
    a1 = 1.0 - math.exp(-2.0 * math.pi * 1400.0 / RATE)
    a2 = 1.0 - math.exp(-2.0 * math.pi * 250.0 / RATE)
    l1 = l2 = 0.0
    for i in range(n):
        t = i / RATE
        x = rng.uniform(-1.0, 1.0)
        l1 += (x - l1) * a1
        l2 += (l1 - l2) * a2
        band = l1 - l2
        if t < 0.45:
            env = 0.5 - 0.5 * math.cos(math.pi * t / 0.45)
        elif t < 1.7:
            env = 0.5 + 0.5 * math.cos(math.pi * (t - 0.45) / 1.25)
        else:
            env = 0.0
        # slow swell of the gust
        env *= 0.8 + 0.2 * math.sin(2.0 * math.pi * 1.3 * t)
        out[i] += band * env * 0.9
    # 2. low glass bell: A3 (220 Hz) with inharmonic partials and a detuned twin (beating shimmer)
    f0 = 220.0
    partials = [(1.0, 1.0, 1.3), (2.32, 0.42, 0.85), (4.25, 0.22, 0.55), (6.63, 0.11, 0.34), (9.38, 0.05, 0.22)]
    start = 0.10
    for i in range(int(start * RATE), n):
        t = i / RATE - start
        attack = min(t / 0.004, 1.0)
        s = 0.0
        for ratio, amp, tau in partials:
            f = f0 * ratio
            decay = math.exp(-t / tau)
            s += amp * decay * (math.sin(2.0 * math.pi * f * t) + 0.6 * math.sin(2.0 * math.pi * f * 1.0035 * t + 0.7))
        tail = 1.0 if t < 1.5 else max(0.0, 1.0 - (t - 1.5) / 0.2)
        out[i] += s * attack * tail * 0.32
    peak = max(abs(v) for v in out) or 1.0
    gain = 10 ** (-3.0 / 20.0) / peak
    return [v * gain for v in out]


def write(path: str, samples: list) -> None:
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in samples))


def main() -> None:
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "ui")
    os.makedirs(out_dir, exist_ok=True)
    p = os.path.join(out_dir, "ui_zone_discover.wav")
    write(p, zone_discover())
    print("wrote %s (%d bytes)" % (p, os.path.getsize(p)))


if __name__ == "__main__":
    main()
