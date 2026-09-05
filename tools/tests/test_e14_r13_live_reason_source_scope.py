"""Regression guard for E14-R13 / H3 (ADR 0112 önjavító kör, 2026-09-05).

Measured on ``main @ b17e08ef``, still BEFORE any dispatch: the round's own
pre-flight halted because the 2026-08-20 pre-written brief (base
``main @ 88e08e65``) was not deliverable inside its own ``allowed_paths``, and
its §5.4 prescribed a SECOND reason taxonomy beside a meanwhile-merged closed
enum::

    sed -n '/^enum RecognitionRejectReason/,/^}/p' \\
        lib/features/live/domain/recognition/recognition_decision.dart
    #   -> lowConfidence unstable signalQuality noChord modelUnavailable timeout
    #      (SIX, closed — ADR 0505 D3/D6; the brief prescribed FOUR)

    grep -l '"liveWeakSignal"' lib/l10n/app_en.arb lib/l10n/base/app_en.arb
    #   -> both; the brief allowed only the GENERATED aggregate, not the source

    grep -rn "RecognitionRejectReason" lib/ --include=*.dart \\
      | grep -v "domain/recognition\\|model/live_frame\\|public.dart\\|live_pipeline"
    #   -> empty: ZERO UI consumers, so the round's actual goal is real

Widening ``allowed_paths`` is not the orchestrator's authority (ADR 0087 §2), so
the round could only halt — the third occurrence of the ``docs/LESSONS.md`` L636
class in this band off the same 88e08e65 base (E14-R10 heal 39680e1e, E14-R15
heal b17e08ef).

What this guard pins is the REQUIRED END STATE, never the absence of the
round's work (``docs/LESSONS.md`` L612): the l10n SOURCE segment is on the
list, the three tests whose assertions the round moves are on the list AND in
the gate, the §5 contract consumes the merged six-element enum instead of
minting a fourth-element rival, and the ADR number is the reserved one. Every
one of these holds before the round lands and stays true after it lands, so the
round's own success cannot turn its guard red. The §10/§11 sections — the only
parts the implementer and the reviewer fill in — are deliberately untouched by
every assertion here.

Measured red on the pre-revision brief: five of the six assertions fail.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = (
    REPO_ROOT / "docs" / "rounds" / "e14-r13-live-ui-truthfulness-hotfix.md"
)
QUEUE = REPO_ROOT / "docs" / "execution" / "pipeline-queue.tsv"
DECISION = (
    REPO_ROOT
    / "lib"
    / "features"
    / "live"
    / "domain"
    / "recognition"
    / "recognition_decision.dart"
)

# The ARB source segment (ADR 0307 §4). `lib/l10n/app_<locale>.arb` is the
# generated union — a round that may only touch the union cannot add a key.
L10N_SOURCES = (
    "lib/l10n/base/app_en.arb",
    "lib/l10n/base/app_hu.arb",
)

# The tests whose ASSERTIONS the reason banner moves. They are outside the
# original list, and every one of them must also RUN on the round's own gate
# (`docs/LESSONS.md` L593 / brief-lint S14) — otherwise the permission to touch
# them is unmeasured.
MOVED_PINS = (
    "test/features/live/live_stage_test.dart",
    "test/features/live/live_screen_test.dart",
    "test/ui/goldens/e13_r18_screens_golden_test.dart",
)

# The reserved number (.pipeline/inflight/adr/0520, round=E14-R13). The
# 2026-08-20 pre-allocation said 0365, which the reserver never hands out again.
RESERVED_ADR = "0520"
STALE_ADR = "0365"

SECTION_5 = re.compile(r"(?ms)^## 5\. .*?(?=^## 6\.)")


class LiveReasonSourceScope(unittest.TestCase):
    def setUp(self) -> None:
        self.text = BRIEF.read_text(encoding="utf-8")
        self.metadata = load_brief_metadata(BRIEF)
        self.allowed = set(self.metadata.allowed_paths)
        self.gate = set(self.metadata.gate_tests)

    def test_the_l10n_source_segment_is_on_the_list(self) -> None:
        """A kulcsfelvétel helye a FORRÁS, nem a generált aggregátum."""
        for source in L10N_SOURCES:
            self.assertIn(source, self.allowed, source)
            self.assertTrue((REPO_ROOT / source).is_file(), source)

    def test_the_moved_pins_are_allowed_and_gated(self) -> None:
        """Amit a kör elmozdít, azt futtatnia is kell (L593 / S14)."""
        for pin in MOVED_PINS:
            self.assertIn(pin, self.allowed, pin)
            self.assertIn(pin, self.gate, pin)
            self.assertTrue((REPO_ROOT / pin).is_file(), pin)

    def test_the_gate_command_mirrors_the_gate_tests(self) -> None:
        """A §7 parancssor futtatja a `gate_tests` MINDEN elemét (S12)."""
        for test in self.gate:
            self.assertIn(test, self.text, test)

    def test_the_contract_consumes_the_merged_six_element_enum(self) -> None:
        """A §5 a merge-elt szótárat fogyasztja, nem mint egy másodikat épít."""
        merged = re.search(
            r"(?ms)^enum RecognitionRejectReason \{(.*?)^\}",
            DECISION.read_text(encoding="utf-8"),
        )
        self.assertIsNotNone(merged, "a merge-elt enum eltűnt a fából")
        elements = re.findall(r"^  ([a-z][A-Za-z]*)[,;]$", merged.group(1), re.MULTILINE)
        self.assertEqual(len(elements), 6, elements)

        section = SECTION_5.search(self.text)
        self.assertIsNotNone(section, "a brief §5 szakasza nem található")
        body = section.group(0)
        self.assertIn("RecognitionRejectReason", body)
        # A `default:` ág tiltása AZ, ami a rivális taxonómiát kizárja: egy
        # jövőbeli enum-elem fordítási hibát ad, nem néma általánosítást.
        self.assertIn("kimerítő", body)
        self.assertIn("`default:` ág **TILOS**", body)
        # A mátrix a MERGE-ELT `values` fölött iterál, nem másolt cellákkal —
        # enélkül az „exhaustive" ígéret nem mérhető.
        self.assertIn("RecognitionRejectReason.values", self.text)

    def test_the_adr_number_is_the_reserved_one(self) -> None:
        """A foglaló a mérvadó — a 2026-08-20-i előre-kiosztás elavult.

        A §0.0 revízió SZÁNDÉKOSAN megnevezi a leváltott `0365`-öt (a történet
        nem íródik át), ezért nem a szám EMLÍTÉSE tilos, hanem a KÖTŐ alakja: a
        §5 fejléce és az „Előre kiosztott ADR" sor a foglalt számot hordozza.
        """
        self.assertIn(f"**Előre kiosztott ADR:** `{RESERVED_ADR}`", self.text)
        self.assertIn(
            f"## 5. Kötött architekturális döntések (ADR {RESERVED_ADR})", self.text
        )
        self.assertNotIn(f"(ADR {STALE_ADR})", self.text)
        self.assertNotIn(f"**Előre kiosztott ADR:** `{STALE_ADR}`", self.text)

        row = next(
            line.split("\t")
            for line in QUEUE.read_text(encoding="utf-8").splitlines()
            if line.startswith("E14-R13\t")
        )
        self.assertEqual(row[3], RESERVED_ADR, row)

    def test_the_forbidden_zone_still_covers_the_closed_enum(self) -> None:
        """A kör nem bővítheti a szótárat — az ADR 0505 D3 zárt szerződés."""
        self.assertNotIn(
            "lib/features/live/domain/recognition/recognition_decision.dart",
            self.allowed,
        )


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
