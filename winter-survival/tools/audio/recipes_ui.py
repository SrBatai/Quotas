"""UI of the HUD «Susurro» and the few music stingers (S1; docs/research/10_hud_ux.md appendix §5.6); H3 adds the radio
static and the two pings at the end (build_h3, own seed).

UI: soft, short, organic — wood ticks, paper, a felt-muted string, cold glass — never a beep: every tone has an
inharmonic partial set, a noise attack and a quick natural decay, and they sit at −22 LUFS (momentary) under the
game. Stingers: no music in a loop (GDD §14): short cues made of a bowed-glass drone, a low felt hit and a
string-like pad of detuned partials, stereo.
"""
from __future__ import annotations

import numpy as np

import audiolib as A
from recipes_player import heartbeat, kick
from recipes_weapons import src


def wood_tick(rng, f=None, dur: float = 0.06) -> np.ndarray:
    n = A.n_of(dur)
    exc = A.bp(A.noise(A.n_of(0.002), rng), 800, 8000) * np.hanning(A.n_of(0.002))
    f = f or rng.uniform(1500, 1900)
    y = A.modal(A.pad_to(exc, n), [(f, 0.012, 0), (f * 2.4, 0.008, -5), (f * 4.1, 0.005, -10)])
    return A.fade(y / (np.max(np.abs(y)) + 1e-9) + A.pad_to(exc, n) * 0.4, 0.0, 0.01)


def pluck(rng, f: float, dur: float = 0.5, bright: float = 0.5, damp: float = 0.996) -> np.ndarray:
    """Karplus–Strong string (felt-muted when `damp` is low)."""
    n = A.n_of(dur)
    p = int(A.SR / f)
    buf = A.lp(rng.uniform(-1, 1, p), 1500 + 6000 * bright, 1)
    y = np.zeros(n)
    for i in range(n):
        v = buf[i % p]
        y[i] = v
        buf[i % p] = damp * 0.5 * (v + buf[(i + 1) % p])
    return A.fade(A.hp(y, 60), 0.001, 0.05)


def glass(rng, f: float, dur: float = 1.2, decay: float = 0.6) -> np.ndarray:
    """Cold glass / small bell: inharmonic partials with individual decays and a soft mallet."""
    n = A.n_of(dur)
    exc = np.zeros(n)
    k = A.n_of(0.003)
    exc[:k] = np.hanning(k)
    y = A.modal(exc, [(f, decay, 0), (f * 2.76, decay * 0.5, -6), (f * 5.40, decay * 0.3, -12), (f * 8.93, decay * 0.18, -18),
                      (f * 1.003, decay, -2)])
    return A.fade(y / (np.max(np.abs(y)) + 1e-9), 0.0, 0.1)


def radio_blip(rng, f: float, dur: float) -> np.ndarray:
    n = A.n_of(dur)
    t = np.arange(n) / A.SR
    tone = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2 * t)
    tone *= A.env_ar(n, 0.008, 0.04, dur - 0.05)
    st = A.bp(A.noise(n, rng), 400, 3500) * 0.12
    return A.bp(A.saturate(tone + st, 1.5), 300, 3200, 2)


def pad(rng, freqs, dur: float, attack: float, release: float, detune: float = 0.004, bright: float = 2500) -> np.ndarray:
    """Soft string-like pad: detuned sawtooth partial sets per note, low-passed, slow envelope, stereo."""
    n = A.n_of(dur)
    t = np.arange(n) / A.SR
    ch = []
    for c in range(2):
        y = np.zeros(n)
        for f in freqs:
            for d in (-detune, 0.0, detune):
                ff = f * (1 + d + rng.uniform(-0.001, 0.001))
                ph = rng.uniform(0, 2 * np.pi)
                for h in range(1, 12):
                    if ff * h > 8000:
                        break
                    y += np.sin(2 * np.pi * ff * h * t + ph * h) / h
        y = A.lp(y, bright, 2)
        ch.append(y)
    x = np.stack(ch, axis=1)
    env = A.env_points(n, [(0, 0), (attack, 1), (dur - release, 0.85), (dur, 0)])
    return x * env[:, None] / (np.max(np.abs(x)) + 1e-9)


