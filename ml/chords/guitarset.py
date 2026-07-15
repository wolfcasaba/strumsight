"""GuitarSet loader — REAL guitar audio with TRUE chord annotations (r202).

Dataset
-------
GuitarSet (Xi, Bittner, Pauwels, Ye, Bello — "GuitarSet: A Dataset for Guitar
Transcription", ISMIR 2018). Zenodo record 3371780, licensed **CC-BY-4.0**.
360 takes = 6 guitarists x 5 styles (BN/Funk/Jazz/Rock/SS) x {comp, solo},
~3.05 hours, each with a hand-verified JAMS annotation. Attribution is required
by the licence; keep this docstring with the code.

Why this module exists
----------------------
The synth-trained chord model scores ~0.99 on held-out SYNTH but only ~36% on
real Lab-mode audio (vs the shipping DSP's ~56%). Synth accuracy transfers
nothing (see the "adversarial synth testing" lesson). GuitarSet is the first
corpus we have that is BOTH real audio AND truly labelled, so it can arbitrate
honestly. This module is the loader; `eval_guitarset.py` is the benchmark.

We use the **mono-mic** recordings (`audio_mono-mic.zip`), not the hexaphonic
pickup mix: a room mic is the closest available analogue of the app's phone-mic
capture path.

WHICH CHORD ANNOTATION (inspected, not assumed)
-----------------------------------------------
Every one of the 360 JAMS carries **two** `chord` namespace annotations, and
they NEVER agree (verified across all 360 files):

  index 0 — `data_source: ""`, no `annotation_rules`.
      The sheet-derived "instructed" changes. Vocabulary over the whole corpus
      is 42 distinct values, all of the form `<root>:{maj,min,7,hdim7}`.
      Every one reduces to majmin unambiguously.

  index 1 — `data_source: "Semi-automatic chord transcription with manual
      verification"`, `annotation_rules: "Chord sheet-informed symbolic chord
      transcription based on the included separate string note transcriptions
      with the chord segmentation and root derived from sheet music."`
      The performed-voicing transcription: 588 distinct values with
      inversions/extensions/omissions, e.g. `D#:sus2(7)/1`, `G#:maj6(2,b5,*5)/1`,
      and bare power chords `G#:(1,5)/1`.

**We take index 0 (the sheet-derived one)** — selected by its EMPTY `data_source`
via :data:`SHEET_DATA_SOURCE`, not by list position. Rationale:

  * It is a clean majmin-reducible vocabulary. Annotation 1 contains power
    chords `(1,5)` which have NO third at all; forcing those into a maj/min
    class would be a coin flip dressed up as ground truth (our `labels.py`
    fallback would silently call them major).
  * Both annotations have identical segmentation (same times/durations, same
    observation count) — annotation 1 adds no temporal resolution, only
    voicing detail our 25-class majmin head cannot represent anyway.
  * The model's target space IS majmin, so the instructed changes are the
    fairest statement of "what chord is sounding".

Both are exposed: `parse_jams(..., data_source=PERFORMED_DATA_SOURCE)` reads the
other one if a future round wants a richer vocabulary.

Coverage note: the sheet annotation covers **100.0%** of every take's duration
(0 gaps > 50 ms across all 360 files), so `N` (no-chord) frames essentially do
not occur in GuitarSet ground truth. `harte_to_class` still handles `N` because
the Harte vocabulary defines it and gaps are honoured by the frame builder.

Pure stdlib + NumPy — no `jams` package (it is a heavy, unmaintained dep and we
only need two fields), no TensorFlow. Runs on the ARM dev box.
"""
from __future__ import annotations

import json
import os
import re
import sys
import zipfile
from typing import List, Optional, Sequence, Tuple

import numpy as np

# `chords.labels` / `chords.frames` are siblings. Support both
# `python3 ml/chords/test_guitarset.py` (this dir on the path) and
# `import chords.guitarset` from the ml/ root — same shim as frames.py.
try:  # pragma: no cover - import shim
    from chords import frames, labels
except Exception:  # pragma: no cover - import shim
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import frames  # type: ignore
    import labels  # type: ignore

