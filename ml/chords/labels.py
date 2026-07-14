"""Chord-label <-> 25-class majmin index (ML chord track, phase 0.1).

The v1 vocabulary is the MIREX **majmin** space: N.C. + 12 major + 12 minor.
Index layout (stable — the Dart side and the exported model depend on it):

    0            = N.C.  (no chord)
    1 .. 12      = C, C#, D, ... B   MAJOR
    13 .. 24     = C, C#, D, ... B   MINOR

Any richer label (Cmaj7, G7, Dm7, Asus4, Bdim, Caug, F/A ...) reduces to its
majmin class by the quality's THIRD (the standard MIREX majmin reduction):
dim -> minor (minor third), aug/7/maj7/6/sus/add -> major, no recognisable
third -> major. This matches how the field trains the 25-class head; the richer
qualities stay alive in the shipped chroma `ChordDictionary` refiner (see plan).

Pure Python, no deps — runs anywhere (label mapping for the dataset builder).
"""
from __future__ import annotations

N_CLASSES = 25
NO_CHORD = 0

# Pitch-class index by name; enharmonics fold together.
_PC = {
    "C": 0, "B#": 0,
    "C#": 1, "Db": 1,
    "D": 2,
    "D#": 3, "Eb": 3,
    "E": 4, "Fb": 4,
    "F": 5, "E#": 5,
    "F#": 6, "Gb": 6,
    "G": 7,
    "G#": 8, "Ab": 8,
    "A": 9,
    "A#": 10, "Bb": 10,
    "B": 11, "Cb": 11,
}
_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# No-chord spellings seen in the wild (Klangio, Harte, MIREX).
_NO_CHORD_TOKENS = {"N", "N.C.", "NC", "X", "", "-"}


def _split_root(label: str) -> tuple[int, str]:
    """Return (pitch-class 0..11, remainder) or (-1, '') if unparseable."""
    s = label.strip()
    if len(s) >= 2 and s[1] in "#b":
        root, rest = s[:2], s[2:]
    elif s:
        root, rest = s[:1], s[1:]
    else:
        return -1, ""
    pc = _PC.get(root)
    return (-1, "") if pc is None else (pc, rest)


def _is_minor_third(rest: str) -> bool:
    """Does the quality suffix carry a MINOR third? (majmin reduction rule)."""
    r = rest
    # Strip a bass slash (inversion) — the third lives in the quality, not bass.
    r = r.split("/", 1)[0]
    # 'maj'/'M' means a MAJOR quality even though it contains 'm'.
    low = r.lower()
    if low.startswith("maj") or r.startswith("M"):
        return False
    # dim / diminished / half-diminished -> minor third.
    if low.startswith("dim") or low.startswith("o") or "hdim" in low or low.startswith("min"):
        return True
    # a leading 'm' (m, m7, m6, m9, mMaj7 already handled above) -> minor.
    if low.startswith("m"):
        return True
    return False


def to_majmin_class(label: str) -> int:
    """Chord label -> class index in 0..24. Unparseable -> N.C. (0)."""
    if label is None:
        return NO_CHORD
    s = label.strip()
    if s in _NO_CHORD_TOKENS or s.upper() in {"N", "N.C.", "NC", "X"}:
        return NO_CHORD
    pc, rest = _split_root(s)
    if pc < 0:
        return NO_CHORD
    return (13 + pc) if _is_minor_third(rest) else (1 + pc)


def transpose_class(cls: int, semitones: int) -> int:
    """Transpose a class by [semitones] (for +/- pitch-shift augmentation).
    N.C. is invariant; maj/min groups roll within themselves."""
    if cls == NO_CHORD:
        return NO_CHORD
    if 1 <= cls <= 12:
        return 1 + (cls - 1 + semitones) % 12
    return 13 + (cls - 13 + semitones) % 12


def class_to_label(cls: int) -> str:
    """Canonical label for a class index (0..24)."""
    if cls == NO_CHORD:
        return "N.C."
    if 1 <= cls <= 12:
        return _NAMES[cls - 1]
    if 13 <= cls <= 24:
        return _NAMES[cls - 13] + "m"
    raise ValueError(f"class out of range: {cls}")
