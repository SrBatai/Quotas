"""Zombies and wolves (S1).

Zombie voices start from artisticdude's CC0 «Zombies Sound Pack» (OpenGameArt, 24 human-voiced growls), processed
into families: slow idle groans (pitched down, stretched, a throat rattle), the «te he visto» alert (a sharp inhale
then a snarl), attack snarls with the arm's swipe, pained hit grunts, deaths that fall in pitch into a gurgle and a
body drop, chase breaths (designed: noise through a vocal tract), frozen wake (ice cracks timed to Zom_Wake), bloater
pop, shambling steps. Wolves: a designed growl and howl (glottal pulses through wolf formants, vibrato), rubberduck's
CC0 creature pack for the yelp / whine, bites from teeth clacks and wet impacts.
"""
from __future__ import annotations

import numpy as np

import audiolib as A
from recipes_weapons import metal_click, src

ZPACK = "zombies-sound-pack"
GROAN_SRC = [16, 17, 18, 19, 20, 21, 1, 9, 15, 2, 14, 8]
ALERT_SRC = [10, 4, 12, 7, 5, 22]
ATTACK_SRC = [11, 13, 3, 6, 23, 12]
HIT_SRC = [24, 5, 13, 3, 11, 7]
DIE_SRC = [17, 16, 21, 18, 20]


def zvoice(i: int) -> np.ndarray:
    return src(ZPACK, f"zombie-{i}.m4a", 60)


def glide(x: np.ndarray, r0: float, r1: float) -> np.ndarray:
    """Time-varying resampling: playback rate glides from r0 to r1 (pitch and speed together)."""
    n = len(x)
    rates = np.linspace(r0, r1, n)
    pos = np.cumsum(rates)
    pos = pos[pos < n - 1]
    return np.interp(pos, np.arange(n), A.mono(x))


def voice_eq(x: np.ndarray, rng, dark: float = 1.0) -> np.ndarray:
    y = A.hp(x, 70)
    y = A.peaking(y, rng.uniform(220, 320), 3.0, 0.8)          # chest
    y = A.peaking(y, rng.uniform(2600, 3600), -3.0 * dark, 1.0)  # take the edge off the human voice
    y = A.lp(y, 7500 / dark, 2)
    return y


def rattle(x: np.ndarray, rng, depth: float = 0.35) -> np.ndarray:
    """Throat rattle: irregular 18–32 Hz amplitude modulation."""
    n = len(x)
    f = rng.uniform(18, 32)
    ph = np.cumsum(f * (1 + 0.3 * A.lp(rng.standard_normal(n), 3))) * 2 * np.pi / A.SR
    am = 1 - depth * (0.5 + 0.5 * np.sign(np.sin(ph)) * np.abs(np.sin(ph)) ** 0.5)
    return x * am


def breath(rng, dur: float, inhale: bool, rasp: float = 0.4, formants=None) -> np.ndarray:
    """Noise through a vocal tract: two or three formant peaks; inhale = rising, higher; exhale = falling."""
    n = A.n_of(dur)
    x = A.noise(n, rng, "pink")
    fm = formants or ([(700, 8, 2.0), (1600, 6, 2.5), (2800, 4, 3.0)] if inhale else [(500, 8, 2.0), (1200, 6, 2.5), (2500, 3, 3.0)])
    y = A.lp(A.bp(x, 150, 4500, 2), 3200 if inhale else 2400, 2)
    for f, g, q in fm:
        y = A.peaking(y, f * rng.uniform(0.9, 1.1), g, q)
    if rasp > 0:  # vocal-fold flutter: an irregular 55–80 Hz amplitude modulation
        fr = rng.uniform(55, 80) * (1 + 0.15 * A.lp(rng.standard_normal(n), 8) * 10)
        y = y * (1 + rasp * np.sin(2 * np.pi * np.cumsum(fr) / A.SR))
    env = A.env_ar(n, dur * (0.65 if inhale else 0.2), dur * (0.3 if inhale else 0.75), 0.0, 1.5)
    return A.fade(y * env, 0.005, 0.02)