# --------------------------------------------------------------------------- #
# Zenodo source (module constants — the CI cache key is derived from these)
# --------------------------------------------------------------------------- #
ZENODO_RECORD = 3371780
ZENODO_BASE = f"https://zenodo.org/records/{ZENODO_RECORD}/files"
LICENSE = "CC-BY-4.0"
CITATION = (
    "Q. Xi, R. Bittner, J. Pauwels, X. Ye, J. P. Bello. 'GuitarSet: A Dataset "
    "for Guitar Transcription', ISMIR 2018. Zenodo record 3371780 (CC-BY-4.0)."
)

ANNOTATION_ZIP = "annotation.zip"          # ~39 MB — 360 JAMS
AUDIO_MIC_ZIP = "audio_mono-mic.zip"       # ~657 MB — mono room-mic renders
AUDIO_PICKUP_ZIP = "audio_mono-pickup_mix.zip"  # ~683 MB — NOT used (see above)

#: Files `download()` fetches, and the basis of the CI cache key.
REQUIRED_ZIPS = (ANNOTATION_ZIP, AUDIO_MIC_ZIP)

#: Subdirectories the zips extract into, relative to the dataset root.
ANNOTATION_DIR = "annotation"
AUDIO_MIC_DIR = "audio_mono-mic"

#: Mic WAVs are named `<stem>_mic.wav` against a `<stem>.jams`.
MIC_SUFFIX = "_mic.wav"

#: `annotation_metadata.data_source` of the sheet-derived ("instructed") chord
#: annotation — the one we evaluate against. Empty string, verified over all 360.
SHEET_DATA_SOURCE = ""
#: ...and of the performed-voicing transcription (selectable, not the default).
PERFORMED_DATA_SOURCE = "Semi-automatic chord transcription with manual verification"

#: `<guitaristId>_<style><n>-<tempo>-<key>_<comp|solo>` — e.g. 03_SS1-100-C#_comp
_STEM_RE = re.compile(
    r"^(?P<gid>\d+)_(?P<style>[A-Za-z]+)(?P<n>\d+)"
    r"-(?P<tempo>\d+)-(?P<key>[A-G][b#]?)_(?P<mode>comp|solo)$"
)

#: A chord observation: (start_seconds, duration_seconds, harte_label).
Segment = Tuple[float, float, str]
#: A track: (wav_path, jams_path, guitarist_id).
Track = Tuple[str, str, str]


def default_root() -> str:
    """Dataset root: $GUITARSET_ROOT, else ml/data/guitarset."""
    env = os.environ.get("GUITARSET_ROOT")
    if env:
        return env
    ml_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(ml_dir, "data", "guitarset")


# --------------------------------------------------------------------------- #
# Download
# --------------------------------------------------------------------------- #
def _extracted_marker(dest: str, zip_name: str) -> str:
    """Directory whose existence means `zip_name` is already extracted."""
    return os.path.join(
        dest, ANNOTATION_DIR if zip_name == ANNOTATION_ZIP else AUDIO_MIC_DIR)


def download(dest: Optional[str] = None,
             zips: Sequence[str] = REQUIRED_ZIPS) -> str:
    """Fetch + extract the GuitarSet zips into `dest`. Idempotent.

    Skips any zip whose extraction directory already holds files (so a warm CI
    cache costs nothing) and deletes each archive after extracting to keep the
    runner's disk small. Returns the dataset root.

    NOTE the zips do not all wrap their contents in a folder, so we extract each
    into its OWN subdirectory (`annotation/`, `audio_mono-mic/`) and let
    `tracks()` glob recursively — that is robust either way.
    """
    import urllib.request

    dest = dest or default_root()
    os.makedirs(dest, exist_ok=True)
    for zip_name in zips:
        out_dir = _extracted_marker(dest, zip_name)
        if os.path.isdir(out_dir) and os.listdir(out_dir):
            print(f"[guitarset] {zip_name}: already extracted -> {out_dir}")
            continue
        url = f"{ZENODO_BASE}/{zip_name}?download=1"
        zip_path = os.path.join(dest, zip_name)
        if not os.path.exists(zip_path):
            print(f"[guitarset] downloading {url}", flush=True)
            urllib.request.urlretrieve(url, zip_path)
        print(f"[guitarset] extracting {zip_name} -> {out_dir}", flush=True)
        os.makedirs(out_dir, exist_ok=True)
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(out_dir)
        os.remove(zip_path)
    return dest


