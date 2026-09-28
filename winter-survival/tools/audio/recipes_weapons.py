"""Firearms, bow, reload mechanics, casings and bullet impacts (S1).

Gunshots are designed, not recorded (no CC0 recording of these calibres reachable): a Friedlander blast wave + the
supersonic N-wave for the rifle, a band-limited gas burst with two decay rates, a low body thump (sine glide), the
ground reflection, the action's metal transients (modal synthesis) and a short early-reflection cloud, then soft
saturation. A recorded CC0 cap bang (rubberduck, OpenGameArt) adds a few ms of organic crack texture. Tails are the
dry shot convolved with an algorithmic impulse response of each firing environment (forest / open / city / interior),
wet only, so the game layers close + tail (+ the distant layer beyond ~35 m).
Reload / action sounds are modal-synthesised metal clicks and slides layered with Kenney's metal clicks and latches.
"""
from __future__ import annotations

import numpy as np

import audiolib as A
from sources import use

# ------------------------------------------------------------------ gunshot core
PROFILES = {
    # bands = (lo Hz, hi Hz, decay tau s, gain dB): the highs die first (≈ 8 ms), the low-mids carry the body
    # pistola 9 mm: bright bark, short, slide cycling right after the shot
    "pistol": dict(blast_t=0.0007, crack=0.0,
                   bands=[(3200, 12000, 0.007, -4.0), (900, 3200, 0.018, 0.0), (260, 900, 0.04, -1.0), (45, 260, 0.05, -3.0)],
                   formants=[(1900, 4.0, 1.1), (4200, 3.0, 1.5)], sweep=(150, 60, -8.0), crackle=(0.012, -9.0),
                   refl=(0.0045, -5.0), mech=[(0.022, "slide", -15.0), (0.052, "slide_fwd", -17.0)], rec=-8.0,
                   drive=2.2, length=0.55, er=-13.0, room=(0.16, -26.0)),
    # revólver .357: heavier, lower bark, longer gas, a ring of the frame, no slide
    "revolver": dict(blast_t=0.0010, crack=0.0,
                     bands=[(3000, 11000, 0.008, -5.0), (800, 3000, 0.024, 0.0), (220, 800, 0.06, 0.0), (40, 220, 0.075, -1.5)],
                     formants=[(1350, 5.0, 1.0), (3300, 2.0, 1.4)], sweep=(130, 50, -7.0), crackle=(0.015, -9.0),
                     refl=(0.005, -4.0), mech=[(0.004, "frame_ring", -22.0)], rec=-9.0, drive=2.5, length=0.7,
                     er=-12.0, room=(0.2, -24.0)),
    # escopeta de corredera 12 ga: huge low-mid boom, long burst
    "shotgun": dict(blast_t=0.0016, crack=0.0,
                    bands=[(2800, 9000, 0.010, -6.0), (700, 2800, 0.035, -1.0), (160, 700, 0.09, 0.0), (35, 160, 0.12, 0.0)],
                    formants=[(850, 5.0, 0.9), (2300, 2.0, 1.2)], sweep=(110, 42, -5.0), crackle=(0.02, -8.0),
                    refl=(0.0055, -3.5), mech=[], rec=-11.0, drive=2.8, length=0.95, er=-11.0, room=(0.28, -22.0)),
    # rifle .308: supersonic crack + whip, deep thump, long gas
    "rifle": dict(blast_t=0.0012, crack=0.00035,
                  bands=[(3500, 13000, 0.008, -3.0), (1000, 3500, 0.028, 0.0), (200, 1000, 0.075, -0.5), (35, 200, 0.10, -1.0)],
                  formants=[(2600, 3.0, 1.0), (1100, 3.0, 1.0)], sweep=(100, 40, -6.0), crackle=(0.016, -8.0),
                  refl=(0.006, -4.0), mech=[], rec=-10.0, drive=2.6, length=0.95, er=-11.5, room=(0.26, -23.0)),
}

CAP_BANGS = ["bang-02.m4a", "bang-05.m4a", "bang-08.m4a", "bang-04.m4a"]


