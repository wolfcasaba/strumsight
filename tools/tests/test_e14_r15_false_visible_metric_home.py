"""Regression guard for E14-R15 / H3 (ADR 0112 önjavító kör, 2026-09-05).

Measured on ``main @ 8180c9dc``, still BEFORE any dispatch: the round's own
pre-flight halted because the 2026-08-20 pre-written brief prescribed a NEW,
standalone home for a metric whose canonical home had meanwhile been merged::

    grep -n "falseVisibleEventsPerMinute" \\
        lib/features/live/domain/evaluation/recognition_metrics.dart
    #   -> 731: the metric the brief's §2 declared missing (E14-R08 / ADR 0509)
    grep -n -A2 falseVisibleEventsPerMinute \\
        evaluation/recognition/recognition_release_gate.json
    #   -> 36-38: already gated at 2.0/min (E14-R09 / ADR 0511)
    sed -n '118,140p' docs/eval/recognition-dashboard.md
    #   -> ADR 0511 D8: "Mechanising any of these requires extending the
    #      E14-R08 harness (recognition_metrics.dart) with a genuinely scoped
    #      metric" — i.e. the scoped variant has exactly ONE decision site

The brief's ``allowed_paths`` did not contain that file; it named
``lib/features/live/domain/evaluation/false_visible_event_metric.dart``
instead. A round built to that list would have shipped a SECOND, competing
definition of the same Ch14 §7.2 line, next to the merged one — the
``docs/LESSONS.md`` L549 failure class that ADR 0511 D8 exists to prevent, and
the same class that halted E14-R10 (L636).

Why the existing rules were blind to the *resolution*: ``S15``
(``test_brief_base_sha_drift.py``) DID fire on this brief — it measures that the
pre-written base moved — but a stale-base finding is advisory: it says "re-read
and revise", not "this specific list is missing the one file the merged
contract names". Narrowing is the orchestrator's own authority; widening
``allowed_paths`` is not, so the round could only halt (H3).

What this guard pins is the REQUIRED END STATE, not the absence of the round's
work (``docs/LESSONS.md`` L612): the scoped false-visible metric must live in
the merged harness, and no competing standalone metric file may be opened for
it. Both hold before the round lands and stay true after it lands — the round's
own success cannot turn its guard red.

This guard is red on the pre-revision brief (measured: three of the four
assertions fail).
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief_metadata


REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = (
    REPO_ROOT
    / "docs"
    / "rounds"
    / "e14-r15-hard-negative-corpus-and-false-visible-metric.md"
)
QUEUE = REPO_ROOT / "docs" / "execution" / "pipeline-queue.tsv"
ADR_0511 = (
    REPO_ROOT
    / "docs"
    / "adr"
    / "0511-recognition-release-gate-and-single-source-report.md"
)

# ADR 0511 D8 names this file as the single extension point of a scoped
# recognition metric; its matrix cells live in the test beside it.
MERGED_METRIC_HOME = "lib/features/live/domain/evaluation/recognition_metrics.dart"
MERGED_METRIC_TEST = "test/features/live/evaluation/recognition_metrics_test.dart"

# A standalone Dart file whose name claims the same Ch14 §7.2 line is exactly
# the second decision site ADR 0511 D8 / L549 forbid.
COMPETING_METRIC_FILE = re.compile(r"(?i)false_?visible.*metric\.dart$")

# The reserved number (.pipeline/inflight/adr/0521, round=E14-R15). The
# 2026-08-20 pre-allocation said 0367, which the reserver never hands out
# again — the E14 band's real ADRs are 0505/0509/0511/0518.
RESERVED_ADR = "0521"
STALE_ADR = "0367"


def _round_row() -> list[str]:
    for line in QUEUE.read_text(encoding="utf-8").splitlines():
        if line.startswith("E14-R15\t"):
            return line.split("\t")
    raise AssertionError("no E14-R15 row in docs/execution/pipeline-queue.tsv")


class E14R15FalseVisibleMetricHomeTest(unittest.TestCase):
    def test_the_scoped_metric_is_built_in_the_merged_harness(self) -> None:
        metadata = load_brief_metadata(BRIEF)
        allowed = set(metadata.allowed_paths)

        self.assertEqual(
            {MERGED_METRIC_HOME, MERGED_METRIC_TEST} - allowed,
            set(),
            "ADR 0511 D8: a szűkített false-visible ráta EGYETLEN helye a "
            "merge-elt recognition_metrics.dart (+ a mátrix-cellái) — ha az "
            "allowed_paths nem tartalmazza, a kör csak második, versengő "
            "definíciót tud építeni (L549 / L636)",
        )
        self.assertIn(
            MERGED_METRIC_TEST,
            set(metadata.gate_tests),
            "a kiterjesztett harness mátrix-tesztjét a kapunak FUTTATNIA kell",
        )

    def test_no_second_decision_site_is_opened_for_the_ch14_false_visible_line(
        self,
    ) -> None:
        competing = sorted(
            path
            for path in load_brief_metadata(BRIEF).allowed_paths
            if path.startswith("lib/") and COMPETING_METRIC_FILE.search(path)
        )

        self.assertEqual(
            competing,
            [],
            "különálló false-visible metrika-fájl a merge-elt "
            f"{MERGED_METRIC_HOME} MELLETT — pontosan az a metrika/címke "
            "elcsúszás, amit az ADR 0511 D8 és az L549 néven nevez",
        )

    def test_the_merged_contract_still_names_that_single_extension_point(
        self,
    ) -> None:
        # The *why* of the two assertions above, read off the merged ADR
        # rather than restated here: if D8 is ever superseded, this cell is
        # the one that says so out loud.
        self.assertTrue(ADR_0511.is_file(), f"hiányzik: {ADR_0511}")
        self.assertIn(
            "recognition_metrics.dart",
            ADR_0511.read_text(encoding="utf-8"),
            "az ADR 0511 nem nevezi meg a kiterjesztési pontot — a fenti két "
            "cella indoklása elmozdult alóluk, nézd meg újra a D8-at",
        )

    def test_the_round_carries_its_reserved_adr_number(self) -> None:
        row = _round_row()
        brief_text = BRIEF.read_text(encoding="utf-8")

        self.assertEqual(
            row[3],
            RESERVED_ADR,
            "a sor ADR-oszlopa elavult előre-kiosztás; a foglaló "
            "(tools/round-slots.py reserve-adr) a mérvadó",
        )
        self.assertIn(
            RESERVED_ADR,
            brief_text,
            "a brief nem a lefoglalt ADR-számot hordozza",
        )
        self.assertNotIn(
            f"ADR {STALE_ADR}",
            brief_text,
            "a brief még az elavult 2026-08-20-i ADR-számra hivatkozik "
            "kötött döntésként",
        )


if __name__ == "__main__":
    unittest.main()
