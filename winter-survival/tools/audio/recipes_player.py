"""Player: footsteps by surface, breath, vocal reactions, heartbeat, foley and melee (S1).

Footsteps (8 per surface; the game adds pitch / volume by speed and posture):
  snow      fresh powder — Kenney footstep_snow layered with a designed crunch (compacting grain burst)
  packed    packed snow / road / track — qubodup's CC0 «walking on snow-covered gravel» (Corsica)
  ice       designed: a hard heel tap, a thin glassy ring, a scatter of ice grit
  wood      Kenney footstep_wood + rubberduck / tinyworlds wooden steps (CC0), a board creak now and then
  concrete  Kenney footstep_concrete + Fantozzi's stone steps (qubodup, CC0), a little snow grit
  metal     haeldb's CC0 metal steps + a designed plate resonance
Vocal reactions from qubodup's CC0 «15 vocal male strain/hurt» and haeldb's CC0 grunts; melee swings from
artisticdude's CC0 swishes layered with designed air; impacts from Kenney punches / knife slices and qubodup's wet
impacts and wood hits.
"""
from __future__ import annotations

import numpy as np

import audiolib as A
from recipes_creatures import breath, snow_body_fall, snow_step, whoosh
from recipes_weapons import friction, metal_click, src


def kick(rng, fc: float = 200, tau: float = 0.02) -> np.ndarray:
    n = A.n_of(tau * 6)
    x = A.lp(A.noise(n, rng, "brown"), fc) * A.env_exp(n, tau, 0.002)
    return x / (np.max(np.abs(x)) + 1e-9)


def step_snow(rng, i: int) -> np.ndarray:
    k = src("kenney_impactsounds", f"footstep_snow_{i % 5:03d}.ogg", 60)
    k = A.pitch(k, rng.uniform(-1.5, 1.0))
    c = snow_step(rng, rng.uniform(0.9, 1.1))
    return A.mix((k, 0, 0), (c, rng.uniform(0.0, 0.01), -6), (kick(rng, 180, 0.018), 0, -12))


def step_packed(rng, i: int) -> np.ndarray:
    names = [f"corsica-s-walking-on-snow-covered-gravel-{k:02d}.m4a" for k in (1, 4, 5, 7, 8, 9, 10, 12, 14, 15)]
    g = src("42-snow-and-gravel-footsteps", names[i % len(names)], 70, -45)
    g = A.pitch(g, rng.uniform(-1.0, 1.0))[: A.n_of(0.45)]
    return A.mix((A.fade(g, 0.001, 0.08), 0, 0), (kick(rng, 220, 0.015), 0, -10))


def step_ice(rng, i: int) -> np.ndarray:
    n = A.n_of(0.3)
    heel = A.bp(A.noise(A.n_of(0.02), rng), 400, 5000) * A.env_exp(A.n_of(0.02), 0.004, 0.0005)
    exc = np.zeros(n)
    exc[0] = 1.0
    f = rng.uniform(1600, 2300)
    ring = A.modal(exc, [(f, 0.025, 0), (f * 2.3, 0.018, -4), (f * 3.9, 0.012, -8)])
    grit = A.grains(n, rng, np.linspace(1500, 50, n), 0.0008, (3000, 12000), A.env_ar(n, 0.003, 0.15))
    slide = friction(rng, 0.08, 1500, 6000, 30, A.env_ar(A.n_of(0.08), 0.01, 0.07)) if i % 3 == 0 else np.zeros(1)
    toe = A.bp(A.noise(A.n_of(0.012), rng), 800, 7000) * A.env_exp(A.n_of(0.012), 0.003, 0.0003)
    return A.mix((heel / (np.max(np.abs(heel)) + 1e-9), 0, 0), (ring / (np.max(np.abs(ring)) + 1e-9), 0, -16),
                 (grit / (np.max(np.abs(grit)) + 1e-9), 0.002, -20), (kick(rng, 260, 0.01), 0, -8), (slide, 0.01, -16),
                 (toe / (np.max(np.abs(toe)) + 1e-9), rng.uniform(0.07, 0.1), -8))