def metal_click(rng, size: float = 1.0, bright: float = 1.0, decay: float = 1.0, body_db: float = -8.0) -> np.ndarray:
    """A small steel part hitting steel: a 0.6 ms excitation into a bank of inharmonic modes + a low body knock."""
    n = A.n_of(0.25 * decay + 0.05)
    exc = np.zeros(n)
    k = A.n_of(0.0006)
    exc[:k] = rng.standard_normal(k) * np.hanning(k)
    base = rng.uniform(2300, 3100) / size * bright
    ratios = [1.0, 1.58, 2.31, 2.97, 3.84, 4.62]
    modes = [(base * r * rng.uniform(0.95, 1.05), 0.028 * decay * rng.uniform(0.6, 1.3) / (1 + i * 0.35),
              -3.0 * i + rng.uniform(-3, 2)) for i, r in enumerate(ratios)]
    ring = A.modal(exc, modes)
    knock = A.lp(exc, 900) * A.env_exp(n, 0.012) * 8
    tick = A.hp(exc, 4000) * 2.5
    grit = A.bp(A.noise(n, rng), 2500, 11000) * A.env_exp(n, 0.004, 0.0001)
    out = ring / (np.max(np.abs(ring)) + 1e-9) + knock * A.db(body_db) + tick * A.db(-6) + grit * A.db(-8)
    return A.fade(A.dc_block(out), 0.0, 0.02)


def friction(rng, dur: float, lo: float = 1500, hi: float = 7000, rough_hz: float = 55.0, shape=None) -> np.ndarray:
    """Metal sliding on metal: band noise with a rough amplitude modulation and a bell envelope."""
    n = A.n_of(dur)
    x = A.bp(A.noise(n, rng), lo, hi, 2)
    am = 0.6 + 0.4 * np.abs(np.sin(np.cumsum(rng.uniform(0.7, 1.3, n) * 2 * np.pi * rough_hz / A.SR)))
    env = shape if shape is not None else np.sin(np.linspace(0, np.pi, n)) ** 1.5
    return A.fade(x * am * env, 0.002, 0.004)


def _mech(kind: str, rng) -> np.ndarray:
    if kind == "slide":
        return A.mix((friction(rng, 0.018, 2000, 8000), 0, -6), (metal_click(rng, 1.1, 1.0, 0.6), 0.014, 0))
    if kind == "slide_fwd":
        return metal_click(rng, 1.0, 1.1, 0.5)
    if kind == "frame_ring":
        n = A.n_of(0.25)
        exc = np.zeros(n)
        exc[0] = 1
        return A.modal(exc, [(rng.uniform(2700, 2900), 0.18, 0), (rng.uniform(4000, 4300), 0.12, -4),
                             (rng.uniform(6100, 6500), 0.08, -8)]) * 0.05
    raise KeyError(kind)


def limiter(x: np.ndarray, ceiling_db: float = -1.0, release_s: float = 0.05, look_s: float = 0.0015) -> np.ndarray:
    """Look-ahead peak limiter: the needed gain is min-filtered over the look-ahead window and smoothed (attack =
    look-ahead, exponential release), so the gain never steps (no clicks)."""
    from scipy.ndimage import minimum_filter1d
    c = A.db(ceiling_db)
    m = np.abs(A.mono(x))
    need = np.minimum(1.0, c / np.maximum(m, 1e-9))
    la = max(2, A.n_of(look_s))
    need = minimum_filter1d(need, size=2 * la + 1, origin=0)
    need = np.concatenate([need[la:], np.full(la, need[-1])])  # the window looks ahead
    rel = np.exp(-1.0 / (release_s * A.SR))
    att = np.exp(-1.0 / (look_s * A.SR / 2.0))
    g = np.empty_like(need)
    cur = 1.0
    for i in range(len(need)):
        cur = att * cur + (1 - att) * need[i] if need[i] < cur else rel * cur + (1 - rel) * need[i]
        g[i] = cur
    y = x * (g if x.ndim == 1 else g[:, None])
    p = np.max(np.abs(y))
    return y * (c / p) if p > c else y


