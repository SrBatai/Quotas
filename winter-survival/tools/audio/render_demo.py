#!/usr/bin/env python3
"""Renders docs/audio/demo_mix.ogg (S1): a ~42 s listening demo mixed offline from the shipped assets with the same
rules the game uses (inverse-distance attenuation from the listener, a distance low-pass, equal-power panning by
screen position, the gunshot close / distant / tail layers, bed crossfades). Not used by the game.

  0–17 s   the valley at dusk: forest bed + wind layer, a campfire 3 m to the right, walking on fresh snow, crows,
           an owl; a zombie groans in the trees, notices you («te he visto»), shambles in; two pistol shots, a
           shotgun (+ pump), the zombie falls; the shotgun is reloaded shell by shell.
  17–42 s  crossfade to Altavega: the street bed (wind in the canyons), steps on packed snow, a far car alarm, dogs,
           a creaking sign, a flapping tarp, an unseen gunshot far off, a scream, glass.
Run: python3 tools/audio/render_demo.py  (after build_audio.py)
"""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import audiolib as A  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
AUD = os.path.join(ROOT, "assets", "audio")
OUT = os.path.join(ROOT, "docs", "audio", "demo_mix.ogg")
DUR = 42.0
rng = np.random.default_rng(7)
N = A.n_of(DUR)
mixbuf = np.zeros((N, 2))


def f(rel: str) -> np.ndarray:
    return A.load(os.path.join(AUD, rel), mono=False)


def place(rel: str, t: float, x: float = 0.0, z: float = -3.0, gain_db: float = 0.0, unit: float = 4.0,
          lpf_far: float = 4000.0, maxd: float = 120.0, pitch: float = 1.0) -> None:
    """A mono 3D one-shot at (x, z) m from the listener (x = screen right, -z = up the screen)."""
    s = A.load(os.path.join(AUD, rel))
    if abs(pitch - 1.0) > 1e-3:
        s = A.resample_ratio(s, pitch)
    d = max(np.hypot(x, z), 0.5)
    g = min(1.0, unit / d) * A.db(gain_db)
    if d > unit:
        s = A.lp(s, max(lpf_far, 20000.0 * (1 - min(d / maxd, 1.0)) ** 2 + lpf_far * min(d / maxd, 1.0)), 2)
    pan = np.clip(x / d, -1, 1)
    st = A.pan(s * g, pan)
    i = A.n_of(t)
    e = min(N, i + len(st))
    mixbuf[i:e] += st[: e - i]


def bed(rel: str, t0: float, t1: float, gain_db: float, fade: float = 3.0) -> None:
    s = f(rel)
    n = A.n_of(t1 - t0)
    reps = int(np.ceil(n / len(s))) + 1
    s = np.concatenate([s] * reps)[:n]
    env = np.ones(n)
    k = A.n_of(fade)
    env[:k] = np.linspace(0, 1, k) ** 1.5
    env[-k:] = np.linspace(1, 0, k) ** 1.5
    i = A.n_of(t0)
    mixbuf[i:i + n] += s * env[:, None] * A.db(gain_db)


def shot(kind: str, weight: str, env: str, t: float, x: float, z: float, idx: int, gain_db: float = 0.0) -> None:
    d = np.hypot(x, z)
    close_g = 1.0 - np.clip((d - 20) / 40, 0, 1)
    far_g = np.clip((d - 15) / 30, 0, 1)
    if close_g > 0.02:
        place(f"weapons/{kind}_close_{idx:02d}.ogg", t, x, z, gain_db + 20 * np.log10(close_g), unit=6.0, lpf_far=9000)
    if far_g > 0.02:
        place(f"weapons/{kind}_far_{(idx - 1) % 3 + 1:02d}.ogg", t, x, z, gain_db - 2 + 20 * np.log10(far_g), unit=22.0, lpf_far=2500)
    tail = A.load(os.path.join(AUD, f"weapons/tail_{env}_{weight}_{(idx - 1) % 3 + 1:02d}.ogg"))
    tg = min(1.0, 14.0 / max(d, 1.0)) * A.db(gain_db - 5 + 5 * np.clip((d - 5) / 55, 0, 1))
    st = A.pan(tail * tg, 0.4 * np.clip(x / max(d, 0.5), -1, 1))
    i = A.n_of(t + 0.012)
    e = min(N, i + len(st))
    mixbuf[i:e] += st[: e - i]


