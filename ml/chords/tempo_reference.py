"""Generate independent librosa beat-tracker tempo references for Klangio WAVs.

Usage:
    ~/audio-venv/bin/python ml/chords/tempo_reference.py ml/data/klangio \
        --out /tmp/tempo_reference.json

The JSON object maps the recording stem (for example ``recording_1001``) to
the BPM returned by ``librosa.beat.beat_track``. Recordings without a positive
tempo are intentionally omitted and named on standard output.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import librosa
import numpy as np


def _tempo_bpm(wav: Path) -> float | None:
    audio, sample_rate = librosa.load(wav, sr=None, mono=True)
    tempo, _ = librosa.beat.beat_track(y=audio, sr=sample_rate)
    value = float(np.asarray(tempo).reshape(-1)[0])
    return value if np.isfinite(value) and value > 0 else None


def _recording_stem(wav: Path) -> str:
    suffix = "_phone.wav"
    if not wav.name.endswith(suffix):
        raise ValueError(f"expected a {suffix} file: {wav.name}")
    return wav.name[: -len(suffix)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", type=Path, help="directory containing *_phone.wav")
    parser.add_argument("--out", required=True, type=Path, help="output JSON path")
    args = parser.parse_args()

    wavs = sorted(args.corpus.glob("*_phone.wav"))
    if not wavs:
        raise SystemExit(f"no *_phone.wav files in {args.corpus}")

    references: dict[str, float] = {}
    unavailable: list[str] = []
    for wav in wavs:
        stem = _recording_stem(wav)
        tempo = _tempo_bpm(wav)
        if tempo is None:
            unavailable.append(stem)
        else:
            references[stem] = tempo

    args.out.write_text(
        json.dumps(references, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"librosa version: {librosa.__version__}")
    print(f"tempo references written: {len(references)}/{len(wavs)} -> {args.out}")
    print(f"recordings without tempo ({len(unavailable)}): {unavailable}")


if __name__ == "__main__":
    main()