def gunshot(kind: str, rng, cap: np.ndarray | None = None, with_sine: bool = True) -> np.ndarray:
    P = PROFILES[kind]
    n = A.n_of(P["length"])
    # 1. blast wave (+ supersonic N-wave for the rifle)
    bt = P["blast_t"] * rng.uniform(0.9, 1.1)
    blast = A.hp(A.friedlander(n, bt, 1.4) * A.env_exp(n, bt * 6), 40)
    parts = [(blast, 0, -2.0)]
    if P["crack"] > 0:
        parts.append((A.hp(A.nwave(n, P["crack"] * rng.uniform(0.9, 1.1)), 1200), 0, -2.0))
    # 2. gas burst: band-split noise, each band with its own decay (the highs die first), voiced by formant peaks
    burst = np.zeros(n)
    for lo, hi, tau, g in P["bands"]:
        bn = A.bp(A.noise(n, rng, "pink"), lo, hi, 2)
        bn = bn / (np.std(bn) + 1e-12)
        burst += bn * A.env_exp(n, tau * rng.uniform(0.85, 1.15), 0.0003) * A.db(g)
    for f, g, q in P["formants"]:
        burst = A.peaking(burst, f * rng.uniform(0.9, 1.1), g, q)
    parts.append((burst / (np.max(np.abs(burst)) + 1e-9), 0.0002, 0.0))
    # 3. turbulent crackle of the first ms
    ct, cg = P["crackle"]
    cr = A.grains(n, rng, 3000, 0.0010, (2000, 12000), A.env_exp(n, ct, 0.0002))
    parts.append((cr / (np.max(np.abs(cr)) + 1e-9), 0.0004, cg))
    # 4. a short pitch-dropping punch under the blast (felt more than heard)
    if with_sine:
        f0, f1, sg = P["sweep"]
        sw = A.sine_sweep(n, f0 * rng.uniform(0.92, 1.08), f1, 0.025) * A.env_exp(n, 0.035, 0.002)
        parts.append((sw, 0.0006, sg))
    # 4b. the close surroundings answering (a soft 150–300 ms room of low-mids, under the tail layer)
    rt, rg = P["room"]
    rm = A.lp(A.bp(A.noise(n, rng, "pink"), 150, 2500, 1), 1800) * A.env_exp(n, rt / 3.0, 0.02)
    parts.append((rm / (np.max(np.abs(rm)) + 1e-9), 0.01, rg))
    # 5. recorded cap crack (organic texture of the first ms)
    if cap is not None:
        m = A.n_of(0.05)
        c = A.hp(cap[:m], 700) * A.env_exp(m, 0.012, 0.0)
        parts.append((c / (np.max(np.abs(c)) + 1e-9), 0.0, P["rec"]))
    # 6. action mechanics
    for t, mk, mg in P["mech"]:
        parts.append((_mech(mk, rng), t * rng.uniform(0.9, 1.1), mg))
    x = A.pad_to(A.mix(*parts), n)
    # 7. ground reflection (comb) + early reflection cloud (the shooter's surroundings at arm's length)
    d, gd = P["refl"]
    x = x + np.concatenate([np.zeros(A.n_of(d * rng.uniform(0.85, 1.15))), A.lp(x, 6000)])[:n] * A.db(gd)
    er = np.zeros(A.n_of(0.035))
    for _ in range(24):
        er[rng.integers(A.n_of(0.004), len(er))] += rng.uniform(-1, 1)
    x = x + A.lp(A.convolve(x, er)[:n], 5000) * A.db(P["er"])
    # 8. density: saturation then limiting (crest factor of a real close recording, ≈ 12 dB)
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = A.saturate(x, P["drive"])
    x = A.dc_block(x, 25)
    x = limiter(x * A.db(4.0), -1.0, 0.06)
    x = A.fade(x, 0.0, P["length"] * 0.5)
    return A.normalize(x, peak=-1.0)


def distant(kind: str, rng, cap=None) -> np.ndarray:
    """The shot 60–150 m away: the direct sound arrives first (dull: air and snow take the highs), then the terrain
    returns it as a rolling boom (diffuse scattering decaying over ~0.3 s); the rifle keeps a soft crack ahead."""
    x = gunshot(kind, rng, cap, with_sine=False)
    L = A.n_of(0.45)
    t = np.arange(L)
    ir = rng.standard_normal(L) * np.exp(-t / A.n_of(0.09)) * 0.05
    ir[: A.n_of(0.01)] *= np.linspace(0, 1, A.n_of(0.01))
    ir[0] = 1.0
    for _ in range(5):  # a few discrete returns (tree lines, slopes)
        ir[rng.integers(A.n_of(0.05), A.n_of(0.35))] += rng.uniform(0.08, 0.2)
    y = A.convolve(x, ir)
    y = A.lp(A.lp(y, 2400 if kind == "rifle" else 1600, 3), 3000, 2)
    y = A.hp(y, 70)
    y = A.shelf(y, 250, 2.0, high=False)
    y = y / (np.max(np.abs(y)) + 1e-9)
    y = limiter(A.saturate(y, 1.2), -3.0, 0.08)
    y = A.fade(A.trim(y, -50, 0.0, 0.05, keep_head=True), 0.0, 0.35)
    return A.normalize(y, peak=-3.0)