def step_wood(rng, i: int) -> np.ndarray:
    pool = [("kenney_impactsounds", f"footstep_wood_{k:03d}.ogg") for k in range(5)] + \
           [("100-cc0-sfx-2", f"sfx100v2-footstep-wood-0{k}.m4a") for k in (1, 3, 4)] + \
           [("different-steps-on-wood-stone-leaves-gravel-and-mud", f"wood0{k}.m4a") for k in (1, 3)]
    x = src(*pool[i % len(pool)], 50)[: A.n_of(0.4)]
    x = A.pitch(x, rng.uniform(-1.0, 1.0))
    # heel on boards: the recordings are mostly sub thump; a short knock of the planks makes them read on small speakers
    n = A.n_of(0.2)
    exc = A.bp(A.noise(A.n_of(0.004), rng), 300, 4000) * np.hanning(A.n_of(0.004))
    knock = A.modal(A.pad_to(exc, n), [(rng.uniform(180, 240), 0.04, 0), (rng.uniform(420, 520), 0.03, -2),
                                       (rng.uniform(900, 1100), 0.02, -5), (rng.uniform(1900, 2300), 0.012, -9)])
    toe = A.modal(A.pad_to(exc, n), [(rng.uniform(260, 320), 0.03, 0), (rng.uniform(600, 700), 0.02, -3), (rng.uniform(1300, 1600), 0.012, -7)])
    scuff = friction(rng, 0.08, 600, 5000, 25, A.env_ar(A.n_of(0.08), 0.01, 0.07))
    parts = [(A.fade(x, 0.001, 0.06), 0, -2), (knock / (np.max(np.abs(knock)) + 1e-9), 0, -4),
             (toe / (np.max(np.abs(toe)) + 1e-9), rng.uniform(0.06, 0.09), -10), (scuff, 0.02, -20)]
    if i % 4 == 1:
        m = A.n_of(0.3)
        cr = A.creak(m, rng, np.linspace(60, 35, m), [(rng.uniform(300, 380), 0.02, 0), (rng.uniform(800, 950), 0.015, -4)], 0.3, A.env_ar(m, 0.05, 0.2))
        parts.append((cr, 0.03, -18))
    return A.mix(*parts)


def step_concrete(rng, i: int) -> np.ndarray:
    pool = [("kenney_impactsounds", f"footstep_concrete_{k:03d}.ogg") for k in range(5)] + \
           [("fantozzis-footsteps-grasssand-stone", f"fantozzi-stone-{s}{k}.m4a") for s in "lr" for k in (1, 2, 3)]
    x = src(*pool[i % len(pool)], 60)[: A.n_of(0.4)]
    x = A.pitch(x, rng.uniform(-1.0, 0.8))
    if len(x) < A.n_of(0.2):  # Kenney's concrete steps are a bare 0.1 s heel: add a sole scuff
        sc = friction(rng, 0.12, 800, 6000, 25, A.env_ar(A.n_of(0.12), 0.01, 0.1))
        x = A.mix((x, 0, 0), (sc, 0.03, -14))
    grit = A.grains(A.n_of(0.12), rng, 800, 0.0015, (2500, 9000), A.env_ar(A.n_of(0.12), 0.005, 0.1))
    return A.mix((A.fade(x, 0.001, 0.06), 0, 0), (grit / (np.max(np.abs(grit)) + 1e-9), 0.004, -16))


def step_metal(rng, i: int) -> np.ndarray:
    names = ["step-metal.m4a", "step-metal-2.m4a", "step-metal-3.m4a", "step-metal-4.m4a"]
    x = src("footsteps-leather-cloth-armor", names[i % 4], 60)
    x = A.pitch(x, rng.uniform(-3.0, -1.0))
    n = A.n_of(0.35)
    exc = np.zeros(n)
    exc[0] = 1.0
    f = rng.uniform(180, 260)
    plate = A.modal(exc, [(f, 0.12, 0), (f * 1.9, 0.09, -2), (f * 3.1, 0.07, -5), (f * 4.7, 0.05, -8), (f * 6.8, 0.03, -10)])
    return A.mix((A.fade(x, 0.001, 0.05), 0, 0), (plate / (np.max(np.abs(plate)) + 1e-9), 0, -10), (kick(rng, 300, 0.012), 0, -8))


