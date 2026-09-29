"""Ambience (S1): stereo beds crossfaded by the AmbienceDirector and the sparse one-shots it places around the
listener. Everything here is designed (no recording), deterministic, and loops seamlessly.

Wind model: pink / brown noise through a band-pass whose centre and gain follow a slow random «gust» curve (gusts are
louder and brighter), plus narrow resonances (whistle / howl) that open above a gust threshold, plus the sound of what
the wind hits: pine needles (a broadband «shhh» 2–8 kHz), snow grains skittering over the crust (saltation: dense
tiny ticks 4–12 kHz), cables and building edges (whistles), flapping tarps. Left / right share the gust curve with a
small delay and use decorrelated noise, which gives width without phasiness in mono.
"""
from __future__ import annotations

import numpy as np

import audiolib as A
from recipes_creatures import breath, ice_crack
from recipes_player import kick
from recipes_weapons import metal_click, src
from recipes_world import swell

BED_S = 24.0


def gusts(n: int, rng, rate_hz: float, lo: float, hi: float) -> np.ndarray:
    """Smooth random gust curve in [lo, hi] (cubic-ish interpolation of random points)."""
    k = max(6, int(n / A.SR * rate_hz) + 4)
    pts = rng.uniform(0, 1, k) ** 1.5
    x = np.interp(np.linspace(0, k - 1, n), np.arange(k), pts)
    x = A.lp(x, max(rate_hz * 2, 0.05), 1)
    x = (x - x.min()) / (x.max() - x.min() + 1e-9)
    return lo + (hi - lo) * x


def wind(n: int, rng, g: np.ndarray, base=(180, 900), bright: float = 1.0, whistle: float = 0.0, whistle_f=(500, 1400),
         rumble: float = 0.5) -> np.ndarray:
    """One channel of wind following the gust curve g (0..1)."""
    body = A.noise(n, rng, "pink")
    lo, hi = base
    # two fixed bands crossfaded by the gust → the centre rises with the gust
    b1 = A.bp(body, lo, lo * 2.5, 2)
    b2 = A.bp(body, hi / 2.5, hi * bright, 2)
    y = b1 * (1 - g) * 0.8 + b2 * g * 1.2
    y *= 0.25 + 0.75 * g
    if rumble > 0:
        r = A.hp(A.lp(A.noise(n, rng, "brown"), 110), 30) * (0.3 + 0.7 * g)
        y += r / (np.std(r) + 1e-9) * np.std(y) * rumble
    if whistle > 0:
        # narrow-band noise tones (≈ 15–30 Hz wide) gliding smoothly: a complex low-passed noise heterodyned onto a
        # slowly wandering carrier — how wind sings on edges and cables; they open when the gust is strong
        wsum = np.zeros(n)
        for _ in range(3):
            k = max(4, int(n / A.SR * 0.4))
            fc = np.interp(np.linspace(0, k - 1, n), np.arange(k), rng.uniform(whistle_f[0], whistle_f[1], k))
            fc = A.lp(fc, 0.3, 1)
            bw = rng.uniform(8, 18)
            z = A.lp(rng.standard_normal(n), bw, 2) + 1j * A.lp(rng.standard_normal(n), bw, 2)
            wsum += np.real(z * np.exp(1j * 2 * np.pi * np.cumsum(fc) / A.SR))
        gate = np.clip((g - 0.45) / 0.4, 0, 1) ** 1.5
        y += wsum / (np.std(wsum) + 1e-9) * np.std(y) * whistle * gate
    return y


def stereo_wind(rng, dur: float, rate: float, lo: float, hi: float, **kw) -> np.ndarray:
    n = A.n_of(dur)
    g = gusts(n, rng, rate, lo, hi)
    d = A.n_of(rng.uniform(0.08, 0.2))
    gr = np.concatenate([g[d:], g[-d:]])
    L = wind(n, rng, g, **kw)
    R = wind(n, rng, gr, **kw)
    return np.stack([L, R], axis=1)