def tail(close: np.ndarray, env: str, rng) -> np.ndarray:
    """Wet reverb of the shot in `env`, starting 12 ms after the shot (the game plays it under the close layer)."""
    ir = A.make_ir(env, rng)
    w = A.reverb_tail(close, ir, 0.012)
    w = A.hp(w, 60)
    lengths = {"forest": 2.4, "open": 2.0, "city": 3.4, "interior": 1.0}
    w = A.pad_to(w, A.n_of(lengths[env]))
    w = A.fade(w, 0.004, lengths[env] * 0.35)
    return A.normalize(w, peak=-6.0)


# ------------------------------------------------------------------ mechanics (reload steps, actions)
def src(pack: str, file: str, hp_hz: float = 80.0, thr: float = -50.0) -> np.ndarray:
    x = A.load(use(pack, file))
    return A.trim(A.hp(A.dc_block(x), hp_hz), thr)


def click_pair(rng, a_size=1.0, b_size=0.8, gap=0.03, bright=1.0) -> np.ndarray:
    return A.mix((metal_click(rng, a_size, bright, 0.8), 0, 0), (metal_click(rng, b_size, bright * 1.1, 0.6), gap, -3))


def pouch(rng) -> np.ndarray:
    """Hand into a canvas / leather pouch: cloth rustle + a small rattle of rounds."""
    cl = src("kenney_rpgaudio", rng.choice(["cloth2.ogg", "cloth3.ogg", "cloth4.ogg", "handleSmallLeather.ogg"]), 150)
    rat = A.grains(A.n_of(0.18), rng, 90, 0.004, (2500, 9000), A.env_ar(A.n_of(0.18), 0.02, 0.12))
    return A.mix((cl[: A.n_of(0.35)], 0, 0), (rat / (np.max(np.abs(rat)) + 1e-9), 0.05, -10))


def mag_out(rng) -> np.ndarray:
    fr = friction(rng, 0.09, 1200, 6000, 40, A.env_ar(A.n_of(0.09), 0.01, 0.06))
    return A.mix((metal_click(rng, 1.3, 0.9, 0.7), 0, 0), (fr, 0.012, -9), (metal_click(rng, 1.8, 0.7, 0.5), 0.1, -12))


def mag_in(rng) -> np.ndarray:
    fr = friction(rng, 0.06, 900, 5000, 60, A.env_ar(A.n_of(0.06), 0.04, 0.01))
    th = A.lp(A.noise(A.n_of(0.08), rng, "brown"), 500) * A.env_exp(A.n_of(0.08), 0.015)
    return A.mix((fr, 0, -8), (metal_click(rng, 1.5, 0.8, 0.9, -2.0), 0.055, 0), (th / (np.max(np.abs(th)) + 1e-9), 0.055, -8))


def slide_rack(rng, heavy: float = 1.0) -> np.ndarray:
    """Pull back (friction up) + release forward (hard snap)."""
    back = friction(rng, 0.07 * heavy, 1500, 7000, 70, A.env_ar(A.n_of(0.07 * heavy), 0.05, 0.02))
    return A.mix((metal_click(rng, 1.1 * heavy, 1.0, 0.5), 0, -6), (back, 0.005, -6),
                 (metal_click(rng, 0.9 * heavy, 1.0, 1.0, -3.0), 0.09 * heavy, 0), (metal_click(rng, 1.4, 0.9, 0.6), 0.1 * heavy, -8))


def pump(rng, back: bool) -> np.ndarray:
    """Shotgun fore-end: wood/steel slide with a hard stop (back: + the hull ejection flick)."""
    d = 0.09
    fr = friction(rng, d, 500, 4500, 35, A.env_ar(A.n_of(d), 0.06, 0.02))
    body = A.lp(A.noise(A.n_of(0.06), rng, "brown"), 700) * A.env_exp(A.n_of(0.06), 0.012)
    parts = [(fr, 0, -4), (metal_click(rng, 1.9, 0.75, 1.1, -1.0), d - 0.01, 0), (body / (np.max(np.abs(body)) + 1e-9), d - 0.01, -5)]
    if back:
        parts.append((metal_click(rng, 1.2, 1.0, 0.4), 0.01, -9))
    return A.mix(*parts)


