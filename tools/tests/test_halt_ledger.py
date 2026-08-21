"""Unit tests for the read-only halt ledger (ADR 0315)."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "halt-ledger.py"


class HaltLedgerTest(unittest.TestCase):
    """Every fixture is an isolated repository; the live halt corpus is untouched."""

    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self._temporary_directory.name)
        (self.repo / ".pipeline").mkdir()
        (self.repo / "docs").mkdir()
        self.addCleanup(self._temporary_directory.cleanup)

    def write_halts(self, code: str, count: int) -> None:
        for index in range(count):
            (self.repo / ".pipeline" / f"halted-{code}-{index}.txt").write_text(
                f"round=E99-R{index:02d}\nhalt={code}\nhalted_at=2026-08-20T00:00:00Z\n",
                encoding="utf-8",
            )

    def write_lessons(self, text: str = "") -> None:
        (self.repo / "docs" / "LESSONS.md").write_text(text, encoding="utf-8")

    def run_ledger(self, output_format: str = "json") -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(TOOL), "--repo", str(self.repo), "--format", output_format],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )

    def json_report(self) -> list[dict[str, object]]:
        completed = self.run_ledger()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)["halt_classes"]

    def row(self, code: str) -> dict[str, object]:
        return next(item for item in self.json_report() if item["halt"] == code)

    def test_a_guard_test_covers_a_repeated_halt_class(self) -> None:
        self.write_halts("H8", 3)
        self.write_lessons(
            "## L1 — H8 recovery\n\n"
            "The H8 incident has a regression guard.\n"
            "**Őrteszt:** tools/tests/x.py::H8GuardTest\n"
        )

        report = self.row("H8")

        self.assertEqual(report["occurrences"], 3)
        self.assertEqual(report["guard_tests"], ["tools/tests/x.py::H8GuardTest"])
        self.assertEqual(report["status"], "fedett")
        self.assertFalse(report["warning"])

    def test_a_repeated_class_without_a_guard_is_missing(self) -> None:
        self.write_halts("H6", 3)
        self.write_lessons("## L2 — H6 was measured\n\nNo machine-readable guard yet.\n")

        report = self.row("H6")

        self.assertEqual(report["status"], "hiányzik")
        self.assertTrue(report["warning"])
        self.assertEqual(report["guard_tests"], [])

    def test_an_explicit_no_guard_decision_counts_as_covered(self) -> None:
        self.write_halts("H2", 2)
        self.write_lessons(
            "## L3 — H2 exception\n\n"
            "**Őrteszt:** nincs — human decision is required\n"
        )

        report = self.row("H2")

        self.assertEqual(report["status"], "fedett")
        self.assertFalse(report["warning"])
        self.assertEqual(report["guard_tests"], ["nincs — human decision is required"])

    def test_a_similar_halt_code_does_not_cover_the_class(self) -> None:
        self.write_halts("H3", 3)
        self.write_lessons(
            "## L4 — H30 is unrelated\n\n"
            "**Őrteszt:** tools/tests/x.py::H30GuardTest\n"
        )

        report = self.row("H3")

        self.assertEqual(report["status"], "hiányzik")
        self.assertEqual(report["guard_tests"], [])

    def test_empty_input_is_an_empty_markdown_report_and_still_succeeds(self) -> None:
        self.write_lessons("")

        completed = self.run_ledger("markdown")

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("# Halt-főkönyv", completed.stdout)
        self.assertIn("Nincs halt-rekord.", completed.stdout)

    def test_json_and_markdown_reports_expose_the_same_halt_fields(self) -> None:
        self.write_halts("H-GATEGUARD", 2)
        self.write_lessons("## L5 — H-GATEGUARD\n\n")

        json_row = self.row("H-GATEGUARD")
        markdown = self.run_ledger("markdown")

        self.assertEqual(
            set(json_row),
            {"halt", "occurrences", "guard_tests", "status", "warning"},
        )
        self.assertEqual(markdown.returncode, 0, markdown.stderr)
        self.assertIn("| H-GATEGUARD | 2 | — | hiányzik | igen |", markdown.stdout)

    def test_warning_threshold_is_one_two_and_five_occurrences(self) -> None:
        self.write_halts("H1", 1)
        self.write_halts("H2", 2)
        self.write_halts("H4", 5)
        self.write_lessons("")

        rows = {item["halt"]: item for item in self.json_report()}

        self.assertEqual(rows["H1"]["status"], "nem jelölt")
        self.assertFalse(rows["H1"]["warning"])
        self.assertEqual(rows["H2"]["status"], "hiányzik")
        self.assertTrue(rows["H2"]["warning"])
        self.assertEqual(rows["H4"]["status"], "hiányzik")
        self.assertTrue(rows["H4"]["warning"])


if __name__ == "__main__":
    unittest.main()
