"""World objects (S1): chopping and the falling tree, campfire / stove / flare / generator loops, doors, loot
containers, thrown cans, placement, crafting, glass, ice, car alarms.

Loops are rendered long (8–12 s) and made seamless with an equal-power crossfade of their end into their head.
Fire is designed from its physics: a low turbulent roar (brown noise with a slow irregular swell), a gas hiss, and
crackles — a Poisson cloud of short pops whose sizes follow a log-normal law, a few big resin snaps. Doors,
chopping, glass and metal come from Kenney / qubodup / rubberduck CC0 recordings, layered and re-pitched.
"""
from __future__ import annotations

import numpy as np

import audiolib as A
from recipes_creatures import ice_crack, snow_body_fall, snow_step, whoosh
from recipes_player import kick
from recipes_weapons import friction, metal_click, src


def swell(n: int, rng, rate_hz: float = 0.3, depth: float = 0.5) -> np.ndarray:
    """Slow irregular amplitude swell (low-passed noise), mean 1."""
    k = max(8, int(n / A.SR * rate_hz * 8))
    pts = rng.uniform(1 - depth, 1 + depth, k)
    return np.maximum(np.interp(np.linspace(0, k - 1, n), np.arange(k), pts), 0.05)


def fire(rng, dur: float, size: float = 1.0, muffle: float = 0.0) -> np.ndarray:
    n = A.n_of(dur)
    roar = A.hp(A.lp(A.noise(n, rng, "brown"), 380 * size), 70, 2) * swell(n, rng, 0.4, 0.45)
    hiss = A.bp(A.noise(n, rng, "pink"), 1800, 7000) * swell(n, rng, 0.8, 0.5) * 0.25
    small = A.grains(n, rng, 35 * size, 0.0015, (1200, 9000), None, 0.9)
    pops = A.grains(n, rng, 2.2 * size, 0.004, (500, 6000), None, 1.1)
    # a few resin snaps: a sharp transient with a short woody ring
    snaps = np.zeros(n)
    for _ in range(int(dur * 0.6 * size)):
        i = rng.integers(0, n - A.n_of(0.1))
        exc = np.zeros(A.n_of(0.1))
        exc[:3] = [1, -0.5, 0.2]
        snaps[i:i + len(exc)] += A.modal(exc, [(rng.uniform(900, 1500), 0.012, 0), (rng.uniform(2500, 3500), 0.008, -4)]) * rng.uniform(0.5, 1.0)
    x = (roar / (np.std(roar) + 1e-9)) * 0.35 + hiss / (np.std(hiss) + 1e-9) * 0.05 + small / (np.std(small) + 1e-9) * 0.05 \
        + pops / (np.max(np.abs(pops)) + 1e-9) * 0.5 + snaps / (np.max(np.abs(snaps)) + 1e-9) * 0.55
    if muffle > 0:
        x = A.lp(x, 2500 / (1 + muffle * 3), 2)
    return A.hp(x, 45, 2)