def bowed_glass(rng, f: float, dur: float) -> np.ndarray:
    n = A.n_of(dur)
    t = np.arange(n) / A.SR
    y = np.zeros(n)
    for r, g in ((1.0, 0), (2.0, -9), (3.0, -16), (4.02, -20)):
        y += np.sin(2 * np.pi * f * r * t * (1 + 0.0015 * np.sin(2 * np.pi * 4.5 * t))) * A.db(g)
    y *= 1 + 0.15 * np.sin(2 * np.pi * rng.uniform(3, 5) * t)
    y += A.bp(A.noise(n, rng), f * 0.9, f * 1.2) * 0.05
    return y / (np.max(np.abs(y)) + 1e-9)


def felt_hit(rng, f: float = 55) -> np.ndarray:
    n = A.n_of(1.8)
    s = A.sine_sweep(n, f * 1.8, f, 0.03) * A.env_exp(n, 0.45, 0.004)
    s += A.lp(A.noise(n, rng, "brown"), 200) * A.env_exp(n, 0.1, 0.002) * 0.6
    return s / (np.max(np.abs(s)) + 1e-9)


def stereo_room(x: np.ndarray, rng, wet_db: float = -8, kind: str = "forest") -> np.ndarray:
    ir = A.make_ir(kind, rng, stereo=True)
    xs = x if x.ndim == 2 else np.stack([x, x], axis=1)
    w = A.convolve(xs, ir)
    w = w / (np.max(np.abs(w)) + 1e-9) * np.max(np.abs(xs))
    return A.mix((xs, 0, 0), (w, 0, wet_db))