def bolt(rng, step: str) -> np.ndarray:
    if step == "open":   # handle up: a dry click
        return A.mix((metal_click(rng, 1.4, 0.9, 0.6), 0, 0), (friction(rng, 0.03, 2000, 7000), 0.004, -12))
    if step == "back":   # bolt pulled: long steel slide ending in a stop
        return A.mix((friction(rng, 0.11, 1300, 6500, 45, A.env_ar(A.n_of(0.11), 0.07, 0.02)), 0, -3), (metal_click(rng, 1.6, 0.8, 0.8), 0.1, -2))
    if step == "fwd":
        return A.mix((friction(rng, 0.09, 1300, 6500, 50, A.env_ar(A.n_of(0.09), 0.02, 0.05)), 0, -4), (metal_click(rng, 1.3, 0.9, 0.7), 0.08, -3))
    if step == "close":  # handle down: firm lock
        return A.mix((metal_click(rng, 1.2, 1.0, 0.9, -2.0), 0, 0), (metal_click(rng, 2.0, 0.7, 0.5), 0.012, -8))
    raise KeyError(step)


def shell_in(rng, kind: str) -> np.ndarray:
    """One round pushed into a tube / an internal magazine / a cylinder chamber."""
    if kind == "shell":
        fr = friction(rng, 0.05, 700, 4000, 30, A.env_ar(A.n_of(0.05), 0.03, 0.01))
        return A.mix((fr, 0, -8), (metal_click(rng, 1.7, 0.8, 0.8, -3.0), 0.045, 0), (metal_click(rng, 2.2, 0.7, 0.4), 0.06, -10))
    if kind == "round":
        return A.mix((metal_click(rng, 0.8, 1.2, 0.5), 0, 0), (friction(rng, 0.03, 2500, 9000), 0.004, -12))
    if kind == "chamber":
        return A.mix((metal_click(rng, 0.7, 1.3, 0.35), 0, -2), (friction(rng, 0.02, 3000, 9000), 0.0, -14))
    raise KeyError(kind)


def cylinder(rng, opening: bool) -> np.ndarray:
    clk = metal_click(rng, 1.0, 1.2, 0.7)
    spin = A.grains(A.n_of(0.12), rng, 180, 0.002, (3000, 10000), A.env_ar(A.n_of(0.12), 0.01, 0.1))
    if opening:
        return A.mix((clk, 0, 0), (spin / (np.max(np.abs(spin)) + 1e-9), 0.02, -12))
    return A.mix((spin / (np.max(np.abs(spin)) + 1e-9), 0, -14), (metal_click(rng, 0.9, 1.1, 0.9, -2.0), 0.05, 0))


def ejector(rng) -> np.ndarray:
    """Revolver: the ejector rod pushes six empties out; they rattle on the ground."""
    parts = [(metal_click(rng, 1.2, 0.9, 0.5), 0, 0)]
    for i in range(6):
        parts.append((casing_hit(rng, "brass", 0.9), 0.18 + rng.uniform(0, 0.25), -6 - rng.uniform(0, 6)))
    return A.mix(*parts)


def casing_hit(rng, kind: str, size: float = 1.0) -> np.ndarray:
    """One bounce of a spent case on a hard floor: brass = bright bell-like tink, hull = dull plastic clack."""
    n = A.n_of(0.35)
    exc = np.zeros(n)
    exc[:3] = [1.0, -0.6, 0.2]
    if kind == "brass":
        f = rng.uniform(3600, 5200) / size
        ring = A.modal(exc, [(f, 0.05, 0), (f * 1.47, 0.035, -3), (f * 2.13, 0.03, -5), (f * 2.9, 0.02, -8), (f * 3.7, 0.015, -10)])
        tick = A.bp(A.noise(A.n_of(0.01), rng), 2000, 12000) * A.env_exp(A.n_of(0.01), 0.0015)
        return A.mix((ring / (np.max(np.abs(ring)) + 1e-9), 0, 0), (tick / (np.max(np.abs(tick)) + 1e-9), 0, -6))
    body = A.lp(A.noise(A.n_of(0.03), rng), 2500) * A.env_exp(A.n_of(0.03), 0.004)
    return A.mix((body, 0, 0), (A.modal(exc, [(rng.uniform(1300, 1700), 0.02, 0), (rng.uniform(3000, 3600), 0.015, -6)]) * 4.0, 0, -4))


