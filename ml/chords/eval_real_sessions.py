"""Evaluate the app's on-device ML vs DSP chord calls against an INDEPENDENT
reference, on REAL Lab-mode uploads (the honest real-audio harness).

This closes the improve-loop: the app's Lab mode uploads real-guitar sessions
(metadata + short audio) to the box; this script decodes them, runs an
independent librosa CQT-chroma template recogniser as an approximate ground
truth, and reports the ML and DSP majmin accuracy on REAL audio — the number a
future model must beat (the synth held-out is saturated + doesn't transfer).

First real result (2026-07-14, 7 sessions / 75 events): ML 36% vs DSP 56% —
the synth-trained full-band model is WORSE than the shipping DSP on real audio.

Usage (needs an audio venv):
    python -m venv ~/audio-venv && ~/audio-venv/bin/pip install "numpy<2" librosa soundfile
    ~/audio-venv/bin/python ml/chords/eval_real_sessions.py /path/to/diagnostics_data

The reference is itself imperfect on phone-mic full-band audio — treat the
absolute numbers as noisy but the ML-vs-DSP gap as decisive.
"""
from __future__ import annotations

import base64
import glob
import gzip
import io
import json
import os
import re
import sys
import warnings

warnings.filterwarnings("ignore")
import numpy as np  # noqa: E402

NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def _majmin(label: str | None) -> str | None:
    """Reduce a chord label to its majmin root+quality (Cmaj7→C, Am7→Am)."""
    if not label:
        return None
    m = re.match(r"^([A-G][#b]?)(m(?!aj))?", label)
    return (m.group(1) + ("m" if m.group(2) else "")) if m else label


def _reference(wav_bytes: bytes, times: list[float]) -> list[str]:
    """Independent majmin estimate at each time via librosa harmonic CQT-chroma."""
    import librosa

    y, sr = librosa.load(io.BytesIO(wav_bytes), sr=22050, mono=True)
    yh = librosa.effects.harmonic(y, margin=3.0)  # suppress drums/percussion
    ch = librosa.feature.chroma_cqt(y=yh, sr=sr, hop_length=2048, bins_per_octave=36)
    ch = librosa.decompose.nn_filter(ch, aggregate=np.median, metric="cosine")
    n = ch.shape[1]
    hop_t = 2048 / sr
    out = []
    for t in times:
        f = int(round(t / hop_t))
        v = ch[:, max(0, f - 2):min(n, f + 3)].mean(1)
        v = v / (v.sum() + 1e-9)
        best = (-1.0, "?")
        for r in range(12):
            for q, offs in (("", (0, 4, 7)), ("m", (0, 3, 7))):
                sc = float(sum(v[(r + o) % 12] for o in offs))
                if sc > best[0]:
                    best = (sc, NAMES[r] + q)
        out.append(best[1])
    return out


def main(data_dir: str) -> None:
    files = sorted(glob.glob(os.path.join(data_dir, "*.bin")))
    ml_ok = ds_ok = total = 0
    ml_win = ds_win = tie = 0
    for f in files:
        try:
            s = json.loads(gzip.decompress(open(f, "rb").read()))
        except Exception:
            continue
        ev = s.get("events", [])
        clips = s.get("audioClips", [])
        if not ev or not clips or not clips[0].get("wavBase64"):
            continue
        wav = base64.b64decode(clips[0]["wavBase64"])
        refs = _reference(wav, [e["tSec"] for e in ev])
        for e, ref in zip(ev, refs):
            total += 1
            ml = _majmin(e.get("mlChord"))
            ds = _majmin(e.get("dspChord"))
            mm, dm = ml == ref, ds == ref
            ml_ok += mm
            ds_ok += dm
            if e.get("agree"):
                continue
            if mm and not dm:
                ml_win += 1
            elif dm and not mm:
                ds_win += 1
            else:
                tie += 1
    if total == 0:
        print("no sessions with events+audio found in", data_dir)
        return
    print(f"REAL-audio majmin accuracy vs librosa reference ({total} events):")
    print(f"  ML  (full-band model): {ml_ok}/{total} = {ml_ok/total*100:.1f}%")
    print(f"  DSP (shipping chroma) : {ds_ok}/{total} = {ds_ok/total*100:.1f}%")
    print(f"On disagreements: ML-correct {ml_win}  DSP-correct {ds_win}  "
          f"neither/both {tie}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/home/ubuntu/strumsight-diag-data")