# note helpers (A minor-ish, cold): A2 110, D3 146.8, E3 164.8, A3 220, C4 261.6, E4 329.6, A4 440
def build(out):
    rng = np.random.default_rng(6603)
    # --- UI
    for i in range(3):
        out(f"ui/click_{i + 1:02d}", wood_tick(rng, rng.uniform(1500, 1800)), "ui", gain_db=-2.0)
    for i in range(2):
        n = A.n_of(0.22)
        sw = A.bp(A.noise(n, rng, "pink"), 600, 5000) * A.env_points(n, [(0, 0), (0.15, 1), (0.22, 0)])
        out(f"ui/open_{i + 1:02d}", A.mix((sw / (np.max(np.abs(sw)) + 1e-9), 0, -8), (wood_tick(rng, 1300), 0.17, 0)), "ui", gain_db=-2.0)
        sw2 = A.bp(A.noise(n, rng, "pink"), 400, 3500) * A.env_points(n, [(0, 0), (0.04, 1), (0.22, 0)])
        out(f"ui/close_{i + 1:02d}", A.mix((wood_tick(rng, 1100), 0, 0), (sw2 / (np.max(np.abs(sw2)) + 1e-9), 0.01, -10)), "ui", gain_db=-3.0)
    out("ui/map_open_01", A.mix((src("kenney_rpgaudio", "bookOpen.ogg", 150), 0, 0), (src("kenney_rpgaudio", "bookFlip1.ogg", 150), 0.12, -6)), "ui")
    out("ui/map_close_01", src("kenney_rpgaudio", "bookClose.ogg", 150), "ui")
    for i in range(3):
        out(f"ui/tab_{i + 1:02d}", src("kenney_rpgaudio", f"bookFlip{1 + i}.ogg", 200), "ui", gain_db=-4.0)
    for i in range(2):
        n = A.n_of(0.5)
        sc = A.bp(A.noise(n, rng), 1500, 7000) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * rng.uniform(7, 11) * np.arange(n) / A.SR))) * A.env_ar(n, 0.03, 0.2, 0.25)
        out(f"ui/mark_{i + 1:02d}", sc, "ui", gain_db=-6.0)
    # info veil: a breath of air and a faint cold glass (open rises, close falls)
    n = A.n_of(0.45)
    air = A.bp(A.noise(n, rng, "pink"), 800, 6000)
    out("ui/info_open_01", A.mix((air * A.env_points(n, [(0, 0), (0.35, 1), (0.45, 0)]), 0, -10), (glass(rng, 1320, 0.8, 0.35), 0.25, -14)), "ui", gain_db=-6.0)
    out("ui/info_close_01", A.mix((air * A.env_points(n, [(0, 0), (0.05, 1), (0.45, 0)]), 0, -10), (glass(rng, 990, 0.6, 0.25), 0.0, -16)), "ui", gain_db=-7.0)
    for i in range(3):
        l = src("kenney_rpgaudio", ["handleSmallLeather.ogg", "handleSmallLeather2.ogg", "cloth4.ogg"][i], 200)[: A.n_of(0.18)]
        out(f"ui/pickup_{i + 1:02d}", A.mix((l, 0, 0), (wood_tick(rng, 2000, 0.04), 0.0, -10)), "ui", gain_db=-3.0)
    # P1 warning: a low double radio blip; hazard: the same, deeper, with a gust behind it
    out("ui/warn_01", A.mix((radio_blip(rng, 440, 0.12), 0, 0), (radio_blip(rng, 440, 0.12), 0.2, -1)), "ui", gain_db=-2.0)
    n = A.n_of(1.0)
    gust = A.bp(A.noise(n, rng, "pink"), 250, 1800) * A.env_points(n, [(0, 0), (0.4, 1), (1.0, 0)])
    out("ui/hazard_01", A.mix((radio_blip(rng, 330, 0.16), 0, 0), (radio_blip(rng, 330, 0.16), 0.24, -1), (gust / (np.max(np.abs(gust)) + 1e-9), 0.05, -10)), "ui")
    # objectives: a dry muted string; done = two warm notes a fifth apart; hold tick / done; craft; level
    out("ui/objective_update_01", pluck(rng, 196.0, 0.35, 0.35, 0.985), "ui")
    out("ui/objective_done_01", A.mix((pluck(rng, 220.0, 0.7, 0.45, 0.994), 0, 0), (pluck(rng, 329.6, 0.8, 0.45, 0.994), 0.14, -1)), "ui")
    out("ui/hold_tick_01", wood_tick(rng, 2200, 0.04), "ui", gain_db=-8.0)
    out("ui/hold_done_01", A.mix((wood_tick(rng, 1500), 0, 0), (glass(rng, 1760, 0.7, 0.3), 0.02, -8)), "ui", gain_db=-3.0)
    out("ui/level_01", A.mix((glass(rng, 880, 1.0, 0.5), 0, -2), (glass(rng, 1108.7, 1.0, 0.5), 0.1, -3), (glass(rng, 1318.5, 1.2, 0.6), 0.2, -2)), "ui")
    # teammate down (P0): double heartbeat + radio static
    n = A.n_of(1.0)
    stat = A.bp(A.noise(n, rng), 500, 4000) * A.env_points(n, [(0, 0), (0.05, 1), (0.3, 0.3), (0.6, 0.6), (1.0, 0)])
    out("ui/mate_down_01", A.mix((heartbeat(rng), 0, 0), (heartbeat(rng), 0.55, -2), (stat, 0, -16)), "ui", gain_db=2.0)
    # --- stingers (stereo, a few seconds, never a loop)
    # nightfall: a low bowed glass drone opens with a dark pad (A2 + E3), a cold high partial above
    d = 5.5
    x = A.mix((pad(rng, [110.0, 164.8], d, 1.8, 2.5, bright=900), 0, -2), (np.stack([bowed_glass(rng, 440.0, d)] * 2, axis=1) * A.env_points(A.n_of(d), [(0, 0), (2.5, 0.6), (4.0, 0.4), (d, 0)])[:, None], 0.3, -14))
    out("music/stinger_night", stereo_room(x, rng, -10), "stinger", gain_db=-4.0)
    # dawn: a soft rising open fifth (D3 + A3 + E4), warmer
    d = 4.5
    x = pad(rng, [146.8, 220.0, 329.6], d, 1.2, 2.0, bright=2200)
    out("music/stinger_dawn", stereo_room(x, rng, -10), "stinger", gain_db=-5.0)
    # danger / horde: a felt hit under a dissonant cluster swelling (A2 + Bb2 + E3)
    d = 4.0
    cl = pad(rng, [110.0, 116.5, 164.8], d, 0.8, 1.8, 0.008, 1400)
    x = A.mix((np.stack([felt_hit(rng, 55.0)] * 2, axis=1), 0, 0), (cl, 0.05, -4))
    out("music/stinger_danger", stereo_room(x, rng, -9), "stinger", gain_db=-2.0)
    # mission done: warm pad (A3 C4 E4) with two glass notes a fifth apart (≈ 2.5 s)
    d = 3.0
    x = A.mix((pad(rng, [220.0, 261.6, 329.6], d, 0.5, 1.6, bright=2600), 0, -3),
              (np.stack([glass(rng, 659.3, 2.2, 0.9)] * 2, axis=1), 0.05, -8), (np.stack([glass(rng, 987.8, 2.2, 0.9)] * 2, axis=1), 0.3, -9))
    out("music/stinger_mission", stereo_room(x, rng, -10), "stinger", gain_db=-3.0)
    # win (5 days survived): a longer resolving chord
    d = 6.5
    x = A.mix((pad(rng, [110.0, 164.8, 220.0, 277.2], d, 1.5, 3.0, bright=2400), 0, 0), (pad(rng, [146.8, 220.0, 293.7, 370.0], d - 2.5, 1.2, 2.0, bright=2800), 2.5, -2))
    out("music/stinger_win", stereo_room(x, rng, -9), "stinger", gain_db=-3.0)
    # death: a dark falling drone
    d = 5.0
    p = pad(rng, [82.4, 123.5], d, 0.4, 3.0, bright=700)
    x = A.mix((np.stack([felt_hit(rng, 41.0)] * 2, axis=1), 0, -2), (p, 0, 0))
    out("music/stinger_death", stereo_room(x, rng, -8), "stinger", gain_db=-4.0)
    # --- H3 (appended last with its own seed: the files above stay byte-identical)
    build_h3(out)