def heartbeat(rng) -> np.ndarray:
    """Lub-dub: two low thumps (≈ 55 / 45 Hz) 0.28 s apart, felt in the chest (played 2D on the UI bus)."""
    def thump(f, tau, g):
        n = A.n_of(0.25)
        s = A.sine_sweep(n, f * 1.4, f, 0.02) * A.env_exp(n, tau, 0.008)
        s += A.lp(A.noise(n, rng, "brown"), 120) * A.env_exp(n, tau * 0.8, 0.006) * 0.8
        return s * A.db(g)
    return A.mix((thump(rng.uniform(52, 58), 0.05, 0), 0, 0), (thump(rng.uniform(42, 48), 0.06, -4), rng.uniform(0.26, 0.3), 0))


def build(out):
    rng = np.random.default_rng(3307)
    # --- footsteps: 8 per surface
    for surface, fn, gain in (("snow", step_snow, 0.0), ("packed", step_packed, 0.0), ("ice", step_ice, -1.0),
                              ("wood", step_wood, 0.0), ("concrete", step_concrete, -1.0), ("metal", step_metal, -1.0)):
        for i in range(8):
            out(f"player/step_{surface}_{i + 1:02d}", fn(rng, i), "footstep", gain_db=gain)
    # --- breath in the cold (exhale puffs) and running breaths
    for i in range(4):
        out(f"player/breath_cold_{i + 1:02d}", breath(rng, rng.uniform(0.7, 1.0), False, 0.0, [(450, 5, 2), (1300, 4, 2.5)]), "player_vocal", gain_db=-10.0)
    for i in range(6):
        parts = [(breath(rng, rng.uniform(0.2, 0.26), True, 0.15), 0, -2),
                 (breath(rng, rng.uniform(0.28, 0.36), False, 0.2, [(520, 7, 2), (1400, 5, 2.5)]), 0.23, 0)]
        out(f"player/breath_run_{i + 1:02d}", A.mix(*parts), "player_vocal", gain_db=-6.0)
    # --- shiver (teeth chatter) when freezing: fast tiny clicks in bursts
    for i in range(3):
        n = A.n_of(1.2)
        rate = 22 + 6 * np.sin(np.linspace(0, np.pi * 3, n))
        ch = A.creak(n, rng, rate, [(rng.uniform(1800, 2300), 0.006, 0), (rng.uniform(3500, 4200), 0.004, -4)], 0.2,
                     A.env_points(n, [(0, 0), (0.1, 1), (0.45, 0.6), (0.6, 1), (1.1, 0.8), (1.2, 0)]))
        br = breath(rng, 1.1, True, 0.9, [(600, 6, 2), (1700, 4, 2.5)])
        out(f"player/shiver_{i + 1:02d}", A.mix((ch, 0, -4), (br, 0.05, -10)), "player_vocal", gain_db=-8.0)
    # --- vocal: hurt (6), downed (3), death (3)
    hurt_src = [1, 2, 8, 11, 12, 3]
    for i, k in enumerate(hurt_src):
        v = src("15-vocal-male-strainhurtpainjump-sounds", f"slightscream-{k:02d}.m4a", 90)
        out(f"player/hurt_{i + 1:02d}", A.fade(A.pitch(v, rng.uniform(-1.5, 0.5)), 0.003, 0.08), "player_vocal")
    for i, k in enumerate([14, 13, 10]):
        v = src("15-vocal-male-strainhurtpainjump-sounds", f"slightscream-{k:02d}.m4a", 90)
        x = A.mix((A.pitch(v, -1.0), 0, 0), (snow_body_fall(rng, 1.1), 0.22, -3))
        out(f"player/downed_{i + 1:02d}", x, "player_vocal")
    for i, k in enumerate([15, 5, 9]):
        v = src("15-vocal-male-strainhurtpainjump-sounds", f"slightscream-{k:02d}.m4a", 90)
        v = A.pitch(v, -2.5)
        tail = breath(rng, 0.9, False, 0.3, [(400, 6, 2), (1000, 4, 2)])
        out(f"player/die_{i + 1:02d}", A.mix((A.fade(v, 0.003, 0.2), 0, 0), (tail, len(v) / A.SR - 0.1, -8)), "player_vocal")
    # --- heartbeat (single lub-dub; the manager schedules it by intensity)
    for i in range(2):
        out(f"player/heartbeat_{i + 1:02d}", heartbeat(rng), "foley", gain_db=-2.0)
    # --- foley: eat, bandage, pickup, tool break
    for i in range(4):
        e = src("80-cc0-creature-sfx", f"eat-0{1 + i}.m4a", 120)
        crunch = A.grains(A.n_of(0.25), rng, 900, 0.002, (1500, 7000), A.env_ar(A.n_of(0.25), 0.005, 0.2))
        x = A.mix((A.pitch(e, rng.uniform(-2, 0)), 0, 0), (crunch / (np.max(np.abs(crunch)) + 1e-9), 0.0, -12))
        out(f"player/eat_{i + 1:02d}", x, "foley")
    for i in range(3):
        n = A.n_of(0.55)
        tear = A.bp(A.noise(n, rng), 1200, 7000) * (A.grains(n, rng, 700, 0.002, (1000, 8000)) * 20 + 0.2)
        tear *= A.env_points(n, [(0, 0), (0.03, 1), (0.35, 0.8), (0.5, 0)])
        cl = src("kenney_rpgaudio", f"cloth{1 + i}.ogg", 150)
        out(f"player/bandage_{i + 1:02d}", A.mix((tear / (np.max(np.abs(tear)) + 1e-9), 0, -4), (cl, 0.4, 0)), "foley", gain_db=-2.0)
    for i, (pack, f) in enumerate([("kenney_rpgaudio", "handleSmallLeather.ogg"), ("kenney_rpgaudio", "handleSmallLeather2.ogg"),
                                   ("kenney_rpgaudio", "cloth4.ogg"), ("kenney_rpgaudio", "dropLeather.ogg"),
                                   ("kenney_rpgaudio", "beltHandle1.ogg")]):
        x = src(pack, f, 150)
        out(f"player/pickup_{i + 1:02d}", A.pitch(x, rng.uniform(-1, 1)), "foley", gain_db=-3.0)
    for i in range(3):
        crack = src("35-wooden-crackshitsdestructions", f"crack0{2 + i * 3}-mp3.m4a", 80)
        x = A.mix((crack[: A.n_of(0.5)], 0, 0), (metal_click(rng, 0.8, 1.0, 1.5), 0.06, -8), (snow_step(rng, 0.7), 0.25, -12))
        out(f"player/tool_break_{i + 1:02d}", x, "foley")
    # --- melee: swings per weight (light: knife / fists; medium: crowbar / machete; heavy: bat / axe)
    swishes = [f"swish-{k}.m4a" for k in range(1, 14)]
    for weight, (lo, hi, dur, semis) in {"light": (600, 5000, 0.18, 2.0), "medium": (350, 3500, 0.26, 0.0),
                                         "heavy": (180, 2500, 0.36, -3.0)}.items():
        for i in range(5):
            sw = src("swishes-sound-pack", swishes[(i * 3 + len(weight)) % 13], 100)
            sw = A.pitch(sw, semis + rng.uniform(-1, 1))
            air = whoosh(rng, dur * rng.uniform(0.9, 1.1), lo, hi, 0.65)
            out(f"player/swing_{weight}_{i + 1:02d}", A.mix((air, 0, 0), (sw, dur * 0.3, -4)), "melee", gain_db=-4.0)
    # --- melee impacts: blunt / sharp on flesh, on wood, on metal; fists; blocked; shove; stomp; stab
    for i in range(5):
        p = src("kenney_impactsounds", f"impactPunch_heavy_{i:03d}.ogg")
        sq = src("8-wet-squish-slurp-impacts", f"impactsplat0{1 + (i + 2) % 8}-mp3.m4a")
        bone = src("35-wooden-crackshitsdestructions", f"crack{1 + i:02d}-mp3.m4a")
        out(f"player/hit_blunt_flesh_{i + 1:02d}", A.mix((p, 0, 0), (sq[: A.n_of(0.3)], 0.005, -6), (A.hp(bone[: A.n_of(0.12)], 800), 0.002, -14)), "melee")
        sl = src("kenney_rpgaudio", ["knifeSlice.ogg", "knifeSlice2.ogg"][i % 2])
        out(f"player/hit_sharp_flesh_{i + 1:02d}", A.mix((A.pitch(sl, rng.uniform(-3, 0)), 0, -2), (sq[: A.n_of(0.3)], 0.0, -3),
                                                     (kick(rng, 250, 0.02), 0, -6)), "melee")
        out(f"player/hit_fist_{i + 1:02d}", A.pitch(src("kenney_impactsounds", f"impactPunch_medium_{i:03d}.ogg"), rng.uniform(-1, 1)), "melee", gain_db=-3.0)
        w = src("35-wooden-crackshitsdestructions", f"impactwood{10 + i:02d}-mp3.m4a")
        out(f"player/hit_wood_{i + 1:02d}", w[: A.n_of(0.5)], "melee", gain_db=-2.0)
        m = src("kenney_impactsounds", f"impactMetal_heavy_{i:03d}.ogg")
        out(f"player/hit_metal_{i + 1:02d}", A.mix((m, 0, 0), (metal_click(rng, 0.5, 1.0, 2.0, -20), 0, -10)), "melee", gain_db=-2.0)
    for i in range(3):
        b = src("kenney_impactsounds", f"impactPlank_medium_{i:03d}.ogg")
        out(f"player/blocked_{i + 1:02d}", A.mix((b[: A.n_of(0.4)], 0, 0), (metal_click(rng, 1.2, 0.8, 0.6), 0, -12)), "melee", gain_db=-3.0)
        out(f"player/shove_{i + 1:02d}", A.mix((whoosh(rng, 0.2, 200, 1500, 0.7), 0, -4), (kick(rng, 300, 0.03), 0.14, 0),
                                               (src("kenney_rpgaudio", f"cloth{1 + i}.ogg", 150)[: A.n_of(0.3)], 0.1, -6)), "melee", gain_db=-3.0)
        st = A.mix((kick(rng, 150, 0.04), 0, 0), (snow_step(rng, 1.4), 0.0, -4), (A.hp(src("35-wooden-crackshitsdestructions", f"crack0{6 + i}-mp3.m4a")[: A.n_of(0.15)], 900), 0.01, -10),
                   (src("8-wet-squish-slurp-impacts", f"impactsplat0{4 + i}-mp3.m4a")[: A.n_of(0.3)], 0.01, -6))
        out(f"player/stomp_{i + 1:02d}", st, "melee")
        stab = A.mix((src("kenney_rpgaudio", "drawKnife3.ogg", 200)[: A.n_of(0.3)], 0, -8), (src("8-wet-squish-slurp-impacts", f"impactsplat0{1 + i}-mp3.m4a")[: A.n_of(0.35)], 0.05, 0))
        out(f"player/stab_{i + 1:02d}", stab, "melee", gain_db=-2.0)
        out(f"player/throw_{i + 1:02d}", whoosh(rng, 0.28, 300, 3000, 0.6), "melee", gain_db=-8.0)
    # --- revive: hands working on a body (cloth + effort), 2 s loop-able one-shot
    for i in range(2):
        parts = []
        t = 0.0
        while t < 1.8:
            parts.append((src("kenney_rpgaudio", f"cloth{1 + int(rng.integers(0, 4))}.ogg", 150)[: A.n_of(0.4)], t, rng.uniform(-6, 0)))
            t += rng.uniform(0.35, 0.6)
        out(f"player/revive_{i + 1:02d}", A.mix(*parts), "foley", gain_db=-4.0)