def whoosh(rng, dur: float, lo: float = 300, hi: float = 3000, peak_at: float = 0.6) -> np.ndarray:
    """Air moved by an arm / a weapon: band noise with a swept band-pass centre and a peaked envelope."""
    n = A.n_of(dur)
    x = A.noise(n, rng, "pink")
    t = np.linspace(0, 1, n)
    env = np.where(t < peak_at, (t / peak_at) ** 2.2, ((1 - t) / (1 - peak_at)) ** 1.6)
    # swept centre: two band-passes crossfaded
    a = A.bp(x, lo, lo * 3, 2)
    b = A.bp(x, hi / 3, hi, 2)
    w = np.clip((t - peak_at * 0.5) / peak_at, 0, 1)
    y = (a * (1 - w) + b * w) * env
    return A.fade(y / (np.max(np.abs(y)) + 1e-9), 0.003, 0.02)


def snow_body_fall(rng, heavy: float = 1.0) -> np.ndarray:
    """A body dropping in snow: a dull low thump, compacting crunch, a cloth flap."""
    n = A.n_of(0.5)
    th = A.lp(A.noise(n, rng, "brown"), 180 * heavy ** -0.3) * A.env_exp(n, 0.06 * heavy, 0.004)
    cr = A.grains(n, rng, np.linspace(1400, 50, n), 0.004, (700, 5000), A.env_ar(n, 0.005, 0.35))
    cl = A.bp(A.noise(A.n_of(0.12), rng), 400, 2500) * A.env_ar(A.n_of(0.12), 0.01, 0.1)
    return A.mix((th / (np.max(np.abs(th)) + 1e-9), 0, 0), (cr / (np.max(np.abs(cr)) + 1e-9), 0.003, -7), (cl, 0.0, -12))


def ice_crack(rng, big: float = 1.0) -> np.ndarray:
    """Ice breaking: a sharp broadband snap, a burst of micro-fractures and a short glassy ring."""
    n = A.n_of(0.35)
    snap = A.hp(A.noise(A.n_of(0.003), rng), 1500) * np.hanning(A.n_of(0.003))
    fr = A.grains(n, rng, np.linspace(3000 * big, 30, n), 0.0008, (2500, 12000), A.env_exp(n, 0.05 * big, 0.0005))
    exc = np.zeros(n)
    exc[0] = 1
    ring = A.modal(exc, [(rng.uniform(1800, 2600), 0.03, 0), (rng.uniform(4200, 5200), 0.02, -4), (rng.uniform(7000, 8500), 0.012, -8)])
    return A.mix((snap / (np.max(np.abs(snap)) + 1e-9), 0, 0), (fr / (np.max(np.abs(fr)) + 1e-9), 0.001, -4),
                 (ring / (np.max(np.abs(ring)) + 1e-9), 0.0, -14))


def snow_step(rng, weight: float = 1.0, drag: float = 0.0) -> np.ndarray:
    """One foot into fresh snow: crunch grains in a compacting burst; `drag` s of scrape before it (shamble)."""
    d = 0.22 + 0.1 * weight
    n = A.n_of(d)
    k = A.n_of(0.03)
    rate = np.concatenate([np.linspace(200, 2500 * weight, k), np.linspace(2500 * weight, 100, n - k)])
    cr = A.grains(n, rng, rate, 0.0025, (500, 7000), A.env_ar(n, 0.02, d, 0.0))
    th = A.lp(A.noise(A.n_of(0.08), rng, "brown"), 250) * A.env_exp(A.n_of(0.08), 0.02, 0.005)
    step = A.mix((cr / (np.max(np.abs(cr)) + 1e-9), 0, 0), (th / (np.max(np.abs(th)) + 1e-9), 0, -8 + 4 * (weight - 1)))
    if drag <= 0:
        return A.fade(step, 0.002, 0.04)
    m = A.n_of(drag)
    sc = A.bp(A.noise(m, rng, "pink"), 600, 4000) * A.env_ar(m, drag * 0.3, drag * 0.7)
    gr = A.grains(m, rng, 500, 0.003, (800, 4000))
    sc = sc / (np.max(np.abs(sc)) + 1e-9) + gr / (np.max(np.abs(gr)) + 1e-9) * 0.5
    return A.fade(A.mix((sc, 0, -8), (step, drag * 0.8, 0)), 0.01, 0.04)


