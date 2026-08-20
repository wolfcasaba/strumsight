"""A `practice_generator` generált barrel nem ütközési felület (E99-R18, ADR 0336).

Brief §4 mérce-mátrix:
  * két brief, mindkettő `lib/features/practice_generator/public.dart`  → NINCS ütközés
  * két brief, mindkettő `lib/features/x/public.dart`                     → ÜTKÖZÉS
  * két brief, mindkettő `lib/features/x/public/domain.dart`              → ÜTKÖZÉS

A `GENERATED_PATH_PATTERNS` kizárólag a ténylegesen migrált feature barreljét
tartja nyilván (E99-R18 §0.0c, ADR 0336): egy `public.dart` csak akkor
generált, ha a saját körében (a) fragmentum-forrás, (b) a generátor
frissességét mérő teszt, és (c) explicit nyilvántartási bejegyzés egyaránt
létezik. A korábbi `lib/features/*/public.dart` blanket glob ezt a hármas
bizonyítékot NEM pótolta, és a `SlotPlanningTest::test_real_epic_four_
rounds_are_correctly_rejected` regressziós őrt némította el (L343) — az
E04-R15/E04-R16 valódi, `lib/features/ai_tutor/public.dart`-ot érintő
ütközését engedte át.
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
    def test_pattern_matches_the_migrated_root_barrel(self) -> None:
        # E99-R18 pilot: only the barrel with fragment evidence is waived.
        self.assertTrue(
            is_generated_path("lib/features/practice_generator/public.dart")
        )

    def test_pattern_rejects_non_migrated_feature_root_barrels(self) -> None:
        # Second falsification cell (brief §4): any feature root barrel
        # that has NOT been migrated to fragment-driven generation remains
        # a full-value collision surface.
        self.assertFalse(is_generated_path("lib/features/x/public.dart"))
        self.assertFalse(is_generated_path("lib/features/ai_tutor/public.dart"))
        self.assertFalse(
            is_generated_path("lib/features/gamification/public.dart")
        )

    def test_pattern_rejects_fragment_files(self) -> None:
        # Fragments are NOT generated: they are the source of truth, and
        # any change in them must be visible to the slot planner.
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

    def test_pattern_registry_is_explicit_not_a_glob(self) -> None:
        # E99-R18 §0.0c / ADR 0336: a registry is a literal set, not a
        # blanket feature glob. A blanket glob would let every non-migrated
        # feature's `public.dart` slip through silently — exactly the
        # regression that turned the E04-R15/E04-R16 collision invisible
        # and prompted the H8 self-heal.
        self.assertEqual(
            GENERATED_PATH_PATTERNS,
            ("lib/features/practice_generator/public.dart",),
        )


class EffectivePathsFiltersGeneratedTest(unittest.TestCase):
    def test_migrated_barrel_is_dropped(self) -> None:
        self.assertEqual(
            effective_paths(
                ("lib/features/practice_generator/public.dart", "tool/ci/x.dart")
            ),
            frozenset({"tool/ci/x.dart"}),
        )

    def test_non_migrated_feature_barrel_is_kept(self) -> None:
        # Falsification cell: a non-migrated root barrel MUST stay in the
        # effective path set so two briefs touching it collide.
        self.assertEqual(
            effective_paths(("lib/features/ai_tutor/public.dart",)),
            frozenset({"lib/features/ai_tutor/public.dart"}),
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
    def test_two_briefs_touching_the_migrated_barrel_do_not_conflict(self) -> None:
        # Brief §4 NINCS ütközés case.
        a = effective_paths(("lib/features/practice_generator/public.dart",))
        b = effective_paths(("lib/features/practice_generator/public.dart",))
        self.assertEqual(paths_conflict(a, b), [])

    def test_two_briefs_touching_the_same_non_migrated_barrel_conflict(self) -> None:
        # Brief §4 ÜTKÖZÉS case (non-migrated barrel). The two briefs touch
        # the same hand-maintained `public.dart`; both must still see it as
        # an effective path and collide on it.
        a = effective_paths(("lib/features/x/public.dart",))
        b = effective_paths(("lib/features/x/public.dart",))
        self.assertEqual(
            paths_conflict(a, b),
            [(
                "lib/features/x/public.dart",
                "lib/features/x/public.dart",
            )],
        )

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

    def test_check_two_briefs_touching_the_migrated_barrel(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            brief_a = tmp_path / "e99-r01-gov-a.md"
            brief_b = tmp_path / "e99-r02-gov-b.md"
            self._write_brief(
                brief_a, ["lib/features/practice_generator/public.dart"]
            )
            self._write_brief(
                brief_b, ["lib/features/practice_generator/public.dart"]
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
                "two briefs touching only the migrated barrel must not "
                "collide (§4 NINCS ütközés)",
            )

    def test_check_two_briefs_touching_the_same_non_migrated_barrel(self) -> None:
        # Falsification: a non-migrated root barrel must still collide.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            brief_a = tmp_path / "e99-r05-gov-e.md"
            brief_b = tmp_path / "e99-r06-gov-f.md"
            self._write_brief(
                brief_a, ["lib/features/ai_tutor/public.dart"]
            )
            self._write_brief(
                brief_b, ["lib/features/ai_tutor/public.dart"]
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
                "two briefs touching the same non-migrated barrel must "
                "collide (§4 ÜTKÖZÉS)",
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