def needles(rng, dur: float, g_rate: float = 0.12, level: float = 1.0) -> np.ndarray:
    """Wind in conifers: broadband hiss 2–8 kHz following gusts, stereo."""
    n = A.n_of(dur)
    g = gusts(n, rng, g_rate, 0.15, 1.0)
    ch = []
    for c in range(2):
        h = A.bp(A.noise(n, rng, "pink"), 1800, 8000, 2)
        h = A.shelf(h, 5000, -4.0)
        ch.append(h * (g if c == 0 else np.roll(g, A.n_of(0.3))) ** 1.3)
    return np.stack(ch, axis=1) * level


def saltation(rng, dur: float, g=None, level: float = 1.0) -> np.ndarray:
    """Snow grains skittering over the crust (tiny ticks, dense, following gusts)."""
    n = A.n_of(dur)
    if g is None:
        g = gusts(n, rng, 0.15, 0.1, 1.0)
    ch = []
    for c in range(2):
        gg = g if c == 0 else np.roll(g, A.n_of(0.25))
        t = A.grains(n, rng, 1500 + 6000 * gg ** 2, 0.0006, (3500, 9000), None, 0.25)
        t = A.lp(t, 9000, 2)
        ch.append(t / (np.std(t) + 1e-9) * gg ** 1.5)
    return np.stack(ch, axis=1) * level * 0.12


def rms_mix(*parts) -> np.ndarray:
    """Mixes (signal, dB) layers after normalising each to unit RMS: the dB values are the layers' real balance."""
    out = None
    for sig, g in parts:
        y = sig / (np.sqrt(np.mean(sig ** 2)) + 1e-12) * A.db(g)
        out = y if out is None else out + y
    return out


def bed(x: np.ndarray, rng) -> np.ndarray:
    x = A.lp(A.hp(x, 28, 2), 12000, 2)
    return A.make_loop(x, 3.0)


def place(n: int, events, rng, stereo: bool = True) -> np.ndarray:
    """Places mono events [(signal, t_s, gain_db, pan)] into a stereo buffer of n samples."""
    out = np.zeros((n, 2))
    for sig, t, g, p in events:
        i = A.n_of(t)
        s = A.pan(sig * A.db(g), p)
        e = min(n, i + len(s))
        if i < n:
            out[i:e] += s[: e - i]
    return out


def far(x: np.ndarray, rng, env: str = "forest", lp_hz: float = 2500, wet_db: float = -4) -> np.ndarray:
    """Pushes a mono sound far away: highs gone, the direct part weak, the environment's reverb strong."""
    d = A.lp(x, lp_hz, 2)
    w = A.reverb_tail(d, A.make_ir(env, rng), 0.0)
    w = w / (np.max(np.abs(w)) + 1e-9) * (np.max(np.abs(d)) + 1e-9)
    return A.mix((d, 0.0, -6), (w, 0.0, wet_db))


# ------------------------------------------------------------------ one-shot designs
def crow(rng, caws: int) -> np.ndarray:
    parts = []
    t = 0.0
    for k in range(caws):
        d = rng.uniform(0.22, 0.32)
        n = A.n_of(d)
        f0 = rng.uniform(420, 560) * np.linspace(1.0, rng.uniform(0.78, 0.9), n)
        ph = np.cumsum(f0) / A.SR
        pulse = np.zeros(n)
        for h in range(1, 14):
            pulse += np.sin(2 * np.pi * h * ph) / h ** 0.7
        v = pulse * (1 + 0.8 * A.bp(A.noise(n, rng), 200, 3000))   # harsh, noisy voice
        v = A.peaking(A.peaking(v, rng.uniform(1100, 1400), 10, 2.5), rng.uniform(2200, 2700), 6, 3)
        v = A.bp(v, 500, 4500, 2) * A.env_points(n, [(0, 0), (0.03, 1), (d * 0.6, 0.8), (d, 0)])
        parts.append((v / (np.max(np.abs(v)) + 1e-9), t, -rng.uniform(0, 3)))
        t += d + rng.uniform(0.18, 0.35)
    return A.mix(*parts)