def casing(rng, kind: str, surface: str) -> np.ndarray:
    if surface == "snow":
        # a case sinking in powder: a tiny muffled pff, maybe one dull tick
        n = A.n_of(0.12)
        x = A.lp(A.noise(n, rng, "pink"), 2200) * A.env_ar(n, 0.004, 0.08)
        x = A.mix((x, 0, 0), (A.lp(casing_hit(rng, kind), 1800), rng.uniform(0.0, 0.01), -14))
        return A.normalize(A.fade(x, 0.001, 0.03), peak=-1.0)
    parts = []
    t = 0.0
    g = 0.0
    for b in range(rng.integers(3, 5)):
        parts.append((casing_hit(rng, kind), t, g))
        t += rng.uniform(0.05, 0.12) * (0.75 ** b) + 0.02
        g -= rng.uniform(4, 7)
    return A.normalize(A.fade(A.mix(*parts), 0.0, 0.06), peak=-1.0)


def dry_fire(rng) -> np.ndarray:
    """Hammer / striker falling on nothing: a light steel click, a little spring noise."""
    return A.normalize(A.mix((metal_click(rng, 0.9, 1.2, 0.5, -10.0), 0, 0), (friction(rng, 0.015, 3000, 9000), 0.002, -16)), peak=-1.0)


def jam(rng) -> np.ndarray:
    """A failed feed: the slide stops short on a crooked round — a dull, wrong-sounding clack and a grind."""
    grind = friction(rng, 0.12, 400, 2500, 22, A.env_ar(A.n_of(0.12), 0.01, 0.1))
    return A.normalize(A.mix((metal_click(rng, 1.6, 0.6, 0.7, -2.0), 0, 0), (grind, 0.01, -6), (metal_click(rng, 2.2, 0.5, 0.4), 0.09, -6)), peak=-1.0)


# ------------------------------------------------------------------ bow
def bow_draw(rng) -> np.ndarray:
    """String pulled back: the limbs creak (stick-slip into wooden modes, rate rising with the draw) + a soft
    string / glove stretch."""
    d = rng.uniform(0.75, 0.95)
    n = A.n_of(d)
    rate = np.linspace(18, 55, n) * rng.uniform(0.9, 1.1)
    wood = [(rng.uniform(380, 460), 0.02, 0), (rng.uniform(900, 1100), 0.015, -3), (rng.uniform(1700, 2000), 0.01, -7)]
    cr = A.creak(n, rng, rate, wood, 0.3, A.env_ar(n, 0.2, 0.2, d - 0.45))
    st = A.bp(A.noise(n, rng, "pink"), 250, 1600) * A.env_ar(n, 0.35, 0.15, d - 0.5)
    st = st / (np.max(np.abs(st)) + 1e-9)
    nock = metal_click(rng, 3.0, 0.5, 0.3, -2.0)
    return A.normalize(A.fade(A.mix((nock, 0, -14), (cr, 0.05, 0), (st, 0.05, -10)), 0.002, 0.05), peak=-1.0)


def bow_release(rng) -> np.ndarray:
    """Twang (a damped low string partial set) + the arrow's whip leaving."""
    n = A.n_of(0.45)
    exc = np.zeros(n)
    exc[: A.n_of(0.001)] = 1.0
    f = rng.uniform(95, 120)
    tw = A.modal(exc, [(f, 0.12, 0), (f * 2.01, 0.08, -3), (f * 3.02, 0.05, -6), (f * 4.1, 0.03, -10)]) * 2.0
    whip = A.bp(A.noise(A.n_of(0.12), rng), 1500, 7000) * A.env_ar(A.n_of(0.12), 0.01, 0.1)
    thud = A.lp(A.noise(A.n_of(0.04), rng, "brown"), 400) * A.env_exp(A.n_of(0.04), 0.008)
    return A.normalize(A.mix((tw / (np.max(np.abs(tw)) + 1e-9), 0, 0), (whip, 0.005, -8), (thud / (np.max(np.abs(thud)) + 1e-9), 0, -8)), peak=-1.0)