# --------------------------------------------------------------------------- #
# Parsing
# --------------------------------------------------------------------------- #
def parse_stem(stem: str):
    """`00_BN1-129-Eb_comp` -> dict(gid, style, n, tempo, key, mode) or None.

    `style` is the letters only (BN/Funk/Jazz/Rock/SS); `n` is the take index.
    `mode` is comp|solo — the RECORDING mode, not the key's major/minor mode
    (that lives in the JAMS `key_mode` namespace).
    """
    m = _STEM_RE.match(stem)
    if not m:
        return None
    return {
        "gid": m.group("gid"),
        "style": m.group("style"),
        "n": int(m.group("n")),
        "tempo": int(m.group("tempo")),
        "key": m.group("key"),
        "mode": m.group("mode"),
    }


def parse_jams(path: str, data_source: str = SHEET_DATA_SOURCE):
    """Read one GuitarSet JAMS.

    Returns ``(guitarist_id, style, tempo, key, mode, segments)`` where
    ``segments`` is a time-sorted list of ``(start_s, duration_s, harte_label)``
    from the chord annotation whose ``annotation_metadata.data_source`` equals
    ``data_source`` (default: the sheet-derived one — see the module docstring
    for why). ``tempo`` is int BPM, ``key`` the tonic (e.g. ``"Eb"``), ``mode``
    is ``"comp"``/``"solo"``.

    Metadata comes from the FILENAME stem (the canonical GuitarSet naming); it
    agrees with the JAMS `tempo`/`key_mode` namespaces on every file, and the
    filename is the only place the comp/solo mode is recorded.

    Raises ValueError on an unparseable stem or a missing chord annotation, so a
    corrupt/renamed file fails loudly instead of silently scoring 0.
    """
    stem = os.path.basename(path)
    if stem.endswith(".jams"):
        stem = stem[: -len(".jams")]
    meta = parse_stem(stem)
    if meta is None:
        raise ValueError(f"unparseable GuitarSet stem: {stem!r}")

    with open(path) as fh:
        doc = json.load(fh)

    chords = [a for a in doc.get("annotations", [])
              if a.get("namespace") == "chord"]
    if not chords:
        raise ValueError(f"{stem}: no chord annotation in JAMS")
    picked = [a for a in chords
              if (a.get("annotation_metadata") or {}).get("data_source", "")
              == data_source]
    if not picked:
        avail = [(a.get("annotation_metadata") or {}).get("data_source", "")
                 for a in chords]
        raise ValueError(
            f"{stem}: no chord annotation with data_source={data_source!r} "
            f"(available: {avail!r})")
    # All 360 files have exactly one annotation per data_source; if a future
    # release adds more, prefer the one with the most observations.
    ann = max(picked, key=lambda a: len(a.get("data", [])))

    segs: List[Segment] = [
        (float(o["time"]), float(o["duration"]), str(o["value"]))
        for o in ann.get("data", [])
    ]
    segs.sort(key=lambda s: s[0])
    return (meta["gid"], meta["style"], meta["tempo"], meta["key"],
            meta["mode"], segs)


def harte_to_class(label: str) -> int:
    """Harte chord label -> 25-class majmin index (0..24).

    Delegates to :func:`chords.labels.to_majmin_class` — the ONE mapping the
    trained model's target space is defined by. This wrapper exists to name the
    GuitarSet-facing contract and to document the reduction rules, NOT to add a
    second vocabulary. Verified against GuitarSet's full 42-value sheet
    vocabulary and its 588-value performed vocabulary:

      ``C#:maj``/``C#``        -> major class of the root
      ``A:min``               -> minor class of the root
      ``A:7``, ``F:maj7``,
      ``G:sus4``, ``E:aug``   -> MAJOR (major third, or no third -> major by
                                 the MIREX majmin convention)
      ``B:hdim7``, ``B:dim``,
      ``C:min7``, ``C:minmaj7`` -> MINOR (minor third)
      ``F:maj/5``, ``C:maj/3`` -> the quality decides, the bass is ignored
      ``G#:(1,5)`` (power chord, NO third) -> major (documented fallback; a
                                 reason we evaluate the sheet annotation, which
                                 never contains these)
      ``N`` / ``X`` / ``""``   -> 0 (no chord)
    """
    return labels.to_majmin_class(label)