def woodpecker(rng) -> np.ndarray:
    d = rng.uniform(0.9, 1.4)
    rate = rng.uniform(14, 19)
    parts = []
    k = 0
    while k / rate < d:
        exc = A.bp(A.noise(A.n_of(0.003), rng), 800, 6000) * np.hanning(A.n_of(0.003))
        m = A.n_of(0.06)
        knock = A.modal(A.pad_to(exc, m), [(rng.uniform(900, 1100), 0.008, 0), (rng.uniform(1800, 2200), 0.005, -4)]) + A.pad_to(exc, m) * 0.5
        parts.append((knock / (np.max(np.abs(knock)) + 1e-9), k / rate, -k * 0.6))
        k += 1
    return A.mix(*parts)


def owl(rng) -> np.ndarray:
    """Tawny / great horned owl: soft near-sinusoidal hoots ~ 380 Hz, breathy, the last one longest."""
    pattern = [(0.0, 0.35), (0.55, 0.18), (0.8, 0.18), (1.05, 0.55)]
    f = rng.uniform(340, 420)
    parts = []
    for t, d in pattern:
        n = A.n_of(d)
        fc = f * np.linspace(1.02, 0.97, n)
        v = np.sin(2 * np.pi * np.cumsum(fc) / A.SR) + 0.12 * np.sin(4 * np.pi * np.cumsum(fc) / A.SR)
        v += A.bp(A.noise(n, rng), f * 0.8, f * 3) * 0.3
        v *= A.env_points(n, [(0, 0), (d * 0.3, 1), (d * 0.7, 0.9), (d, 0)])
        parts.append((v, t, 0))
    return A.mix(*parts)


def ice_pew(rng) -> np.ndarray:
    """Lake ice «singing»: a dispersive descending chirp (high frequencies arrive first) with echoes of itself."""
    d = rng.uniform(0.25, 0.45)
    n = A.n_of(d)
    t = np.arange(n) / A.SR
    f = rng.uniform(1800, 3200) * np.exp(-t / (d / rng.uniform(2.5, 3.5))) + 120
    ch = np.sin(2 * np.pi * np.cumsum(f) / A.SR) * A.env_points(n, [(0, 0), (0.005, 1), (d, 0)])
    ch += A.bp(A.noise(n, rng), 500, 3000) * A.env_exp(n, 0.02) * 0.3
    parts = [(ch, 0, 0)]
    for k in range(1, 4):
        parts.append((A.lp(ch, 3000 / k), k * rng.uniform(0.15, 0.3), -6 * k))
    return A.mix(*parts)


def ice_boom(rng) -> np.ndarray:
    n = A.n_of(2.5)
    b = A.hp(A.lp(A.noise(n, rng, "brown"), 160), 25) * A.env_exp(n, 0.35, 0.02)
    return A.mix((b / (np.max(np.abs(b)) + 1e-9), 0, 0), (ice_crack(rng, 0.6), 0.0, -18), (ice_pew(rng), 0.05, -14))


def tarp(rng) -> np.ndarray:
    d = rng.uniform(1.2, 2.4)
    n = A.n_of(d)
    fl = rng.uniform(7, 16) * (1 + 0.3 * np.sin(np.linspace(0, np.pi * 2, n)))
    ph = np.cumsum(fl) / A.SR
    am = np.maximum(np.sin(2 * np.pi * ph), 0) ** 6
    x = A.bp(A.noise(n, rng), 300, 5000) * am * A.env_points(n, [(0, 0), (d * 0.3, 1), (d * 0.7, 0.8), (d, 0)])
    return x / (np.max(np.abs(x)) + 1e-9)