# ------------------------------------------------------------------ bullet impacts
def impact(rng, surface: str) -> np.ndarray:
    n = A.n_of(0.5)
    snap = A.hp(A.noise(A.n_of(0.004), rng), 2000) * np.hanning(A.n_of(0.004))
    if surface == "snow":
        # a thump into packed snow and a spray of powder falling back
        th = A.lp(A.noise(A.n_of(0.1), rng, "brown"), 350) * A.env_exp(A.n_of(0.1), 0.02, 0.001)
        spray = A.grains(A.n_of(0.4), rng, np.linspace(900, 60, A.n_of(0.4)), 0.003, (1500, 7000), A.env_ar(A.n_of(0.4), 0.01, 0.35))
        x = A.mix((th / (np.max(np.abs(th)) + 1e-9), 0, 0), (spray / (np.max(np.abs(spray)) + 1e-9), 0.01, -10), (snap, 0, -14))
    elif surface == "wood":
        f = rng.integers(1, 26)
        f = f if f != 16 else 15
        x = A.mix((src("35-wooden-crackshitsdestructions", "impactwood%02d-mp3.m4a" % f)[: A.n_of(0.45)], 0, 0), (snap, 0, -6),
                  (A.grains(A.n_of(0.25), rng, 300, 0.002, (2000, 8000), A.env_ar(A.n_of(0.25), 0.005, 0.2)) * 3, 0.01, -10))
    elif surface == "metal":
        k = rng.integers(0, 5)
        m = src("kenney_impactsounds", f"impactMetal_{rng.choice(['light', 'medium'])}_{k:03d}.ogg")
        ring = metal_click(rng, rng.uniform(0.35, 0.6), 1.0, 2.5, -20.0)
        x = A.mix((m[: A.n_of(0.4)], 0, 0), (ring, 0, -6), (snap, 0, -4))
    elif surface == "concrete":
        deb = A.grains(A.n_of(0.35), rng, np.linspace(1500, 80, A.n_of(0.35)), 0.0025, (1200, 9000), A.env_ar(A.n_of(0.35), 0.002, 0.3))
        th = A.bp(A.noise(A.n_of(0.05), rng), 300, 3000) * A.env_exp(A.n_of(0.05), 0.008, 0.0002)
        x = A.mix((th / (np.max(np.abs(th)) + 1e-9), 0, 0), (snap, 0, -2), (deb / (np.max(np.abs(deb)) + 1e-9), 0.004, -7))
    elif surface == "flesh":
        k = rng.integers(1, 9)
        sq = src("8-wet-squish-slurp-impacts", "impactsplat%02d-mp3.m4a" % k)
        pu = src("kenney_impactsounds", f"impactPunch_{rng.choice(['medium', 'heavy'])}_{rng.integers(0, 5):03d}.ogg")
        x = A.mix((pu[: A.n_of(0.3)], 0, 0), (sq[: A.n_of(0.35)], 0.004, -4), (snap, 0, -12))
    else:
        raise KeyError(surface)
    x = A.pad_to(x, min(len(x), n))
    return A.normalize(A.fade(x, 0.0005, 0.05), peak=-1.0)


def ricochet(rng) -> np.ndarray:
    """A bullet skipping off a hard surface: a descending whine with a little flutter."""
    d = rng.uniform(0.35, 0.55)
    n = A.n_of(d)
    f0 = rng.uniform(2600, 3600)
    t = np.arange(n) / A.SR
    f = f0 * np.exp(-t * rng.uniform(1.0, 1.8))
    ph = 2 * np.pi * np.cumsum(f * (1 + 0.03 * np.sin(2 * np.pi * rng.uniform(25, 45) * t))) / A.SR
    w = np.sin(ph) * 0.6 + A.bp(A.noise(n, rng), 1500, 6000) * 0.4
    w *= A.env_ar(n, 0.01, d - 0.02, 0.0, 1.5)
    return A.normalize(A.fade(w, 0.002, 0.05), peak=-1.0)


def whiz(rng) -> np.ndarray:
    """A bullet passing close by (supersonic snap + short tearing hiss)."""
    n = A.n_of(0.18)
    crack = A.hp(A.nwave(n, 0.0003), 1500)
    hiss = A.bp(A.noise(n, rng), 2000, 9000) * A.env_ar(n, 0.02, 0.14)
    return A.normalize(A.mix((crack, 0, 0), (hiss, 0.002, -6)), peak=-1.0)