def radio_static(rng, dur: float = 0.9) -> np.ndarray:
    """Hand-radio static: squelch opening click, band-limited hiss with a fluttering level and a far carrier that
    drifts in and out (no voice), squelch tail at the end. Soft: it sits under the game (−22 LUFS momentary)."""
    n = A.n_of(dur)
    t = np.arange(n) / A.SR
    hiss = A.bp(A.noise(n, rng, "white"), 450, 3400, 2)
    flutter = 0.55 + 0.45 * np.abs(np.sin(2 * np.pi * rng.uniform(7.5, 11.0) * t + rng.uniform(0, 6.28)))
    flutter *= 0.8 + 0.2 * np.sin(2 * np.pi * rng.uniform(1.5, 2.5) * t)
    hiss *= flutter
    carrier = np.sin(2 * np.pi * (rng.uniform(820, 900) + 18 * np.sin(2 * np.pi * 0.9 * t)) * t)
    carrier *= A.env_points(n, [(0, 0), (0.25 * dur, 0.0), (0.45 * dur, 0.18), (0.7 * dur, 0.05), (dur, 0)])
    body = (hiss + carrier * 0.6) * A.env_points(n, [(0, 0), (0.02, 1), (dur - 0.12, 0.85), (dur - 0.04, 0.2), (dur, 0)])
    click_n = A.n_of(0.012)
    click = A.bp(A.noise(click_n, rng), 900, 6000) * np.hanning(click_n) * 2.2
    tail_n = A.n_of(0.05)
    tail = A.bp(A.noise(tail_n, rng), 1200, 5000) * A.env_exp(tail_n, 0.012, 0.001) * 1.6
    y = A.mix((body / (np.max(np.abs(body)) + 1e-9), 0, 0), (click, 0.0, -2), (tail, dur - 0.06, -4))
    return A.bp(A.saturate(y, 1.3), 300, 3800, 2)


def build_h3(out):
    """H3 UI cues (own work, CC0): radio static for a teammate still down (repeats soft every 10 s), the place ping
    (a wooden tick and a small cold glass) and the danger ping (two short falling radio blips); the pings are 3D
    (positioned at the ping), so mono like the rest of the UI."""
    rng = np.random.default_rng(6611)
    for i in range(2):
        out(f"ui/radio_static_{i + 1:02d}", radio_static(rng, 0.85 + 0.1 * i), "ui", gain_db=-3.0)
    out("ui/ping_01", A.mix((wood_tick(rng, 1700, 0.05), 0, -10), (glass(rng, 1568.0, 0.9, 0.9), 0.01, 0),
                            (glass(rng, 2093.0, 0.6, 0.5), 0.07, -8)), "ui", gain_db=-1.0)
    out("ui/ping_danger_01", A.mix((radio_blip(rng, 660, 0.09), 0, 0), (radio_blip(rng, 494, 0.11), 0.13, -1),
                                   (glass(rng, 988.0, 0.4, 0.12), 0.0, -14)), "ui", gain_db=0.0)