def tracks(root: Optional[str] = None) -> List[Track]:
    """Pair mic WAVs to JAMS: sorted list of ``(wav_path, jams_path, gid)``.

    Globs both trees recursively (the zips' internal layout is not relied upon)
    and joins on the stem: `<stem>_mic.wav` <-> `<stem>.jams`. Only tracks with
    BOTH files and a parseable stem are returned, so a partial download yields a
    smaller — never a wrong — evaluation set.
    """
    import glob

    root = root or default_root()
    jams_by_stem = {}
    for p in glob.glob(os.path.join(root, "**", "*.jams"), recursive=True):
        jams_by_stem[os.path.basename(p)[: -len(".jams")]] = p

    out: List[Track] = []
    for wav in glob.glob(os.path.join(root, "**", "*" + MIC_SUFFIX),
                         recursive=True):
        stem = os.path.basename(wav)[: -len(MIC_SUFFIX)]
        jams = jams_by_stem.get(stem)
        meta = parse_stem(stem)
        if jams is None or meta is None:
            continue
        out.append((wav, jams, meta["gid"]))
    out.sort()
    return out


# --------------------------------------------------------------------------- #
# Frame labels
# --------------------------------------------------------------------------- #
def frame_labels(segments: Sequence[Segment], n_frames: int,
                 hop: int, sr: int) -> np.ndarray:
    """Per-frame majmin classes (int32, ``(n_frames,)``) from timed segments.

    Uses the SAME frame-centre convention as the training label path
    (``frames.frame_center_time``: frame ``i`` is sampled at
    ``(i*hop + hop/2)/sr``) so predictions and ground truth land on one grid.

    Unlike ``frames.frame_labels`` — which takes strum ONSETS and sustains each
    chord to the next onset — GuitarSet gives explicit ``duration``s, so we
    honour them: a frame centre outside every segment is N.C. (0). On GuitarSet
    the two agree anyway (the sheet annotation is gapless), but respecting the
    stated durations keeps trailing audio past the last chord from being scored
    as that chord.
    """
    n = max(0, int(n_frames))
    out = np.zeros(n, dtype=np.int32)
    if n == 0 or not segments:
        return out

    segs = sorted(segments, key=lambda s: s[0])
    starts = np.asarray([s[0] for s in segs], dtype=np.float64)
    ends = np.asarray([s[0] + s[1] for s in segs], dtype=np.float64)
    classes = np.asarray([harte_to_class(s[2]) for s in segs], dtype=np.int32)

    centers = (np.arange(n, dtype=np.float64) * hop + hop / 2.0) / sr
    # Latest segment starting at or before the frame centre...
    idx = np.searchsorted(starts, centers, side="right") - 1
    valid = idx >= 0                       # frames before the first segment -> N.C.
    safe = np.where(valid, idx, 0)         # keep gather in-bounds; masked below
    inside = valid & (centers < ends[safe])  # ...and the centre is still inside it
    out[inside] = classes[safe[inside]]
    return out


def labels_for_jams(jams_path: str, n_frames: int, hop: int, sr: int,
                    data_source: str = SHEET_DATA_SOURCE) -> np.ndarray:
    """Convenience: `parse_jams` + `frame_labels` for one take."""
    _, _, _, _, _, segs = parse_jams(jams_path, data_source=data_source)
    return frame_labels(segs, n_frames, hop, sr)


if __name__ == "__main__":  # pragma: no cover - manual inspection helper
    root = sys.argv[1] if len(sys.argv) > 1 else default_root()
    ts = tracks(root)
    print(f"[guitarset] root={root}  tracks={len(ts)}")
    if ts:
        wav, jams, gid = ts[0]
        gid, style, tempo, key, mode, segs = parse_jams(jams)
        print(f"[guitarset] {os.path.basename(wav)}: guitarist={gid} "
              f"style={style} tempo={tempo} key={key} mode={mode} "
              f"segments={len(segs)}")
        for s in segs[:6]:
            print(f"    {s[0]:6.2f}s +{s[1]:5.2f}s  {s[2]:12s} "
                  f"-> class {harte_to_class(s[2])}")
    print(f"[guitarset] {CITATION}")
