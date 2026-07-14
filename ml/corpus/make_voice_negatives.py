#!/usr/bin/env python3
"""Deterministic NON-GUITAR negative stimuli for the offline DSP probe.

The user's field bug: in Live mode the chord label jumps around on human
SPEECH. The Live chord path's only non-guitar gate is a "tonalness" test (top-3
pitch-class chroma energy >= 0.7) that rejects white noise but NOT pitched /
formant-structured audio. To reproduce that gate-leak reproducibly (external
audio download is bot-walled on this box), we synthesise real formant speech
with a source-filter vocal model:

    glottal pulse train at a moving F0 (~90-190 Hz)  ->  3-4 moving formants

This is NOT a guitar-accuracy fixture (synth guitar transfers nothing to real
guitar — see memory). It is a *voice-rejection* fixture: the mechanism that
fools the gate is harmonic/formant concentration, which a source-filter model
reproduces faithfully. The FIX is validated to NOT over-reject on the 82 REAL
klangio guitar recordings; real-voice confirmation is part of the APK test.

Outputs 16 kHz mono 16-bit WAV into ./wav/ (matches the app's resample target).
"""
import os
import struct
import wave

import numpy as np

SR = 16000
OUT = os.path.join(os.path.dirname(__file__), "wav")
os.makedirs(OUT, exist_ok=True)


def write_wav(name, x):
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767.0).astype("<i2")
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  wrote {name}  ({len(x)/SR:.1f}s)")


def formant_filter(source, formants, bw, sr=SR):
    """Apply a bank of resonators (2-pole) at the given formant freqs."""
    out = np.zeros_like(source)
    for f, b in zip(formants, bw):
        r = np.exp(-np.pi * b / sr)
        theta = 2 * np.pi * f / sr
        a1 = -2 * r * np.cos(theta)
        a2 = r * r
        y = np.zeros_like(source)
        for n in range(2, len(source)):
            y[n] = source[n] - a1 * y[n - 1] - a2 * y[n - 2]
        out += y
    m = np.max(np.abs(out)) + 1e-9
    return out / m


def glottal_source(dur, f0_start, f0_end, sr=SR):
    n = int(dur * sr)
    t = np.arange(n) / sr
    f0 = np.linspace(f0_start, f0_end, n) * (1 + 0.03 * np.sin(2 * np.pi * 5 * t))
    phase = np.cumsum(f0) / sr
    # Rosenberg-ish glottal pulse via a few harmonics with -12 dB/oct rolloff.
    src = np.zeros(n)
    for h in range(1, 30):
        src += (1.0 / h ** 1.2) * np.sin(2 * np.pi * h * phase)
    return src / (np.max(np.abs(src)) + 1e-9)


# Vowel formant targets (F1,F2,F3) Hz — a moving vowel sequence sounds like talk.
VOWELS = {
    "a": (730, 1090, 2440),
    "e": (530, 1840, 2480),
    "i": (270, 2290, 3010),
    "o": (570, 840, 2410),
    "u": (300, 870, 2240),
}


def synth_speech(seq, seed=0):
    rng = np.random.default_rng(seed)
    chunks = []
    prev = VOWELS["a"]
    for v in seq:
        dur = rng.uniform(0.14, 0.30)
        f0a = rng.uniform(95, 150)
        f0b = f0a * rng.uniform(0.8, 1.25)
        src = glottal_source(dur, f0a, f0b)
        tgt = VOWELS[v]
        # glide formants from prev to target (coarticulation)
        n = len(src)
        forms = [np.linspace(p, t, n) for p, t in zip(prev, tgt)]
        # apply time-varying formants blockwise (cheap approximation)
        y = np.zeros(n)
        blk = 256
        for s in range(0, n, blk):
            e = min(s + blk, n)
            fm = [f[(s + e) // 2] for f in forms]
            y[s:e] = formant_filter(src[s:e], fm, [80, 90, 120])[: e - s]
        env = np.hanning(n) ** 0.4
        chunks.append(y * env)
        prev = tgt
        # short pause / consonant burst between some syllables
        if rng.random() < 0.4:
            gap = int(rng.uniform(0.03, 0.12) * SR)
            burst = rng.standard_normal(gap) * 0.12 * (rng.random() < 0.5)
            chunks.append(burst)
    x = np.concatenate(chunks)
    return 0.7 * x / (np.max(np.abs(x)) + 1e-9)


def main():
    # 1) Continuous talking (moving vowels) — the primary "jumps on speech" case.
    seq = list("aeiouaeoiuaoeuiaeiouoaeui" * 3)
    write_wav("synth_speech_talk.wav", synth_speech(seq, seed=1))

    # 2) A second speaker (different F0 range / seed) for robustness.
    write_wav("synth_speech_talk2.wav", synth_speech(seq, seed=7))

    # 3) Sustained hum/sung vowel — a single steady pitch (worst case: highly
    #    tonal, easily clears the current 0.7 gate → phantom chord).
    src = glottal_source(6.0, 130, 138)
    hum = formant_filter(src, VOWELS["o"], [90, 100, 130])
    write_wav("synth_hum_vowel.wav", 0.6 * hum)

    # 4) Pink-ish noise (broadband) — should already be rejected; a control.
    rng = np.random.default_rng(3)
    white = rng.standard_normal(SR * 5)
    # simple pinking
    b = np.array([0.049922, -0.095993, 0.050612, -0.004408])
    a = np.array([1, -2.494956, 2.017265, -0.522189])
    from numpy import convolve
    pink = convolve(white, b, "same")
    pink = pink / (np.max(np.abs(pink)) + 1e-9)
    write_wav("synth_noise_pink.wav", 0.4 * pink)


if __name__ == "__main__":
    main()