# ------------------------------------------------------------------ recipes
def build(out):
    rng = np.random.default_rng(1701)
    caps = [A.load(use("25-cc0-bang-firework-sfx", f)) for f in CAP_BANGS]
    __import__("sources").CURRENT.clear()   # the caps are attributed explicitly below
    closes = {}
    for kind in ("pistol", "revolver", "shotgun", "rifle"):
        closes[kind] = []
        for i in range(4):
            cap = CAP_BANGS[(i + len(kind)) % len(caps)]
            x = gunshot(kind, rng, caps[(i + len(kind)) % len(caps)])
            closes[kind].append(x)
            out(f"weapons/{kind}_close_{i + 1:02d}", x, "weapons_close", ["25-cc0-bang-firework-sfx/" + cap])
        for i in range(3):
            out(f"weapons/{kind}_far_{i + 1:02d}", distant(kind, rng, caps[i % len(caps)]), "weapons_far",
                ["25-cc0-bang-firework-sfx/" + CAP_BANGS[i % len(caps)]])
    # tails: light (handguns) and heavy (long guns) per environment, 3 variations
    for weight, kinds in (("light", ("pistol", "revolver")), ("heavy", ("shotgun", "rifle"))):
        for env in ("forest", "open", "city", "interior"):
            for i in range(3):
                k = kinds[i % 2]
                out(f"weapons/tail_{env}_{weight}_{i + 1:02d}", tail(closes[k][i], env, rng), "weapons_tail",
                    ["25-cc0-bang-firework-sfx/" + CAP_BANGS[(i + len(k)) % len(caps)]])
    # mechanics
    for i in range(3):
        out(f"weapons/mech_dry_{i + 1:02d}", dry_fire(rng), "weapons_mech", [])
        out(f"weapons/mech_jam_{i + 1:02d}", jam(rng), "weapons_mech", [])
        out(f"weapons/mech_pump_back_{i + 1:02d}", A.normalize(pump(rng, True), peak=-1.0), "weapons_mech", [])
        out(f"weapons/mech_pump_fwd_{i + 1:02d}", A.normalize(pump(rng, False), peak=-1.0), "weapons_mech", [])
        for step in ("open", "back", "fwd", "close"):
            out(f"weapons/mech_bolt_{step}_{i + 1:02d}", A.normalize(bolt(rng, step), peak=-1.0), "weapons_mech", [])
        out(f"weapons/mech_mag_out_{i + 1:02d}", A.normalize(mag_out(rng), peak=-1.0), "weapons_mech", [])
        out(f"weapons/mech_mag_in_{i + 1:02d}", A.normalize(mag_in(rng), peak=-1.0), "weapons_mech", [])
        out(f"weapons/mech_slide_{i + 1:02d}", A.normalize(slide_rack(rng), peak=-1.0), "weapons_mech", [])
        out(f"weapons/mech_cyl_open_{i + 1:02d}", A.normalize(cylinder(rng, True), peak=-1.0), "weapons_mech", [])
        out(f"weapons/mech_cyl_close_{i + 1:02d}", A.normalize(cylinder(rng, False), peak=-1.0), "weapons_mech", [])
        out(f"weapons/mech_eject_{i + 1:02d}", A.normalize(ejector(rng), peak=-1.0), "weapons_mech", [])
        out(f"weapons/mech_unjam_tap_{i + 1:02d}", A.normalize(A.mix((metal_click(rng, 1.8, 0.6, 0.6, -2.0), 0, 0)), peak=-1.0), "weapons_mech", [])
    for i in range(4):
        pk = pouch(rng)
        out(f"weapons/mech_pouch_{i + 1:02d}", pk, "weapons_mech")
        for kind in ("shell", "round", "chamber"):
            out(f"weapons/mech_{kind}_in_{i + 1:02d}", A.normalize(shell_in(rng, kind), peak=-1.0), "weapons_mech", [])
    # casings
    for kind in ("brass", "hull"):
        for surface in ("snow", "hard"):
            for i in range(4):
                out(f"weapons/casing_{kind}_{surface}_{i + 1:02d}", casing(rng, kind, surface), "weapons_casing", [])
    # bow
    for i in range(3):
        out(f"weapons/bow_draw_{i + 1:02d}", bow_draw(rng), "weapons_bow", [])
        out(f"weapons/bow_release_{i + 1:02d}", bow_release(rng), "weapons_bow", [])
    # impacts
    for surface in ("snow", "wood", "metal", "concrete", "flesh"):
        for i in range(4):
            out(f"weapons/impact_{surface}_{i + 1:02d}", impact(rng, surface), "weapons_impact")
    for i in range(3):
        out(f"weapons/ricochet_{i + 1:02d}", ricochet(rng), "weapons_impact", [])
        out(f"weapons/whiz_{i + 1:02d}", whiz(rng), "weapons_impact", [])