def main() -> int:
    # ---- valley at dusk
    bed("ambience/forest_night.ogg", 0.0, 19.5, -8.0, 2.0)
    bed("ambience/wind_layer.ogg", 0.0, 19.5, -17.0, 2.0)
    fire = A.load(os.path.join(AUD, "world/fire_loop_01.ogg"))
    fl = np.concatenate([fire] * 3)[: A.n_of(18.5)]
    fl *= np.concatenate([np.linspace(0, 1, A.n_of(1.0)), np.ones(A.n_of(15.5)), np.linspace(1, 0, A.n_of(2.0))])
    mixbuf[: len(fl)] += A.pan(fl * 0.45, 0.55)
    place("ambience/crow_02.ogg", 1.5, -60, -80, 2.0, unit=30)
    t = 0.8
    k = 0
    while t < 7.2:   # walking on fresh snow (stride 0.55 s)
        place(f"player/step_snow_{k % 8 + 1:02d}.ogg", t, 0.0, -0.3, -6.0 + rng.uniform(-1, 1), unit=2.5, pitch=rng.uniform(0.97, 1.03))
        t += 0.55 + rng.uniform(-0.03, 0.03)
        k += 1
    place("ambience/owl_02.ogg", 4.5, 70, -90, 0.0, unit=30)
    place("creatures/zombie_groan_03.ogg", 7.4, -18, -14, -2.0, unit=4)
    place("creatures/zombie_alert_02.ogg", 9.3, -13, -10, 0.0, unit=6)
    t = 10.2
    zx, zz = -12.0, -9.0
    for k in range(5):   # shambling in
        place(f"creatures/zombie_step_{k % 8 + 1:02d}.ogg", t, zx, zz, -3.0, unit=2.5)
        zx += 1.4
        zz += 1.0
        t += 0.62
    shot("pistol", "light", "forest", 11.8, 0.0, -0.4, 1)
    place("weapons/casing_brass_snow_02.ogg", 12.2, 0.6, 0.2, -10.0, unit=1.5)
    place("weapons/impact_flesh_02.ogg", 11.82, zx, zz, -2.0, unit=3)
    place("creatures/zombie_hurt_03.ogg", 11.9, zx, zz, 0.0, unit=4)
    shot("pistol", "light", "forest", 12.45, 0.0, -0.4, 2)
    place("weapons/impact_snow_01.ogg", 12.47, zx + 1.5, zz - 1.0, -2.0, unit=3)
    shot("shotgun", "heavy", "forest", 13.5, 0.0, -0.4, 1)
    place("weapons/mech_pump_back_01.ogg", 13.82, 0.0, -0.4, -2.0, unit=3)
    place("weapons/mech_pump_fwd_02.ogg", 13.97, 0.0, -0.4, -2.0, unit=3)
    place("weapons/casing_hull_snow_01.ogg", 14.2, 0.8, 0.4, -10.0, unit=1.5)
    place("creatures/zombie_die_02.ogg", 13.55, zx, zz, 0.0, unit=5)
    for k, tt in enumerate((15.6, 16.3)):   # reload two shells (LongGun_Reload_Shell: grab 0.08, in 0.46)
        place(f"weapons/mech_pouch_0{k + 1}.ogg", tt + 0.08, 0.2, -0.3, -8.0, unit=1.5)
        place(f"weapons/mech_shell_in_0{k + 1}.ogg", tt + 0.46, 0.2, -0.3, -3.0, unit=2)
    place("creatures/wolf_howl_02.ogg", 16.0, 0, -200, -2.0, unit=60, lpf_far=2500, maxd=400)
    # ---- Altavega
    bed("ambience/city_day.ogg", 17.5, DUR, -7.0, 3.5)
    bed("ambience/wind_layer.ogg", 17.5, DUR, -19.0, 3.5)
    t = 19.0
    k = 0
    while t < 27.0:
        place(f"player/step_packed_{k % 8 + 1:02d}.ogg", t, 0.0, -0.3, -7.0 + rng.uniform(-1, 1), unit=2.5)
        t += 0.55 + rng.uniform(-0.03, 0.03)
        k += 1
    place("world/car_alarm_02.ogg", 21.0, 90, -140, -6.0, unit=25, lpf_far=1800, maxd=300)
    place("ambience/dog_far_01.ogg", 24.5, -120, -150, 0.0, unit=40, lpf_far=2500, maxd=300)
    place("world/metal_creak_02.ogg", 27.0, 18, -25, -2.0, unit=8, maxd=60)
    place("ambience/tarp_02.ogg", 28.5, -20, -15, -4.0, unit=10, maxd=80)
    shot("rifle", "heavy", "city", 31.0, -250, -300, 2, -6.0)
    place("ambience/shutter_bang_01.ogg", 33.0, 40, -60, -2.0, unit=20)
    place("ambience/scream_far_02.ogg", 35.0, -150, -180, -2.0, unit=40, lpf_far=2000, maxd=300)
    place("ambience/glass_far_02.ogg", 37.5, 80, -90, -4.0, unit=25)
    place("ambience/dog_far_03.ogg", 38.5, 140, -150, -3.0, unit=40, lpf_far=2500, maxd=300)
    # ---- master: fade out, gentle bus compression, limiter
    fade = np.ones(N)
    fade[-A.n_of(2.5):] = np.linspace(1, 0, A.n_of(2.5)) ** 1.5
    y = mixbuf * fade[:, None]
    y = A.compress(y, -16, 2.0, 0.005, 0.2)
    y = y / (np.max(np.abs(y)) + 1e-9) * A.db(-1.0)
    lu = A.integrated_lufs(y)
    y = y * A.db(min(-16.0 - lu, 0.0))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    A.write_ogg(OUT, y, 3.0)
    print(f"demo: {OUT} {len(y) / A.SR:.1f} s, {os.path.getsize(OUT) / 1e3:.0f} kB, {A.integrated_lufs(y):.1f} LUFS, peak {A.peak_db(y):.1f} dBFS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
