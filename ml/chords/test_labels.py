"""Tests for the chord-label -> 25-class majmin mapper (phase 0.1)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from chords.labels import (  # noqa: E402
    NO_CHORD,
    class_to_label,
    to_majmin_class,
    transpose_class,
)


def test_plain_triads():
    assert to_majmin_class("C") == 1
    assert to_majmin_class("B") == 12
    assert to_majmin_class("Am") == 13 + 9  # A minor
    assert to_majmin_class("Cm") == 13


def test_no_chord_spellings():
    for tok in ["N", "N.C.", "NC", "X", "", "  "]:
        assert to_majmin_class(tok) == NO_CHORD


def test_klangio_word_form():
    # Klangio spells qualities as '<root>-major' / '<root>-minor'.
    assert to_majmin_class("C-major") == 1
    assert to_majmin_class("G-major") == 8
    assert to_majmin_class("A-minor") == to_majmin_class("Am")
    assert to_majmin_class("B-minor") == to_majmin_class("Bm")
    assert to_majmin_class("Bb-major") == to_majmin_class("A#")
    assert to_majmin_class("C#-major") == to_majmin_class("C#")
    assert to_majmin_class("F#-minor") == 13 + 6


def test_richer_qualities_reduce_by_third():
    # Major-third family -> major class of the root.
    assert to_majmin_class("Cmaj7") == 1
    assert to_majmin_class("G7") == to_majmin_class("G")
    assert to_majmin_class("C6") == 1
    assert to_majmin_class("Csus4") == 1  # no third -> major by convention
    assert to_majmin_class("Caug") == 1   # augmented has a MAJOR third
    # Minor-third family -> minor class of the root.
    assert to_majmin_class("Dm7") == to_majmin_class("Dm")
    assert to_majmin_class("Bdim") == to_majmin_class("Bm")  # dim third is minor
    # mMaj7 has a minor third -> minor.
    assert to_majmin_class("CmMaj7") == 13


def test_enharmonics_and_accidentals():
    assert to_majmin_class("Db") == to_majmin_class("C#")
    assert to_majmin_class("Bb") == to_majmin_class("A#")
    assert to_majmin_class("F#m") == 13 + 6
    assert to_majmin_class("Gbm") == to_majmin_class("F#m")


def test_slash_chords_use_the_quality_not_the_bass():
    # C/E is still C major, not E-anything.
    assert to_majmin_class("C/E") == 1
    assert to_majmin_class("Am/C") == to_majmin_class("Am")


def test_unparseable_is_no_chord():
    assert to_majmin_class("???") == NO_CHORD
    assert to_majmin_class("H7") == NO_CHORD  # H is not a pitch name here


def test_transpose_rolls_within_group():
    # C major +2 -> D major.
    assert transpose_class(to_majmin_class("C"), 2) == to_majmin_class("D")
    # B major +1 wraps to C major.
    assert transpose_class(to_majmin_class("B"), 1) == to_majmin_class("C")
    # A minor -3 -> F# minor.
    assert transpose_class(to_majmin_class("Am"), -3) == to_majmin_class("F#m")
    # N.C. is invariant.
    assert transpose_class(NO_CHORD, 5) == NO_CHORD
    # Full octave is identity.
    for c in range(25):
        assert transpose_class(c, 12) == c


def test_class_to_label_roundtrip():
    for lbl in ["N.C.", "C", "F#", "B", "Cm", "Am", "Bm"]:
        assert class_to_label(to_majmin_class(lbl)) == lbl


def test_every_class_reachable():
    seen = {to_majmin_class(class_to_label(c)) for c in range(25)}
    assert seen == set(range(25))


if __name__ == "__main__":
    import inspect
    fns = [v for k, v in sorted(globals().items())
           if k.startswith("test_") and inspect.isfunction(v)]
    for fn in fns:
        fn()
    print(f"ALL {len(fns)} LABEL TESTS PASSED")