def wolf_voice(rng, dur: float, f_curve, formants, breath_db: float = -14, vib=(5.0, 0.012), rough: float = 0.0) -> np.ndarray:
    """Glottal-like pulse train (band-limited sawtooth) following `f_curve` (Hz per sample), through the wolf's vocal
    tract (formant resonances), with vibrato, breath noise and an optional roughness (sub-harmonic)."""
    n = A.n_of(dur)
    t = np.arange(n) / A.SR
    f = np.asarray(f_curve) * (1 + vib[1] * np.sin(2 * np.pi * vib[0] * t + rng.uniform(0, 6)))
    ph = np.cumsum(f) / A.SR
    saw = np.zeros(n)
    for k in range(1, 18):
        mask = (f * k) < 9000
        saw += np.sin(2 * np.pi * k * ph) / k * mask * (0.95 ** k)
    if rough > 0:
        saw *= 1 + rough * np.sin(2 * np.pi * ph * 0.5)
    y = np.zeros(n)
    for fm, bw, g in formants:
        y += A.bp(saw, fm - bw / 2, fm + bw / 2, 2) * A.db(g)
    y += A.bp(A.noise(n, rng, "pink"), 400, 5000) * A.db(breath_db) * np.std(y) * 3
    return y / (np.max(np.abs(y)) + 1e-9)


