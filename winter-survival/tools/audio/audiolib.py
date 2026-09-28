"""VENTISCA sound build (S1): small DSP toolkit shared by the recipes of tools/audio/build_audio.py.

Everything works on float64 numpy arrays at SR (44.1 kHz): mono = shape (n,), stereo = shape (n, 2). Filters that
touch transients are causal (sosfilt: no pre-ringing before a gunshot or a footstep). Randomness always comes from a
numpy Generator the recipe seeds, so a build is reproducible byte for byte on the same machine (the OGG encoder is
the only non-Python step). Decoding / encoding uses ffmpeg (pip `imageio-ffmpeg` ships a static one with libvorbis).
"""
from __future__ import annotations

import os
import shutil
import subprocess
from functools import lru_cache
from math import gcd

import numpy as np
from scipy import signal

SR = 44100


# ------------------------------------------------------------------ io
def ffmpeg_exe() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg  # type: ignore

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception as e:  # pragma: no cover
        raise SystemExit("ffmpeg not found: pip install imageio-ffmpeg") from e


@lru_cache(maxsize=512)
def _load_cached(path: str, sr: int) -> np.ndarray:
    out = subprocess.run([ffmpeg_exe(), "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(sr), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def load(path: str, mono: bool = True, sr: int = SR) -> np.ndarray:
    """Decodes any file ffmpeg reads (ogg, wav, m4a) to float64 at `sr`; mono = mid (L + R) / 2."""
    a = _load_cached(os.path.abspath(path), sr).copy()
    if mono:
        return a.mean(axis=1)
    return a


def write_ogg(path: str, x: np.ndarray, quality: float = 4.0, sr: int = SR) -> None:
    """OGG Vorbis through ffmpeg's libvorbis (-q:a quality, 0–10). Clips at ±1 (callers keep peaks ≤ −1 dBFS)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(np.asarray(x, dtype=np.float64), -1.0, 1.0)
    ch = 1 if x.ndim == 1 else x.shape[1]
    data = x.astype(np.float32).tobytes()
    tmp = path + ".tmp.ogg"
    subprocess.run([ffmpeg_exe(), "-v", "error", "-y", "-f", "f32le", "-ac", str(ch), "-ar", str(sr), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", f"{quality:.2f}", "-map_metadata", "-1", "-fflags", "+bitexact",
                    "-flags:a", "+bitexact", tmp], input=data, check=True)
    os.replace(tmp, path)


# ------------------------------------------------------------------ basics
def secs(n: int) -> float:
    return n / SR


def n_of(seconds: float) -> int:
    return max(1, int(round(seconds * SR)))


def db(x: float) -> float:
    return 10.0 ** (x / 20.0)


def to_db(x: float) -> float:
    return 20.0 * np.log10(max(x, 1e-12))


def peak_db(x: np.ndarray) -> float:
    return to_db(float(np.max(np.abs(x))) if x.size else 0.0)


def mono(x: np.ndarray) -> np.ndarray:
    return x if x.ndim == 1 else x.mean(axis=1)


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if len(x) >= n:
        return x[:n]
    shape = (n - len(x),) + x.shape[1:]
    return np.concatenate([x, np.zeros(shape)])


def mix(*parts: tuple) -> np.ndarray:
    """mix((signal, offset_s, gain_db), ...) → one buffer long enough for every part (mono or stereo)."""
    length = 0
    stereo = False
    for sig, off, _g in parts:
        length = max(length, n_of(off) + len(sig) if off > 0 else len(sig))
        stereo = stereo or sig.ndim == 2
    out = np.zeros((length, 2)) if stereo else np.zeros(length)
    for sig, off, g in parts:
        s = sig
        # a part cut short (it ends on a non-zero sample) gets a ≤ 30 ms fade-out: no click, no hard edge at the cut
        if len(s) > 16:
            pk = float(np.max(np.abs(s)))
            if pk > 0 and float(np.max(np.abs(s[-1]))) > 1e-3 * pk:
                s = fade(s, 0.0, min(0.03, len(s) / SR * 0.25))
        if stereo and s.ndim == 1:
            s = np.stack([s, s], axis=1)
        o = n_of(off) if off > 0 else 0
        out[o:o + len(s)] += s * db(g)
    return out


def dc_block(x: np.ndarray, fc: float = 18.0) -> np.ndarray:
    return hp(x, fc, 2)


# ------------------------------------------------------------------ filters (causal)
def _sos(kind: str, fc, order: int):
    return signal.butter(order, fc, btype=kind, fs=SR, output="sos")


def _apply(x: np.ndarray, sos) -> np.ndarray:
    if x.ndim == 1:
        return signal.sosfilt(sos, x)
    return np.stack([signal.sosfilt(sos, x[:, c]) for c in range(x.shape[1])], axis=1)


def hp(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    return _apply(x, _sos("highpass", min(fc, SR * 0.45), order))


def lp(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    return _apply(x, _sos("lowpass", min(fc, SR * 0.45), order))


def bp(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    return _apply(x, _sos("bandpass", [max(lo, 10.0), min(hi, SR * 0.45)], order))


def peaking(x: np.ndarray, f0: float, gain_db: float, q: float = 1.0) -> np.ndarray:
    """RBJ peaking EQ (causal biquad)."""
    a = 10 ** (gain_db / 40.0)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / (2 * q)
    b = np.array([1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a])
    aa = np.array([1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a])
    sos = np.concatenate([b / aa[0], aa / aa[0]])[None, :]
    return _apply(x, sos)


def shelf(x: np.ndarray, f0: float, gain_db: float, high: bool = True) -> np.ndarray:
    """RBJ shelf (S = 1)."""
    a = 10 ** (gain_db / 40.0)
    w0 = 2 * np.pi * f0 / SR
    alpha = np.sin(w0) / 2 * np.sqrt(2)
    cw = np.cos(w0)
    sa = 2 * np.sqrt(a) * alpha
    if high:
        b = [a * ((a + 1) + (a - 1) * cw + sa), -2 * a * ((a - 1) + (a + 1) * cw), a * ((a + 1) + (a - 1) * cw - sa)]
        aa = [(a + 1) - (a - 1) * cw + sa, 2 * ((a - 1) - (a + 1) * cw), (a + 1) - (a - 1) * cw - sa]
    else:
        b = [a * ((a + 1) - (a - 1) * cw + sa), 2 * a * ((a - 1) - (a + 1) * cw), a * ((a + 1) - (a - 1) * cw - sa)]
        aa = [(a + 1) + (a - 1) * cw + sa, -2 * ((a - 1) + (a + 1) * cw), (a + 1) + (a - 1) * cw - sa]
    b = np.array(b)
    aa = np.array(aa)
    sos = np.concatenate([b / aa[0], aa / aa[0]])[None, :]
    return _apply(x, sos)


def resonator(x: np.ndarray, freq: float, decay_s: float) -> np.ndarray:
    """Two-pole resonator ringing at `freq` with a -60 dB time of `decay_s` (modal synthesis of metal / wood)."""
    r = 10 ** (-3.0 / (decay_s * SR))
    w = 2 * np.pi * freq / SR
    b = [1 - r, 0, 0]
    a = [1, -2 * r * np.cos(w), r * r]
    return signal.lfilter(b, a, x)


def modal(x: np.ndarray, modes) -> np.ndarray:
    """Sum of resonators: modes = [(freq, decay_s, gain_db), ...]."""
    out = np.zeros_like(x)
    for f, d, g in modes:
        if f < SR * 0.45:
            out += resonator(x, f, d) * db(g)
    return out


def sweep_lp(x: np.ndarray, f_start: float, f_end: float, curve: float = 1.0) -> np.ndarray:
    """Time-varying one-pole low-pass (exponential sweep of the cutoff over the buffer)."""
    n = len(x)
    t = np.linspace(0.0, 1.0, n) ** curve
    fc = f_start * (f_end / f_start) ** t
    g = 1.0 - np.exp(-2 * np.pi * fc / SR)
    y = np.empty_like(x)
    acc = np.zeros(x.shape[1:]) if x.ndim == 2 else 0.0
    for i in range(n):
        acc = acc + g[i] * (x[i] - acc)
        y[i] = acc
    return y


# ------------------------------------------------------------------ generators
def noise(n: int, rng: np.random.Generator, color: str = "white") -> np.ndarray:
    w = rng.standard_normal(n)
    if color == "white":
        return w / 3.0
    spec = np.fft.rfft(w)
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1] if n > 1 else 1.0
    if color == "pink":
        spec /= np.sqrt(f)
    elif color == "brown":
        spec /= f
    y = np.fft.irfft(spec, n)
    return y / (np.std(y) * 3.0 + 1e-12)


def env_exp(n: int, tau_s: float, attack_s: float = 0.0005) -> np.ndarray:
    t = np.arange(n) / SR
    e = np.exp(-t / max(tau_s, 1e-5))
    na = n_of(attack_s)
    if na > 1:
        e[:na] *= np.linspace(0.0, 1.0, na) ** 2
    return e


def env_ar(n: int, attack_s: float, release_s: float, hold_s: float = 0.0, curve: float = 2.0) -> np.ndarray:
    e = np.zeros(n)
    a = min(n, n_of(attack_s))
    h = min(n - a, n_of(hold_s))
    r = min(n - a - h, n_of(release_s))
    e[:a] = np.linspace(0, 1, a) ** curve
    e[a:a + h] = 1.0
    e[a + h:a + h + r] = np.linspace(1, 0, r) ** curve
    return e


def env_points(n: int, pts) -> np.ndarray:
    """Piecewise-linear envelope from [(t_s, value), ...]."""
    t = np.arange(n) / SR
    ts = [p[0] for p in pts]
    vs = [p[1] for p in pts]
    return np.interp(t, ts, vs)


def sine_sweep(n: int, f0: float, f1: float, tau_s: float | None = None, phase: float = 0.0) -> np.ndarray:
    """Sine whose frequency glides exponentially from f0 to f1 (tau = time constant; None = linear over n)."""
    t = np.arange(n) / SR
    if tau_s is None:
        f = np.linspace(f0, f1, n)
    else:
        f = f1 + (f0 - f1) * np.exp(-t / tau_s)
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    return np.sin(ph)


def friedlander(n: int, t_pos_s: float, b: float = 1.2) -> np.ndarray:
    """Blast wave: instant rise, positive phase of t_pos then the negative phase (Friedlander waveform)."""
    t = np.arange(n) / SR
    return (1 - t / t_pos_s) * np.exp(-b * t / t_pos_s)


def nwave(n: int, width_s: float) -> np.ndarray:
    """Supersonic crack (N-wave): +1 → −1 linear over `width_s`, zero elsewhere."""
    w = max(3, n_of(width_s))
    out = np.zeros(n)
    out[:w] = np.linspace(1.0, -1.0, w)
    return out


def impulses(n: int, times_s, gains_db, rng=None, jitter_s: float = 0.0) -> np.ndarray:
    out = np.zeros(n)
    for t, g in zip(times_s, gains_db):
        if rng is not None and jitter_s > 0:
            t = t + rng.uniform(-jitter_s, jitter_s)
        i = n_of(t) if t > 0 else 0
        if 0 <= i < n:
            out[i] += db(g)
    return out


def grains(n: int, rng: np.random.Generator, rate_hz, grain_s: float, band=(800, 8000), gain_env=None,
           amp_sigma: float = 0.6) -> np.ndarray:
    """Poisson cloud of short noise grains (snow crunch, fire crackle, ice): `rate_hz` scalar or per-sample array."""
    rate = np.full(n, float(rate_hz)) if np.isscalar(rate_hz) else np.asarray(rate_hz)
    p = rate / SR
    hits = rng.random(n) < p
    out = np.zeros(n)
    idx = np.nonzero(hits)[0]
    gl = max(4, n_of(grain_s))
    win = np.hanning(gl * 2)[gl:]  # decaying half window
    for i in idx:
        g = rng.lognormal(0.0, amp_sigma)
        seg = rng.standard_normal(gl) * win * g
        e = min(n, i + gl)
        out[i:e] += seg[: e - i]
    out = bp(out, band[0], band[1], 2)
    if gain_env is not None:
        out *= gain_env
    return out


# ------------------------------------------------------------------ dynamics / shaping
def saturate(x: np.ndarray, drive: float = 2.0) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def compress(x: np.ndarray, thresh_db: float = -18, ratio: float = 3.0, attack_s: float = 0.003,
             release_s: float = 0.08) -> np.ndarray:
    m = np.abs(mono(x))
    a_a = np.exp(-1 / (attack_s * SR))
    a_r = np.exp(-1 / (release_s * SR))
    env = np.zeros_like(m)
    e = 0.0
    for i, v in enumerate(m):
        e = a_a * e + (1 - a_a) * v if v > e else a_r * e + (1 - a_r) * v
        env[i] = e
    lvl = 20 * np.log10(env + 1e-9)
    over = np.maximum(lvl - thresh_db, 0.0)
    gain = 10 ** (-(over * (1 - 1 / ratio)) / 20)
    return x * (gain if x.ndim == 1 else gain[:, None])


def fade(x: np.ndarray, in_s: float = 0.002, out_s: float = 0.01) -> np.ndarray:
    y = x.copy()
    n = len(y)
    ni = min(n, n_of(in_s)) if in_s > 0 else 0
    no = min(n, n_of(out_s)) if out_s > 0 else 0
    if ni > 1:
        w = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, ni))
        y[:ni] *= w if y.ndim == 1 else w[:, None]
    if no > 1:
        w = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, no))
        y[n - no:] *= w if y.ndim == 1 else w[:, None]
    return y


def trim(x: np.ndarray, thr_db: float = -55.0, pre_s: float = 0.004, post_s: float = 0.03,
         keep_head: bool = False) -> np.ndarray:
    """Cuts leading / trailing silence below `thr_db` relative to the peak, with short fades."""
    m = np.abs(mono(x))
    if m.max() <= 0:
        return x
    thr = m.max() * db(thr_db)
    # smooth to ignore single-sample dips
    k = max(1, n_of(0.004))
    sm = np.convolve(m, np.ones(k) / k, mode="same")
    idx = np.nonzero(sm > thr)[0]
    if len(idx) == 0:
        return x
    a = 0 if keep_head else max(0, idx[0] - n_of(pre_s))
    b = min(len(x), idx[-1] + n_of(post_s))
    return fade(x[a:b], 0.0 if keep_head or a == 0 else min(pre_s, 0.003), min(post_s, 0.02))


def tail_fade(x: np.ndarray, out_s: float) -> np.ndarray:
    return fade(x, 0.0, out_s)


# ------------------------------------------------------------------ loudness
def momentary_max_lufs(x: np.ndarray) -> float:
    """Max momentary loudness (400 ms K-weighted window, 100 ms hop). Works for short one-shots (zero-padded)."""
    import pyloudnorm as pyln

    s = x if x.ndim == 2 else x[:, None]
    n400 = n_of(0.4)
    if len(s) < n400:
        s = np.concatenate([s, np.zeros((n400 - len(s), s.shape[1]))])
    meter = pyln.Meter(SR, block_size=0.4)
    # K-weighting via the meter's filters, then block energy
    y = s.copy()
    for filt in meter._filters.values():
        y = np.stack([filt.apply_filter(y[:, c]) for c in range(y.shape[1])], axis=1)
    hop = n_of(0.1)
    best = -120.0
    for i in range(0, len(y) - n400 + 1, hop):
        blk = y[i:i + n400]
        z = np.mean(blk ** 2, axis=0).sum()
        if z > 0:
            best = max(best, -0.691 + 10 * np.log10(z))
    return best


def integrated_lufs(x: np.ndarray) -> float:
    import pyloudnorm as pyln

    s = x if x.ndim == 2 else x[:, None]
    if len(s) < n_of(0.5):
        return momentary_max_lufs(x)
    return float(pyln.Meter(SR).integrated_loudness(s))


def normalize(x: np.ndarray, peak: float | None = None, lufs: float | None = None, mode: str = "momentary",
              peak_cap: float = -1.0) -> np.ndarray:
    """Scales to a loudness target (momentary max or integrated LUFS) or a peak, never above `peak_cap` dBFS."""
    y = x.astype(np.float64)
    if lufs is not None:
        cur = momentary_max_lufs(y) if mode == "momentary" else integrated_lufs(y)
        if np.isfinite(cur) and cur > -100:
            y = y * db(lufs - cur)
    elif peak is not None:
        y = y * db(peak - peak_db(y))
    p = peak_db(y)
    if p > peak_cap:
        y = y * db(peak_cap - p)
    return y


# ------------------------------------------------------------------ pitch / time
def resample_ratio(x: np.ndarray, ratio: float) -> np.ndarray:
    """Plays `x` `ratio` times faster (ratio 1.12 = +2 semitones, shorter). Polyphase (clean, no aliasing)."""
    if abs(ratio - 1.0) < 1e-4:
        return x.copy()
    den = 1000
    num = int(round(den / ratio))
    g = gcd(num, den)
    return signal.resample_poly(x, num // g, den // g, axis=0)


def pitch(x: np.ndarray, semitones: float) -> np.ndarray:
    return resample_ratio(x, 2 ** (semitones / 12.0))


def time_stretch(x: np.ndarray, factor: float, win_s: float = 0.06) -> np.ndarray:
    """Overlap-add time stretch (factor 1.5 = 50 % longer, same pitch); fine for noisy textures and voices."""
    xm = mono(x)
    w = n_of(win_s)
    hop_out = w // 4
    hop_in = hop_out / factor
    win = np.hanning(w)
    n_out = int(len(xm) * factor) + w
    out = np.zeros(n_out)
    norm = np.zeros(n_out)
    pos = 0.0
    o = 0
    while int(pos) + w < len(xm) and o + w < n_out:
        seg = xm[int(pos):int(pos) + w] * win
        out[o:o + w] += seg
        norm[o:o + w] += win
        pos += hop_in
        o += hop_out
    norm[norm < 1e-3] = 1.0
    return (out / norm)[: int(len(xm) * factor)]


# ------------------------------------------------------------------ space
def convolve(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    if x.ndim == 1 and ir.ndim == 1:
        return signal.fftconvolve(x, ir)
    xs = x if x.ndim == 2 else np.stack([x, x], axis=1)
    irs = ir if ir.ndim == 2 else np.stack([ir, ir], axis=1)
    return np.stack([signal.fftconvolve(xs[:, c], irs[:, c]) for c in range(2)], axis=1)


def make_ir(kind: str, rng: np.random.Generator, length_s: float | None = None, stereo: bool = False) -> np.ndarray:
    """Algorithmic impulse responses of the four firing environments (and a small room):
    forest   dense diffuse field from trunks (early cloud 8–90 ms), T60 ≈ 2 s, highs absorbed fast;
    open     snow-covered field / pass: nearly dry, a ground reflection and a few far slap-backs from the slopes;
    city     street canyon: flutter echo between the facades (≈ 110 ms period), long bright tail T60 ≈ 3.4 s;
    interior small room: dense early reflections 2–25 ms, T60 ≈ 0.55 s, boomy.
    """
    spec = {
        "forest": dict(t60=2.1, lf=6500, hf_end=900, early=(0.008, 0.09, 70), er_db=-6, diffuse_db=-9, pre=0.012),
        "open": dict(t60=0.9, lf=5000, hf_end=900, early=(0.004, 0.02, 4), er_db=-8, diffuse_db=-20, pre=0.004),
        "city": dict(t60=3.4, lf=9000, hf_end=1800, early=(0.006, 0.05, 30), er_db=-5, diffuse_db=-10, pre=0.01),
        "interior": dict(t60=0.55, lf=7000, hf_end=2200, early=(0.002, 0.025, 45), er_db=-3, diffuse_db=-6, pre=0.002),
    }[kind]
    L = length_s or min(5.0, spec["t60"] * 1.1 + 0.2)
    n = n_of(L)
    chans = 2 if stereo else 1
    out = np.zeros((n, chans))
    for c in range(chans):
        t = np.arange(n) / SR
        # diffuse tail: noise × exponential decay, low-passed with a closing cutoff (air + snow absorb the highs)
        d = rng.standard_normal(n) * np.exp(-6.91 * t / spec["t60"])
        d = sweep_lp(d, spec["lf"], spec["hf_end"], 0.6)
        pre = n_of(spec["pre"])
        d[:pre] *= np.linspace(0, 1, pre) ** 2
        ramp = n_of(spec["early"][1])
        d[:ramp] *= np.linspace(0.2, 1.0, ramp)
        y = d * db(spec["diffuse_db"])
        # early reflections
        e0, e1, count = spec["early"]
        er = np.zeros(n)
        for _ in range(count):
            tt = rng.uniform(e0, e1)
            er[n_of(tt)] += rng.choice([-1, 1]) * rng.uniform(0.3, 1.0) * np.exp(-tt / 0.08)
        y += lp(er, spec["lf"]) * db(spec["er_db"])
        if kind == "city":
            period = rng.uniform(0.095, 0.125)
            fl = np.zeros(n)
            k = 1
            while k * period < L * 0.8:
                tt = k * period + rng.uniform(-0.003, 0.003)
                fl[n_of(tt)] += (0.72 ** k) * (1 if k % 2 else -1)
                k += 1
            y += lp(fl, 5000) * db(-4)
            for tt, g in ((rng.uniform(0.25, 0.4), -9), (rng.uniform(0.55, 0.8), -12), (rng.uniform(0.9, 1.3), -15)):
                slap = np.zeros(n)
                slap[n_of(tt)] = 1.0
                y += lp(convolve(slap, np.hanning(n_of(0.012)))[:n], 2500) * db(g)
        if kind == "open":
            # far slopes: a few soft slap-backs (0.35–1.6 s), each smeared and low-passed
            for _ in range(4):
                tt = rng.uniform(0.35, min(1.6, L - 0.3))
                slap = np.zeros(n)
                slap[n_of(tt)] = 1.0
                sm = convolve(slap, np.hanning(n_of(rng.uniform(0.02, 0.06))))[:n]
                y += lp(sm, rng.uniform(900, 1600)) * db(rng.uniform(-22, -15))
        if kind == "interior":
            y = peaking(y, rng.uniform(140, 220), 5.0, 1.2)
        out[:, c] = y
    return out[:, 0] if chans == 1 else out


def reverb_tail(dry: np.ndarray, ir: np.ndarray, start_s: float = 0.0) -> np.ndarray:
    """Wet only (convolution), from `start_s` on."""
    w = convolve(dry, ir)
    return w[n_of(start_s):] if start_s > 0 else w


# ------------------------------------------------------------------ loops
def make_loop(x: np.ndarray, xfade_s: float = 1.5) -> np.ndarray:
    """Seamless loop: the last `xfade_s` is crossfaded (equal power) into the head, then removed from the end."""
    n = n_of(xfade_s)
    if len(x) <= 2 * n:
        return x
    head = x[:n]
    tail = x[-n:]
    t = np.linspace(0, np.pi / 2, n)
    fi = np.sin(t)
    fo = np.cos(t)
    if x.ndim == 2:
        fi = fi[:, None]
        fo = fo[:, None]
    y = x[:-n].copy()
    y[:n] = head * fi + tail * fo
    return y


def stereo_decorrelate(x: np.ndarray, rng: np.random.Generator, width: float = 0.6) -> np.ndarray:
    """Mono → stereo with a short random all-pass-ish decorrelation (sum of tiny delays), keeping the mono image."""
    xm = mono(x)
    k = np.zeros(n_of(0.03))
    k[0] = 1.0
    for _ in range(12):
        k[rng.integers(1, len(k))] += rng.uniform(-0.25, 0.25)
    side = signal.fftconvolve(xm, k)[: len(xm)] - xm
    side = side / (np.std(side) + 1e-12) * np.std(xm) * width
    return np.stack([xm + side, xm - side], axis=1)


def pan(x: np.ndarray, p: float) -> np.ndarray:
    """Constant-power pan of a mono signal (-1 left … +1 right) → stereo."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def creak(n: int, rng: np.random.Generator, rate_hz, modes, jitter: float = 0.25, amp_env=None,
          pulse_s: float = 0.0004) -> np.ndarray:
    """Stick-slip creak (wood, rope, metal): a jittered pulse train (rate = scalar or per-sample array, Hz) exciting
    a bank of resonances `modes` = [(freq, decay_s, gain_db), ...]. Slow rates (< 40 Hz) read as ticking, faster
    ones as a groan."""
    rate = np.full(n, float(rate_hz)) if np.isscalar(rate_hz) else np.asarray(rate_hz, dtype=np.float64)
    exc = np.zeros(n)
    t = 0.0
    pw = max(2, n_of(pulse_s))
    shape = np.hanning(pw * 2)[pw:]
    while True:
        i = int(t)
        if i >= n:
            break
        r = max(rate[i], 1.0)
        a = rng.lognormal(0.0, 0.35)
        e = min(n, i + pw)
        exc[i:e] += shape[: e - i] * a * (1 if rng.random() > 0.5 else -1)
        t += SR / r * (1.0 + rng.uniform(-jitter, jitter))
    y = modal(exc, modes)
    if amp_env is not None:
        y *= amp_env
    return y / (np.max(np.abs(y)) + 1e-12)


def finish(x: np.ndarray, tail_thr_db: float = -60.0) -> np.ndarray:
    """Final cleanup of a rendered file: DC removal, trailing silence trimmed (head kept: onsets stay sample
    accurate), a short fade-out so no file ends on a click."""
    y = dc_block(x, 12.0)
    m = np.abs(mono(y))
    if m.max() <= 0:
        return y
    thr = m.max() * db(tail_thr_db)
    idx = np.nonzero(m > thr)[0]
    end = min(len(y), idx[-1] + n_of(0.02)) if len(idx) else len(y)
    y = y[:end]
    return fade(y, 0.0, min(0.015, len(y) / SR * 0.2))