def build(out):
    rng = np.random.default_rng(4409)
    # --- chopping: the axe bites (Kenney chop + qubodup wood hits), a thump, snow shaken off the branches
    for i in range(6):
        ch = src("kenney_rpgaudio", "chop.ogg")
        w = src("35-wooden-crackshitsdestructions", f"impactwood{2 + i * 3:02d}-mp3.m4a")
        sn = A.grains(A.n_of(0.9), rng, np.linspace(300, 10, A.n_of(0.9)), 0.004, (800, 5000), A.env_ar(A.n_of(0.9), 0.05, 0.8))
        x = A.mix((A.pitch(ch, rng.uniform(-2, 1)), 0, 0), (w[: A.n_of(0.4)], 0.0, -3), (kick(rng, 160, 0.03), 0, -6),
                  (sn / (np.max(np.abs(sn)) + 1e-9), 0.12, -20))
        out(f"world/chop_{i + 1:02d}", x, "world")
    # --- tree fall: groaning fibres, cracks, the sweep of the crown, the impact and the snow burst (≈ 4.5 s)
    for i in range(3):
        n = A.n_of(1.6)
        groan = A.creak(n, rng, np.linspace(14, 45, n), [(rng.uniform(120, 160), 0.05, 0), (rng.uniform(320, 400), 0.04, -3),
                                                         (rng.uniform(700, 850), 0.03, -6)], 0.35, A.env_ar(n, 0.4, 0.3, 0.9))
        cracks = [src("35-wooden-crackshitsdestructions", f"crack{k:02d}-mp3.m4a") for k in rng.choice(np.arange(1, 11), 3, replace=False)]
        sweep = whoosh(rng, 1.3, 150, 1500, 0.85)
        boom = A.lp(A.noise(A.n_of(1.2), rng, "brown"), 120) * A.env_exp(A.n_of(1.2), 0.18, 0.005)
        burst = A.grains(A.n_of(1.6), rng, np.linspace(2500, 30, A.n_of(1.6)), 0.004, (600, 6000), A.env_ar(A.n_of(1.6), 0.01, 1.5))
        branches = src("35-wooden-crackshitsdestructions", f"crack{10 - i:02d}-mp3.m4a")
        t_imp = 2.9 + rng.uniform(-0.1, 0.2)
        x = A.mix((groan, 0, -4), (cracks[0], 0.9, -2), (cracks[1], 1.35, 0), (cracks[2], 1.6, -4), (sweep, t_imp - 1.2, -6),
                  (boom / (np.max(np.abs(boom)) + 1e-9), t_imp, 0), (burst / (np.max(np.abs(burst)) + 1e-9), t_imp + 0.02, -6),
                  (branches, t_imp + 0.05, -6), (snow_body_fall(rng, 2.5), t_imp, -3))
        out(f"world/tree_fall_{i + 1:02d}", x, "world", gain_db=2.0)
    # --- campfire loop (3D, 10 s seamless), stove loop (muffled in iron, thermal ticks)
    out("world/fire_loop_01", A.make_loop(fire(rng, 11.5, 1.0), 1.5), "world_loop", loop=True)
    out("world/fire_loop_02", A.make_loop(fire(rng, 11.5, 1.3), 1.5), "world_loop", loop=True)
    st = fire(rng, 11.5, 0.7, 1.0)
    ticks = np.zeros(len(st))
    for _ in range(6):
        c = metal_click(rng, 1.6, 0.8, 0.6, -10)
        j = rng.integers(0, len(st) - len(c))
        ticks[j:j + len(c)] += c * rng.uniform(0.2, 0.5)
    out("world/stove_loop_01", A.make_loop(A.lp(st, 1400, 2) + ticks * 0.15, 1.5), "world_loop", loop=True, gain_db=-2.0)
    # --- adding wood: a log knocked onto the embers, a flare-up of crackles
    for i in range(4):
        w = src("35-wooden-crackshitsdestructions", f"impactwood{12 + i:02d}-mp3.m4a")
        fl = fire(rng, 1.4, 2.5) * A.env_ar(A.n_of(1.4), 0.05, 1.2)
        out(f"world/fire_add_{i + 1:02d}", A.mix((w[: A.n_of(0.4)], 0, 0), (fl, 0.05, -4)), "world", gain_db=-2.0)
    # --- fire out: steam hiss + sizzle dying
    for i in range(2):
        n = A.n_of(2.2)
        hiss = A.bp(A.noise(n, rng), 1500, 9000) * A.env_points(n, [(0, 0), (0.05, 1), (0.6, 0.5), (2.2, 0)])
        siz = A.grains(n, rng, np.linspace(900, 20, n), 0.002, (2000, 9000), A.env_ar(n, 0.02, 2.0))
        out(f"world/fire_out_{i + 1:02d}", A.mix((hiss, 0, -6), (siz / (np.max(np.abs(siz)) + 1e-9), 0, -4), (snow_step(rng, 1.0), 0, -8)), "world")
    # --- flare: strike pop, fizzing burn (6 s, fading), little spits
    for i in range(2):
        n = A.n_of(6.5)
        fizz = A.bp(A.noise(n, rng), 1200, 8000) * swell(n, rng, 3.0, 0.35) * A.env_points(n, [(0, 0), (0.08, 1), (4.5, 0.8), (6.5, 0)])
        spit = A.grains(n, rng, 30, 0.002, (1500, 7000), None, 1.0)
        pop = kick(rng, 900, 0.01)
        out(f"world/flare_burn_{i + 1:02d}", A.mix((pop, 0, -2), (fizz / (np.max(np.abs(fizz)) + 1e-9), 0.02, -6), (spit / (np.max(np.abs(spit)) + 1e-9), 0.1, -14)), "world", gain_db=-4.0)
    # --- generator (inhabited spots): a small single-cylinder engine at ≈ 1800 rpm (30 Hz firing), exhaust + rattle
    n = A.n_of(10.5)
    t = np.arange(n) / A.SR
    f = 29.5 * (1 + 0.01 * np.sin(2 * np.pi * 0.23 * t))
    ph = np.cumsum(f) / A.SR
    pulses = np.maximum(np.sin(2 * np.pi * ph), 0) ** 8
    eng = A.lp(pulses * (1 + 0.3 * A.lp(rng.standard_normal(n), 30) * 5), 900, 2) + A.bp(A.noise(n, rng), 800, 4000) * pulses * 0.15
    rattle = A.bp(A.noise(n, rng), 2000, 6000) * (np.sin(2 * np.pi * ph * 2) > 0.9) * 0.08
    out("world/generator_loop_01", A.make_loop(A.hp(eng + rattle, 35), 1.0), "world_loop", loop=True, gain_db=-2.0)
    # --- doors (M6a): open (hinge creak + latch), close (slam + latch), locked (handle rattles, nothing gives)
    for i in range(6):
        k = [1, 3, 5, 6, 7, 8][i]
        x = src("door-open-door-close-set", f"qubodup-door-open{k:02d}.m4a", 60)
        if i % 2 == 0:
            x = A.mix((x, 0, 0), (src("kenney_rpgaudio", f"creak{1 + i // 2}.ogg", 100), 0.05, -8))
        out(f"world/door_open_{i + 1:02d}", x, "world", gain_db=-3.0)
    for i in range(6):
        k = [1, 3, 6, 7, 9, 10][i]
        out(f"world/door_close_{i + 1:02d}", src("door-open-door-close-set", f"qubodup-door-close{k:02d}.m4a", 50), "world", gain_db=-2.0)
    for i in range(4):
        rat = src("kenney_rpgaudio", "metalLatch.ogg", 200)
        x = A.mix((rat, 0, 0), (rat, rng.uniform(0.12, 0.18), -3), (rat, rng.uniform(0.3, 0.38), -6),
                  (kick(rng, 350, 0.02), 0.01, -10), (kick(rng, 350, 0.02), 0.15, -12))
        out(f"world/door_locked_{i + 1:02d}", A.pitch(x, rng.uniform(-3, 0)), "world", gain_db=-4.0)
    for i in range(3):
        cr = src("35-wooden-crackshitsdestructions", f"crack{3 + i * 2:02d}-mp3.m4a")
        out(f"world/door_break_{i + 1:02d}", A.mix((cr, 0, 0), (src("kenney_impactsounds", f"impactPlank_medium_{i:03d}.ogg"), 0, -2), (kick(rng, 200, 0.04), 0, -4)), "world")
    # --- loot containers: wooden crate / chest, metal cabinet / locker, and the rummage
    for i in range(3):
        x = A.mix((src("kenney_rpgaudio", f"creak{1 + i}.ogg", 100)[: A.n_of(0.5)], 0, -4),
                  (src("kenney_impactsounds", f"impactPlank_medium_{(i + 2) % 5:03d}.ogg"), 0.3, 0))
        out(f"world/container_wood_{i + 1:02d}", x, "world", gain_db=-3.0)
        m = src("100-cc0-metal-and-wood-sfx", ["metal-open-01.m4a", "lock-open-01.m4a", "metal-close-01.m4a"][i], 80)
        out(f"world/container_metal_{i + 1:02d}", A.mix((src("kenney_rpgaudio", "metalLatch.ogg", 200), 0, -4), (m, 0.05, 0)), "world", gain_db=-3.0)
        parts = []
        t0 = 0.0
        for k in range(4):
            parts.append((src("kenney_rpgaudio", ["cloth1.ogg", "handleSmallLeather.ogg", "cloth3.ogg", "beltHandle2.ogg", "bookFlip2.ogg"][(i + k) % 5], 150)[: A.n_of(0.35)], t0, rng.uniform(-8, -2)))
            t0 += rng.uniform(0.18, 0.3)
        out(f"world/rummage_{i + 1:02d}", A.mix(*parts), "foley", gain_db=-3.0)
    # --- thrown can: tin clatter (hard) / a dull tock and crunch in snow
    for i in range(3):
        tin = src("kenney_impactsounds", "impactTin_medium_%03d.ogg" % i)
        out(f"world/can_hard_{i + 1:02d}", A.mix((tin, 0, 0), (tin, rng.uniform(0.15, 0.22), -8), (tin, rng.uniform(0.3, 0.38), -14)), "world")
        out(f"world/can_snow_{i + 1:02d}", A.mix((A.lp(tin, 2500), 0, -6), (snow_step(rng, 0.6), 0, 0)), "world", gain_db=-2.0)
    # --- placing a structure / item in the snow; crafting (two hammer taps)
    for i in range(3):
        out(f"world/place_{i + 1:02d}", A.mix((src("kenney_impactsounds", f"impactWood_medium_{i:03d}.ogg"), 0, -2),
                                              (src("35-wooden-crackshitsdestructions", f"impactwood{20 + i:02d}-mp3.m4a")[: A.n_of(0.3)], 0, -3),
                                              (snow_step(rng, 1.2), 0.0, -4)), "world", gain_db=-3.0)
        h1 = src("100-cc0-metal-and-wood-sfx", f"hammer-0{1 + i}.m4a", 80)
        h2 = src("100-cc0-metal-and-wood-sfx", f"hammer-0{1 + (i + 1) % 4}.m4a", 80)
        out(f"world/craft_{i + 1:02d}", A.mix((h1[: A.n_of(0.25)], 0, 0), (h2[: A.n_of(0.3)], 0.17 + rng.uniform(0, 0.03), -2)), "foley", gain_db=-3.0)
    # --- glass (windows, bottles)
    for i in range(3):
        g = src("75-cc0-breaking-falling-hit-sfx", f"bfh1-glass-breaking-0{1 + i}.m4a", 100)
        out(f"world/glass_break_{i + 1:02d}", A.mix((g, 0, 0), (src("kenney_impactsounds", f"impactGlass_heavy_{i:03d}.ogg"), 0, -4)), "world")
    # --- thin ice under foot: creak then crack (GDD ice_crack), and a breaking through
    for i in range(4):
        n = A.n_of(0.6)
        cr = A.creak(n, rng, np.linspace(25, 70, n), [(rng.uniform(600, 900), 0.02, 0), (rng.uniform(1800, 2400), 0.012, -4)], 0.4, A.env_ar(n, 0.2, 0.3, 0.1))
        out(f"world/ice_crack_{i + 1:02d}", A.mix((cr, 0, -6), (ice_crack(rng, 1.4), 0.45, 0), (ice_crack(rng, 0.8), 0.52 + rng.uniform(0, 0.05), -6)), "world")
    for i in range(2):
        sp = src("40-cc0-water-splash-slime-sfx", f"splash-{3 + i * 4:02d}.m4a")
        out(f"world/ice_break_{i + 1:02d}", A.mix((ice_crack(rng, 2.0), 0, 0), (ice_crack(rng, 1.5), 0.08, -2), (sp, 0.15, -2), (kick(rng, 180, 0.05), 0.1, -4)), "world", gain_db=2.0)
    # --- car alarms (Altavega): horn-speaker siren patterns, played far by the ambience director and near by cars
    for i in range(3):
        n = A.n_of(7.0)
        t = np.arange(n) / A.SR
        if i == 0:     # whoop: rising sweeps
            f = 700 + 900 * ((t * 2.2) % 1.0)
        elif i == 1:   # two-tone alternation
            f = np.where(((t * 3.0) % 1.0) < 0.5, 1150.0, 850.0)
        else:          # fast chirps
            f = 1000 + 600 * np.sin(2 * np.pi * 6.0 * t)
        ph = np.cumsum(f) / A.SR
        sq = np.sign(np.sin(2 * np.pi * ph)) * 0.6 + np.sin(2 * np.pi * ph * 3) * 0.2
        horn = A.bp(sq, 500, 3500, 2)
        horn = A.peaking(horn, 1800, 6, 2)
        horn *= A.env_ar(n, 0.02, 0.2, 6.7)
        out(f"world/car_alarm_{i + 1:02d}", A.lp(horn, 5000), "world", gain_db=-2.0)
    # --- metal creaks / groans (city: hanging signs, girders; port: hulls in the ice)
    for i in range(5):
        d = rng.uniform(1.4, 2.6)
        n = A.n_of(d)
        f0 = rng.uniform(150, 420)
        g = A.creak(n, rng, np.interp(np.linspace(0, 1, n), [0, 0.3, 0.7, 1], rng.uniform(30, 160, 4)),
                    [(f0, 0.08, 0), (f0 * 2.7, 0.06, -3), (f0 * 5.1, 0.04, -6), (f0 * 8.3, 0.03, -9)], 0.2,
                    A.env_points(n, [(0, 0), (d * 0.2, 1), (d * 0.8, 0.7), (d, 0)]))
        out(f"world/metal_creak_{i + 1:02d}", g, "amb_oneshot")