def halyard(rng) -> np.ndarray:
    parts = []
    t = 0.0
    for _ in range(rng.integers(2, 5)):
        parts.append((metal_click(rng, rng.uniform(1.4, 2.0), 0.8, 4.0, -20), t, -rng.uniform(0, 6)))
        t += rng.uniform(0.25, 0.9)
    return A.mix(*parts)


def rattle_window(rng) -> np.ndarray:
    n = A.n_of(0.7)
    r = A.creak(n, rng, rng.uniform(25, 40), [(rng.uniform(1500, 2200), 0.01, 0), (rng.uniform(3500, 4500), 0.006, -4)], 0.4,
                A.env_points(n, [(0, 0), (0.1, 1), (0.5, 0.6), (0.7, 0)]))
    return r


def house_creak(rng) -> np.ndarray:
    d = rng.uniform(0.6, 1.3)
    n = A.n_of(d)
    return A.creak(n, rng, np.interp(np.linspace(0, 1, n), [0, 0.5, 1], rng.uniform(15, 60, 3)),
                   [(rng.uniform(180, 260), 0.03, 0), (rng.uniform(500, 700), 0.02, -3), (rng.uniform(1200, 1500), 0.012, -8)], 0.35,
                   A.env_points(n, [(0, 0), (d * 0.2, 1), (d * 0.8, 0.8), (d, 0)]))


def snow_dump(rng) -> np.ndarray:
    """Snow sliding off a loaded branch: a soft whoosh and a powdery flump."""
    n = A.n_of(1.0)
    sl = A.bp(A.noise(n, rng, "pink"), 500, 5000) * A.env_points(n, [(0, 0), (0.25, 0.6), (0.45, 1), (0.6, 0)])
    fl = A.lp(A.noise(A.n_of(0.4), rng, "brown"), 300) * A.env_exp(A.n_of(0.4), 0.06, 0.01)
    gr = A.grains(A.n_of(0.5), rng, np.linspace(1200, 30, A.n_of(0.5)), 0.003, (800, 6000), A.env_ar(A.n_of(0.5), 0.01, 0.45))
    return A.mix((sl / (np.max(np.abs(sl)) + 1e-9), 0, -6), (fl / (np.max(np.abs(fl)) + 1e-9), 0.45, 0), (gr / (np.max(np.abs(gr)) + 1e-9), 0.46, -6))


def rockfall(rng) -> np.ndarray:
    n = A.n_of(4.0)
    rum = A.hp(A.lp(A.noise(n, rng, "brown"), 200), 25) * A.env_points(n, [(0, 0), (0.6, 1), (2.5, 0.7), (4.0, 0)])
    deb = A.grains(n, rng, 40 * A.env_points(n, [(0, 0.2), (1.0, 1), (3.5, 0.2), (4, 0)]) + 1, 0.01, (200, 2500), None, 1.0)
    return A.mix((rum / (np.max(np.abs(rum)) + 1e-9), 0, 0), (deb / (np.max(np.abs(deb)) + 1e-9), 0, -8))


