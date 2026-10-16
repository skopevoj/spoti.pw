#!/usr/bin/env python3
"""Checks the maths of Sing's built-in separator (SGStemCenterSeparator.swift) on a synthetic mix.

The separator takes the same two-second STFT the Core ML model does and keeps what is centred in the
stereo image and above about 150 Hz, below the top of the voice: a mask of how alike the two channels are, smoothed
over time and frequency, times the mid signal. This script is the same arithmetic in numpy, with the STFT
of SGStemSpectralDSP.swift (centred, reflected ends, periodic Hann, hop 441, 2048 points), so a change to the
mask is tried here before it is tried on a phone.

    python3 harness/sing/center_test.py
"""
import numpy as np

RATE, N, HOP, FRAMES = 44100, 2048, 441, 201
SAMPLES = (FRAMES - 1) * HOP
BINS = N // 2 + 1
WINDOW = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(N) / N)


def stft(x):
    pad = N // 2
    out = np.zeros((BINS, FRAMES), complex)
    for f in range(FRAMES):
        idx = f * HOP - pad + np.arange(N)
        idx = np.where(idx < 0, -idx, np.where(idx >= SAMPLES, 2 * SAMPLES - 2 - idx, idx))
        out[:, f] = np.fft.rfft(x[idx] * WINDOW)
    return out


def istft(spec):
    pad = N // 2
    acc = np.zeros(N + SAMPLES)
    norm = np.zeros(N + SAMPLES)
    for f in range(FRAMES):
        acc[f * HOP:f * HOP + N] += np.fft.irfft(spec[:, f], N) * WINDOW
        norm[f * HOP:f * HOP + N] += WINDOW * WINDOW
    return acc[pad:pad + SAMPLES] / np.maximum(norm[pad:pad + SAMPLES], 1e-8)


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


HZ = np.arange(BINS) * RATE / N
BAND = smoothstep(90, 200, HZ) * (1 - 0.3 * smoothstep(6500, 12000, HZ))
LOW_SIM, HIGH_SIM = 0.55, 0.95


def separate(left, right):
    """The vocals' STFT, the same for both channels."""
    L, R = stft(left), stft(right)
    sim = 2 * np.real(L * np.conj(R)) / (np.abs(L) ** 2 + np.abs(R) ** 2 + 1e-9)
    mask = smoothstep(LOW_SIM, HIGH_SIM, sim)
    # Over time, then over frequency, three taps each, the ends kept.
    padded = np.pad(mask, ((0, 0), (1, 1)), mode="edge")
    mask = 0.25 * padded[:, :-2] + 0.5 * padded[:, 1:-1] + 0.25 * padded[:, 2:]
    padded = np.pad(mask, ((1, 1), (0, 0)), mode="edge")
    mask = 0.25 * padded[:-2] + 0.5 * padded[1:-1] + 0.25 * padded[2:]
    mask *= BAND[:, None]
    return mask * 0.5 * (L + R)


def tone_stack(f0, seconds_gain, rng):
    t = np.arange(SAMPLES) / RATE
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
    x = sum(np.sin(2 * np.pi * f0 * k * vib * t) / k for k in range(1, 12))
    return x * (0.6 + 0.4 * np.sin(2 * np.pi * 2.0 * t) ** 2) * seconds_gain


def main():
    rng = np.random.default_rng(7)
    t = np.arange(SAMPLES) / RATE
    vocal = tone_stack(220, 0.18, rng)                                  # centred
    kick = 0.5 * np.sin(2 * np.pi * 55 * t) * (np.sin(2 * np.pi * 2 * t) > 0.6)   # centred, low
    bass = 0.25 * np.sin(2 * np.pi * 82 * t)                            # centred, low
    guitar = np.convolve(rng.standard_normal(SAMPLES), np.ones(8) / 8, "same") * 0.12   # panned left
    synth = tone_stack(330, 0.10, rng) * 0.9                             # panned right
    keys = tone_stack(262, 0.08, rng)                                    # wide: opposite phase either side
    left = vocal + kick + bass + guitar + 0.3 * synth + keys
    right = vocal + kick + bass + 0.3 * guitar + synth - keys

    estimate = istft(separate(left, right))

    def level(x):
        return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)

    def estimate_of(part_l, part_r=None):
        return istft(separate(part_l, part_l if part_r is None else part_r))

    # Each part alone through the separator, as the part sits in the mix.
    parts = {
        "vocal (centre)": (vocal, vocal),
        "kick (centre, low)": (kick, kick),
        "bass (centre, low)": (bass, bass),
        "guitar (left)": (guitar, 0.3 * guitar),
        "synth (right)": (0.3 * synth, synth),
        "keys (wide)": (keys, -keys),
    }
    print(f"{'part':<22}{'in dB':>8}{'out dB':>9}{'kept':>8}")
    kept = {}
    for name, (l, r) in parts.items():
        out = estimate_of(l, r)
        kept[name] = level(out) - level(0.5 * (l + r) if name.startswith(("vocal", "kick", "bass")) else l)
        print(f"{name:<22}{level(l):8.1f}{level(out):9.1f}{kept[name]:8.1f}")

    # In the whole mix: the vocals' estimate against the true vocal.
    err = estimate - vocal
    snr = level(vocal) - level(err)
    print(f"\nmix: vocal in estimate, error {snr:.1f} dB below the vocal")
    instrumental_left = left - estimate
    residue = level(istft(stft(instrumental_left) * 0 + stft(vocal) - stft(estimate)))
    print(f"vocal left in the instrumental: {level(vocal) - residue:.1f} dB below the vocal")

    ok = kept["vocal (centre)"] > -3 and kept["kick (centre, low)"] < -20 and kept["bass (centre, low)"] < -20 \
        and kept["guitar (left)"] < -12 and kept["synth (right)"] < -12 and kept["keys (wide)"] < -20
    assert ok, kept
    assert snr > 8, snr
    print("ok")


if __name__ == "__main__":
    main()