# ------------------------------------------------------------------ recipes
def build(out):
    rng = np.random.default_rng(2203)
    # --- zombie idle groans (≥ 4 families × variations)
    for i in range(12):
        x = zvoice(GROAN_SRC[i % len(GROAN_SRC)])
        semis = rng.uniform(-4.5, -2.0)
        x = A.pitch(x, semis)
        if rng.random() < 0.5:
            x = A.time_stretch(x, rng.uniform(1.2, 1.5), 0.05)
        x = voice_eq(x, rng)
        x = rattle(x, rng, rng.uniform(0.15, 0.4))
        tail = breath(rng, rng.uniform(0.35, 0.55), False, 0.5, [(420, 7, 2), (1100, 5, 2.5)])
        x = A.mix((A.fade(x, 0.06, 0.2), 0, 0), (tail, len(x) / A.SR - 0.1, -16))
        out(f"creatures/zombie_groan_{i + 1:02d}", x, "creature_vocal")
    # --- «te he visto»: a sharp inhale then a snarl
    for i in range(6):
        inh = breath(rng, rng.uniform(0.16, 0.24), True, 0.6)
        sn = A.pitch(zvoice(ALERT_SRC[i]), rng.uniform(-3.0, -1.0))
        sn = A.saturate(voice_eq(sn, rng, 0.9) / (np.max(np.abs(sn)) + 1e-9), 1.8)
        x = A.mix((inh, 0, -6), (sn, len(inh) / A.SR - 0.03, 0))
        out(f"creatures/zombie_alert_{i + 1:02d}", x, "creature_vocal", gain_db=2.0)
    # --- attack: snarl + the arm's swipe (Zom_Attack_A swing at 0.3 s)
    for i in range(6):
        sn = A.pitch(zvoice(ATTACK_SRC[i]), rng.uniform(-2.5, -0.5))
        sn = voice_eq(sn, rng)[: A.n_of(0.55)]
        sw = whoosh(rng, rng.uniform(0.22, 0.3), 200, 2200, 0.7)
        x = A.mix((A.fade(sn, 0.005, 0.12), 0, 0), (sw, 0.14, -9))
        out(f"creatures/zombie_attack_{i + 1:02d}", x, "creature_vocal", gain_db=1.0)
    # --- hit reaction grunts (short)
    for i in range(6):
        x = A.pitch(zvoice(HIT_SRC[i]), rng.uniform(-2.5, 0.0))
        k = rng.uniform(0.18, 0.32)
        start = int(np.argmax(np.abs(x)) * 0.5)
        x = voice_eq(x[start:start + A.n_of(k)], rng)
        out(f"creatures/zombie_hurt_{i + 1:02d}", A.fade(x, 0.004, 0.08), "creature_vocal", gain_db=-1.0)
    # --- deaths: falling pitch into a gurgle, then the body drops (Zom_Death ground ≈ 0.6 s)
    for i in range(5):
        v = zvoice(DIE_SRC[i])
        v = glide(A.pitch(v, rng.uniform(-3, -1.5)), 1.0, rng.uniform(0.7, 0.8))
        v = voice_eq(v, rng)
        g = src("80-cc0-creature-sfx", f"burble-0{1 + i % 2}.m4a", 100)
        g = A.lp(A.pitch(g, rng.uniform(-6, -3)), 1800, 4)
        fall = snow_body_fall(rng, 1.2)
        x = A.mix((A.fade(v, 0.01, 0.25), 0, 0), (g[: A.n_of(0.6)], len(v) / A.SR * 0.6, -10), (fall, 0.62 + rng.uniform(-0.05, 0.1), -4))
        out(f"creatures/zombie_die_{i + 1:02d}", x, "creature_vocal", gain_db=1.0)
    # --- chase breaths (ragged panting cycles, rasp)
    for i in range(6):
        parts = []
        t = 0.0
        for _ in range(2):
            d_in = rng.uniform(0.18, 0.28)
            d_out = rng.uniform(0.28, 0.4)
            parts.append((breath(rng, d_in, True, 0.7), t, -3))
            parts.append((breath(rng, d_out, False, 0.8, [(380, 8, 2), (1000, 6, 2.5), (2300, 3, 3)]), t + d_in * 0.9, 0))
            t += d_in + d_out + rng.uniform(0.02, 0.08)
        x = A.mix(*parts)
        v = A.pitch(zvoice(GROAN_SRC[(i + 3) % len(GROAN_SRC)]), -4.0)[: len(x)]
        x = A.mix((x, 0, 0), (voice_eq(A.pad_to(v, len(x)), rng) * A.env_ar(len(x), 0.1, 0.3, len(x) / A.SR - 0.4), 0, -16))
        out(f"creatures/zombie_breath_{i + 1:02d}", x, "creature_vocal", gain_db=-4.0)
    # --- frozen wake: two ice cracks (Zom_Wake crack_1 0.30 / crack_2 0.62) and the groan as it breaks free (1.05)
    for i in range(3):
        g = A.pitch(zvoice(GROAN_SRC[(i * 5) % len(GROAN_SRC)]), -4.0)
        x = A.mix((ice_crack(rng, 0.8), 0.0, -4), (ice_crack(rng, 1.3), 0.30 + rng.uniform(-0.02, 0.02), 0),
                  (ice_crack(rng, 1.6), 0.62 + rng.uniform(-0.02, 0.02), 0),
                  (A.grains(A.n_of(0.5), rng, 400, 0.001, (3000, 11000), A.env_ar(A.n_of(0.5), 0.02, 0.45)) * 8, 0.64, -8),
                  (A.pad_to(voice_eq(g, rng), A.n_of(0.9)) * A.env_ar(A.n_of(0.9), 0.15, 0.6, 0.15), 0.95, 3))
        out(f"creatures/frozen_wake_{i + 1:02d}", x, "creature_fx")
    # --- bloater pop: a wet burst, a low thump, gas hiss, splatter falling
    for i in range(3):
        n = A.n_of(1.4)
        th = A.lp(A.noise(A.n_of(0.25), rng, "brown"), 160) * A.env_exp(A.n_of(0.25), 0.05, 0.003)
        sp = src("8-wet-squish-slurp-impacts", f"impactsplat0{1 + (i * 3) % 8}-mp3.m4a")
        sp2 = A.pitch(src("40-cc0-water-splash-slime-sfx", f"slime-{1 + (i * 5) % 16:02d}.m4a"), -3)
        hiss = A.bp(A.noise(n, rng), 1500, 7000) * A.env_ar(n, 0.01, 1.2)
        drops = A.grains(n, rng, np.linspace(60, 3, n), 0.02, (300, 2500), A.env_ar(n, 0.1, 1.0))
        x = A.mix((th / (np.max(np.abs(th)) + 1e-9), 0, 0), (sp[: A.n_of(0.4)], 0.0, -2), (sp2[: A.n_of(0.6)], 0.02, -6),
                  (hiss, 0.03, -18), (drops / (np.max(np.abs(drops)) + 1e-9), 0.15, -14))
        out(f"creatures/bloater_pop_{i + 1:02d}", x, "creature_fx", gain_db=2.0)
    # --- stagger (a hit that pushes it back) and knockdown (body in the snow)
    for i in range(3):
        v = A.pitch(zvoice(HIT_SRC[(i + 2) % 6]), -2.5)[: A.n_of(0.3)]
        x = A.mix((A.fade(voice_eq(v, rng), 0.005, 0.1), 0, 0), (snow_step(rng, 1.2, 0.15), 0.08, -8))
        out(f"creatures/zombie_stagger_{i + 1:02d}", x, "creature_vocal", gain_db=-2.0)
        out(f"creatures/zombie_knock_{i + 1:02d}", snow_body_fall(rng, 1.3), "creature_fx", gain_db=-2.0)
    # --- shambling steps: a dragged foot into snow
    for i in range(8):
        out(f"creatures/zombie_step_{i + 1:02d}", snow_step(rng, rng.uniform(1.0, 1.3), rng.uniform(0.08, 0.2) if i % 2 == 0 else 0.0), "footstep", gain_db=-3.0)
    # --- wolves
    wolf_f = [(650, 300, 0), (1450, 500, -5), (2600, 700, -10), (3800, 900, -16)]
    for i in range(3):
        d = rng.uniform(2.6, 3.4)
        n = A.n_of(d)
        tt = np.linspace(0, 1, n)
        f0 = rng.uniform(380, 450)
        peak = f0 * rng.uniform(1.45, 1.7)
        curve = np.where(tt < 0.25, f0 + (peak - f0) * np.sin(tt / 0.25 * np.pi / 2), peak - (peak - f0 * 0.85) * np.clip((tt - 0.25) / 0.75, 0.0, 1.0) ** 1.8)
        v = wolf_voice(rng, d, curve, wolf_f, -16, (5.5, 0.01))
        v *= A.env_points(n, [(0, 0), (0.25, 0.8), (d * 0.3, 1.0), (d * 0.85, 0.8), (d, 0)])
        tail = A.reverb_tail(v, A.make_ir("forest", rng), 0.0)[: n + A.n_of(1.5)]
        x = A.mix((A.lp(v, 5000), 0, -2), (tail / (np.max(np.abs(tail)) + 1e-9), 0, -8))
        out(f"creatures/wolf_howl_{i + 1:02d}", x, "creature_vocal", gain_db=-2.0)
    for i in range(4):
        d = rng.uniform(0.9, 1.4)
        n = A.n_of(d)
        curve = rng.uniform(70, 95) * (1 + 0.15 * np.sin(np.linspace(0, np.pi, n)))
        g = wolf_voice(rng, d, curve, [(350, 250, 0), (900, 400, -4), (2000, 600, -10)], -10, (7.0, 0.03), 0.6)
        g = rattle(g, rng, 0.5) * A.env_ar(n, 0.12, 0.35, d - 0.47)
        g = A.saturate(g, 2.0)
        out(f"creatures/wolf_growl_{i + 1:02d}", A.lp(g, 4500), "creature_vocal", gain_db=-2.0)
    for i in range(3):
        clack = A.mix((metal_click(rng, 2.5, 0.4, 0.3, 0.0), 0, 0))
        clack = A.lp(clack, 3500)
        sq = src("8-wet-squish-slurp-impacts", f"impactsplat0{2 + i * 2}-mp3.m4a")[: A.n_of(0.3)]
        sn = wolf_voice(rng, 0.35, np.linspace(160, 120, A.n_of(0.35)), [(500, 300, 0), (1300, 500, -4)], -6, (9, 0.03), 0.8)
        x = A.mix((sn * A.env_ar(A.n_of(0.35), 0.02, 0.3), 0, -4), (clack, 0.09, 0), (sq, 0.1, -3))
        out(f"creatures/wolf_bite_{i + 1:02d}", x, "creature_fx")
    for i in range(3):
        y = A.pitch(src("80-cc0-creture-sfx-2", "die-04.m4a"), rng.uniform(2.0, 4.0))[: A.n_of(0.35)]
        out(f"creatures/wolf_hurt_{i + 1:02d}", A.fade(A.lp(y, 5000, 4), 0.004, 0.1), "creature_vocal", gain_db=-2.0)
    for i in range(2):
        y = glide(A.pitch(src("80-cc0-creture-sfx-2", ["die-04.m4a", "die-02.m4a"][i]), 1.0), 1.0, 0.75)
        x = A.mix((A.fade(A.lp(y, 6000), 0.005, 0.25), 0, 0), (snow_body_fall(rng, 0.8), 0.45, -6))
        out(f"creatures/wolf_die_{i + 1:02d}", x, "creature_vocal")