# ------------------------------------------------------------------ recipes
def build(out):
    rng = np.random.default_rng(5501)
    n = A.n_of(BED_S + 3.0)
    D = BED_S + 3.0
    # --- beds
    fd = rms_mix((stereo_wind(rng, D, 0.35, 0.1, 0.7, base=(150, 700), rumble=0.6), 0), (needles(rng, D, 0.3), -15))
    out("ambience/forest_day", bed(fd, rng), "amb_bed", loop=True)
    creaks = [(house_creak(rng) * 0.5, rng.uniform(2, D - 3), -12, rng.uniform(-0.8, 0.8)) for _ in range(3)]
    fn = rms_mix((stereo_wind(rng, D, 0.25, 0.05, 0.5, base=(120, 500), rumble=0.8), 0), (needles(rng, D, 0.25), -21)) + place(n, creaks, rng)
    out("ambience/forest_night", bed(A.lp(fn, 6000), rng), "amb_bed", loop=True, gain_db=-2.0)
    op = rms_mix((stereo_wind(rng, D, 0.4, 0.15, 0.85, base=(200, 1100), rumble=0.5, whistle=0.15), 0), (saltation(rng, D), -19))
    out("ambience/open", bed(op, rng), "amb_bed", loop=True)
    ps = rms_mix((stereo_wind(rng, D, 0.5, 0.25, 1.0, base=(160, 1400), bright=1.3, rumble=0.9, whistle=0.9, whistle_f=(420, 1300)), 0), (saltation(rng, D), -16))
    out("ambience/pass", bed(ps, rng), "amb_bed", loop=True, gain_db=1.0)
    ice_ev = [(ice_pew(rng), rng.uniform(1, D - 3), rng.uniform(-14, -6), rng.uniform(-0.9, 0.9)) for _ in range(5)] + \
             [(ice_boom(rng), rng.uniform(1, D - 4), -8, rng.uniform(-0.5, 0.5)) for _ in range(2)]
    ic = rms_mix((stereo_wind(rng, D, 0.3, 0.05, 0.55, base=(150, 800), rumble=0.5), 0)) + place(n, ice_ev, rng)
    out("ambience/ice", bed(ic, rng), "amb_bed", loop=True)
    tarps = [(tarp(rng), rng.uniform(1, D - 3), rng.uniform(-22, -14), rng.uniform(-1, 1)) for _ in range(3)]
    cd = rms_mix((stereo_wind(rng, D, 0.4, 0.1, 0.8, base=(140, 900), rumble=0.9, whistle=0.55, whistle_f=(700, 2200)), 0)) + place(n, tarps, rng)
    cd += rms_mix((np.stack([A.hp(A.lp(A.noise(n, rng, "brown"), 90), 30)] * 2, axis=1), -10))   # the empty city's low air
    out("ambience/city_day", bed(cd, rng), "amb_bed", loop=True)
    cn = stereo_wind(rng, D, 0.3, 0.05, 0.6, base=(120, 700), rumble=1.0, whistle=0.4, whistle_f=(600, 1800))
    out("ambience/city_night", bed(A.lp(cn, 7000), rng), "amb_bed", loop=True, gain_db=-2.0)
    hal = [(halyard(rng), rng.uniform(1, D - 3), rng.uniform(-18, -10), rng.uniform(-1, 1)) for _ in range(5)]
    pt = rms_mix((stereo_wind(rng, D, 0.35, 0.1, 0.8, base=(150, 1000), rumble=0.7, whistle=0.35, whistle_f=(900, 2400)), 0)) + place(n, hal, rng)
    out("ambience/port", bed(pt, rng), "amb_bed", loop=True)
    # interior: room tone, the storm muffled by the walls, a creak
    rt = np.stack([A.hp(A.lp(A.noise(n, rng, "brown"), 140), 35) for _ in range(2)], axis=1) * 0.3
    outside = A.lp(stereo_wind(rng, D, 0.3, 0.1, 0.8, base=(120, 600), rumble=0.8), 380, 2)
    inn = rms_mix((rt, -4), (outside, 0)) + place(n, [(house_creak(rng), rng.uniform(3, D - 3), -16, rng.uniform(-0.6, 0.6)) for _ in range(2)], rng)
    out("ambience/interior", bed(inn, rng), "amb_bed", loop=True, gain_db=-4.0)
    # layers: generic wind (scaled by WorldState wind) and the blizzard
    wl = stereo_wind(rng, D, 0.45, 0.2, 1.0, base=(180, 1300), rumble=0.7, whistle=0.35, whistle_f=(500, 1500))
    out("ambience/wind_layer", bed(wl, rng), "amb_layer", loop=True)
    bz = rms_mix((stereo_wind(rng, D, 0.6, 0.45, 1.0, base=(150, 1800), bright=1.4, rumble=1.2, whistle=0.8, whistle_f=(380, 1200)), 0), (saltation(rng, D), -12))
    out("ambience/blizzard", bed(bz, rng), "amb_layer", loop=True, gain_db=3.0)
    # --- sparse one-shots (mono; the director places them in 3D around the listener)
    for i in range(5):
        out(f"ambience/crow_{i + 1:02d}", far(crow(rng, int(rng.integers(1, 4))), rng, "forest", 4500, -8), "amb_oneshot", gain_db=-2.0)
    for i in range(3):
        out(f"ambience/woodpecker_{i + 1:02d}", far(woodpecker(rng), rng, "forest", 5000, -8), "amb_oneshot", gain_db=-4.0)
        out(f"ambience/owl_{i + 1:02d}", far(owl(rng), rng, "forest", 2000, -6), "amb_oneshot", gain_db=-4.0)
        out(f"ambience/snow_dump_{i + 1:02d}", snow_dump(rng), "amb_oneshot", gain_db=-4.0)
        out(f"ambience/branch_snap_{i + 1:02d}", far(src("35-wooden-crackshitsdestructions", f"crack{4 + i:02d}-mp3.m4a"), rng, "forest", 3500, -6), "amb_oneshot", gain_db=-6.0)
        out(f"ambience/ice_pew_{i + 1:02d}", far(ice_pew(rng), rng, "open", 6000, -8), "amb_oneshot", gain_db=-4.0)
        out(f"ambience/ice_boom_{i + 1:02d}", ice_boom(rng), "amb_oneshot", gain_db=-2.0)
        out(f"ambience/tarp_{i + 1:02d}", tarp(rng), "amb_oneshot", gain_db=-6.0)
        out(f"ambience/halyard_{i + 1:02d}", far(halyard(rng), rng, "open", 5000, -10), "amb_oneshot", gain_db=-6.0)
        out(f"ambience/window_rattle_{i + 1:02d}", rattle_window(rng), "amb_oneshot", gain_db=-10.0)
        out(f"ambience/house_creak_{i + 1:02d}", house_creak(rng), "amb_oneshot", gain_db=-8.0)
    for i in range(4):
        b = src("80-cc0-creature-sfx", f"barking-0{1 + i % 2}.m4a", 150)
        seq = A.mix(*[(A.pitch(b, rng.uniform(-3, 1)), k * rng.uniform(0.45, 0.7), -k * 1.5) for k in range(int(rng.integers(2, 5)))])
        out(f"ambience/dog_far_{i + 1:02d}", far(seq, rng, "city", 2200, -3), "amb_oneshot", gain_db=-4.0)
    for i, (pack, f) in enumerate([("15-vocal-male-strainhurtpainjump-sounds", "slightscream-10.m4a"), ("15-vocal-male-strainhurtpainjump-sounds", "slightscream-15.m4a"),
                                   ("male-gruntyelling-sounds", "3yell4.m4a")]):
        v = A.pitch(src(pack, f, 150), rng.uniform(-2, 1))
        out(f"ambience/scream_far_{i + 1:02d}", far(v, rng, "city", 1800, -2), "amb_oneshot", gain_db=-6.0)
    for i in range(3):
        a = src("kenney_impactsounds", f"impactPlank_medium_{i:03d}.ogg")
        out(f"ambience/shutter_bang_{i + 1:02d}", far(A.mix((a, 0, 0), (a, rng.uniform(0.12, 0.2), -8)), rng, "city", 4000, -4), "amb_oneshot", gain_db=-4.0)
        g = src("75-cc0-breaking-falling-hit-sfx", f"bfh1-glass-breaking-0{4 + i}.m4a", 150)
        out(f"ambience/glass_far_{i + 1:02d}", far(g, rng, "city", 3500, -3), "amb_oneshot", gain_db=-6.0)
    for i in range(2):
        out(f"ambience/rockfall_{i + 1:02d}", far(rockfall(rng), rng, "open", 1500, -6), "amb_oneshot", gain_db=-2.0)
