"""A `lib/features/*/public.dart` generált barrel nem ütközési felület.

Brief §4 mérce-mátrix:
  * két brief, mindkettő `lib/features/x/public.dart`         → NINCS ütközés
  * két brief, mindkettő `lib/features/x/public/domain.dart`  → ÜTKÖZÉS

A szabályt glob-bal kell kifejezni (D4: nem fix lista), mert (a) a feature-
lista nem fix és (b) az E99-R17 l10n-mechanizmusa nem importálható.
"""

import importlib.util as importlib_util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(ROOT))

_round_slots_path = TOOLS / "round-slots.py"
_spec = importlib_util.spec_from_file_location(
    "_round_slots_for_test", _round_slots_path
)
round_slots = importlib_util.module_from_spec(_spec)
_spec.loader.exec_module(round_slots)
GENERATED_PATH_PATTERNS = round_slots.GENERATED_PATH_PATTERNS
effective_paths = round_slots.effective_paths
is_generated_path = round_slots.is_generated_path
main = round_slots.main
paths_conflict = round_slots.paths_conflict


class GeneratedBarrelPatternTest(unittest.TestCase):
    def test_pattern_matches_feature_root_barrel(self) -> None:
        self.assertTrue(
            is_generated_path("lib/features/practice_generator/public.dart")
        )
        self.assertTrue(is_generated_path("lib/features/x/public.dart"))

    def test_pattern_rejects_fragment_files(self) -> None:
        self.assertFalse(
            is_generated_path("lib/features/practice_generator/public/domain.dart")
        )
        self.assertFalse(
            is_generated_path("lib/features/practice_generator/public/data.dart")
        )

    def test_pattern_rejects_other_dart_files(self) -> None:
        self.assertFalse(
            is_generated_path(
                "lib/features/practice_generator/application/port/a.dart"
            )
        )
        self.assertFalse(is_generated_path("lib/features/practice_generator/public.dart.bak"))
        self.assertFalse(is_generated_path("tool/gen_public_barrel.dart"))

    def test_pattern_glob_is_not_narrowed_to_a_single_feature(self) -> None:
        # Second falsification cell (brief §4): narrowing the glob to a
        # single feature must let another feature's generated barrel become
        # a collision again. Since the pattern is the one shipped, we assert
        # it is the broad glob the brief mandates.
        self.assertEqual(
            GENERATED_PATH_PATTERNS,
            ("lib/features/*/public.dart",),
        )


class EffectivePathsFiltersGeneratedTest(unittest.TestCase):
    def test_generated_barrel_is_dropped(self) -> None:
        self.assertEqual(
            effective_paths(("lib/features/x/public.dart", "tool/ci/x.dart")),
            frozenset({"tool/ci/x.dart"}),
        )

    def test_fragment_paths_are_kept(self) -> None:
        self.assertEqual(
            effective_paths(("lib/features/x/public/domain.dart",)),
            frozenset({"lib/features/x/public/domain.dart"}),
        )

    def test_serialized_paths_still_dropped(self) -> None:
        self.assertEqual(
            effective_paths(("HANDOFF.md", "docs/LESSONS.md")),
            frozenset(),
        )


class PathsConflictGeneratedTest(unittest.TestCase):
    def test_two_briefs_touching_the_same_barrel_do_not_conflict(self) -> None:
        # Brief §4 NINCS ütközés case.
        a = effective_paths(("lib/features/x/public.dart",))
        b = effective_paths(("lib/features/x/public.dart",))
        self.assertEqual(paths_conflict(a, b), [])

    def test_two_briefs_touching_the_same_fragment_do_conflict(self) -> None:
        # Brief §4 ÜTKÖZÉS case.
        a = effective_paths(("lib/features/x/public/domain.dart",))
        b = effective_paths(("lib/features/x/public/domain.dart",))
        self.assertEqual(
            paths_conflict(a, b),
            [(
                "lib/features/x/public/domain.dart",
                "lib/features/x/public/domain.dart",
            )],
        )

    def test_barrel_plus_other_work_does_not_conflict_via_prefix(self) -> None:
        # The barrel path is filtered, so unrelated work next to the barrel
        # must not be flagged as a prefix collision.
        a = effective_paths(("lib/features/x/public/domain.dart",))
        b = frozenset()
        self.assertEqual(paths_conflict(a, b), [])


class MainSubcommandGeneratedBarrelTest(unittest.TestCase):
    """End-to-end check on real briefs written by the helper."""

    def _write_brief(self, path: Path, allowed: list[str]) -> None:
        # The ai-router block is TOML; double quotes only. The filename must
        # contain an `E##-R##` task id (load_brief's contract). gate_tests
        # must be non-empty per the schema validator.
        joined = ",\n  ".join(f'"{entry}"' for entry in allowed)
        path.write_text(
            "```ai-router\n"
            "schema_version = 1\n"
            'risk = "high"\n'
            f"allowed_paths = [\n  {joined}\n]\n"
            'gate_tests = ["test/foo_test.dart"]\n'
            "native_gate = false\n"
            "```\n",
            encoding="utf-8",
        )

    def test_check_two_briefs_touching_the_same_barrel(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            brief_a = tmp_path / "e99-r01-gov-a.md"
            brief_b = tmp_path / "e99-r02-gov-b.md"
            self._write_brief(
                brief_a, ["lib/features/x/public.dart"]
            )
            self._write_brief(
                brief_b, ["lib/features/x/public.dart"]
            )

            exit_code = main(
                [
                    "--repo",
                    str(ROOT),
                    "check",
                    "--brief",
                    str(brief_a),
                    "--brief",
                    str(brief_b),
                ],
            )
            self.assertEqual(
                exit_code,
                0,
                "two briefs touching only the generated barrel must not "
                "collide (§4 NINCS ütközés)",
            )

    def test_check_two_briefs_touching_the_same_fragment(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            brief_a = tmp_path / "e99-r03-gov-c.md"
            brief_b = tmp_path / "e99-r04-gov-d.md"
            self._write_brief(
                brief_a, ["lib/features/x/public/domain.dart"]
            )
            self._write_brief(
                brief_b, ["lib/features/x/public/domain.dart"]
            )

            exit_code = main(
                [
                    "--repo",
                    str(ROOT),
                    "check",
                    "--brief",
                    str(brief_a),
                    "--brief",
                    str(brief_b),
                ],
            )
            self.assertEqual(
                exit_code,
                1,
                "two briefs touching the same fragment must collide "
                "(§4 ÜTKÖZÉS)",
            )


if __name__ == "__main__":
    unittest.main()