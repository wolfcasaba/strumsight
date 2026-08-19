"""Regression guard for the E07-R25 self-heal (ADR 0112, halt H3, 2026-08-19;
corrected under halt H5, 2026-08-19).

Measured root cause of the halt: the PREPARED E07-R25 brief's `allowed_paths`
lets the implementer write two new adapters
(`analysis_evidence_adapter.dart`, `vision_evidence_adapter.dart`) but no
port/model file that could give a Vision measurement a truthful provenance,
and no narrow Vision-owned contract that exposes a skill-scoped numeric value
without raw media. The round's own pre-flight (Terra, branch
`minimax/e07-r25-analysis-and-vision-evidence`, commit `faf1230`) measured and
recorded this half of the gap as ADR 0319: `EvidenceSource`
(`lib/features/practice_generator/domain/model/skill_evidence.dart:17-21`)
has only `learn`/`progress`/`analyzeV2`/`selfReport` -- no `vision` -- and the
only Vision cross-feature contract in scope reach
(`lib/features/vision/domain/integration/public.dart`, ADR 0193) carries no
skill-scoped numeric evidence type.

This self-heal measured a SECOND, independent gap ADR 0319 did not name:
`EvidenceWeightPolicy.sourceReliability`
(`lib/features/practice_generator/domain/policy/evidence_weight_policy.dart:66-71`)
switches on `EvidenceSource` with no `default` arm. Adding `vision` to the
enum without also touching this file does not halt the SAME round again --
it produces a fresh, less legible one: `flutter analyze` fails on a
non-exhaustive switch inside a file the brief still forbids editing. A
brief revision that stops at ADR 0319's own file list would trade one H3 for
another.

This guard locks in three things so neither halt can silently return:

  * the measured founding fact the widening depends on -- `EvidenceSource`
    still carries at least its original four values, and
    `evidence_weight_policy.dart`'s switch still has a matching arm for
    each of them, with no `default` arm (source: this test's own
    `EvidenceSource` value list and the arm-count regex below). This half
    is deliberately ONE-DIRECTIONAL -- see "Correction" below for why the
    other direction (no value beyond these four) cannot be pinned here;
  * the Vision types the new narrow contract is meant to re-export
    (`VisionEvidence`, `ObservationState`, `EvidenceMetric`,
    `EvidenceProvenance`) are declared where ADR 0319's follow-up assumes,
    and stay free of the raw-media fields ADR 0260 §1 forbids (landmark,
    frame, camera coordinate, file path);
  * the brief's `allowed_paths` now covers the model, policy, contract and
    test files the follow-up implementation needs, as a narrow *addition*
    to ADR 0319's own list -- not a blanket widening of
    `practice_generator/domain` or `vision/**`.

Correction (self-heal, halt H5, 2026-08-19): the first version of this
guard pinned `ORIGINAL_EVIDENCE_SOURCE_VALUES` with a full `assertEqual` in
both tests below, including the "no value/arm beyond these four" direction.
That is structurally incompatible with this repo's own round lifecycle --
the same failure class already measured once in
`tools/tests/test_e99_r13_runner_scope.py`'s own "Correction" section
(`docs/LESSONS.md` L279/L280, 2026-08-15): the E07-R25 round's implementer
went on to add the brief-sanctioned `EvidenceSource.vision` (this file's
own H3 widening) on its own, still-unmerged branch
(`minimax/e07-r25-analysis-and-vision-evidence`) -- which is, by
definition, always ahead of `main` while the round is in flight. Measured
(`gh run view 32206385772 --log-failed`, and independently reproduced in an
isolated heal worktree by overlaying the round branch's
`skill_evidence.dart`/`evidence_weight_policy.dart` uncommitted over a
plain `origin/main` checkout): Router CI failed on the round's own branch
because both assertions no longer equalled `main`'s actual 4-value state
once the branch's `vision` addition was in the checked-out tree. Widening
`ORIGINAL_EVIDENCE_SOURCE_VALUES` to 5 entries would "fix" the round branch
but break `main`'s OWN post-merge Router CI (main's tree genuinely has only
4 `EvidenceSource` values until the round actually merges) -- trading one
red for a worse one that blocks every future round dispatch, not just this
one (L279's exact failure mode). Both tests below now assert only the
non-redundant, branch-invariant half: none of the founding four may
silently disappear, or lose their `sourceReliability` arm.
`ORIGINAL_EVIDENCE_SOURCE_VALUES` itself is unchanged (still 4 entries --
it was not, and must not be, widened). The other direction (no
value/arm beyond a brief-sanctioned addition) is already covered,
branch-safely, by `test_allowed_paths_is_the_original_nine_plus_exactly_
five_new_entries` and `test_new_paths_are_in_scope_via_the_real_audit`
below (which files may change), plus Dart's own compiler: a switch arm
added for a value with no corresponding brief-approved file change is a
hard exhaustive-switch compile break, caught by `flutter analyze` in the
Full Gate, not by this Python test.
"""

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e07-r25-analysis-and-vision-evidence.md"

SKILL_EVIDENCE = (
    REPO_ROOT
    / "lib/features/practice_generator/domain/model/skill_evidence.dart"
)
EVIDENCE_WEIGHT_POLICY = (
    REPO_ROOT
    / "lib/features/practice_generator/domain/policy/evidence_weight_policy.dart"
)
VISION_EVIDENCE = REPO_ROOT / "lib/features/vision/domain/evidence/vision_evidence.dart"
VISION_OBSERVATION = (
    REPO_ROOT / "lib/features/vision/domain/evidence/vision_observation.dart"
)
EVIDENCE_PROVENANCE = (
    REPO_ROOT / "lib/features/vision/domain/evidence/evidence_provenance.dart"
)

# Measured 2026-08-19 on main @ 90df4d04 -- the exact, ordered value set the
# `EvidenceSource` enum and the `sourceReliability` switch both carry today.
ORIGINAL_EVIDENCE_SOURCE_VALUES = ("learn", "progress", "analyzeV2", "selfReport")

# The five files ADR 0319's own list omits or that this heal adds on top of
# it, beyond the nine paths the PREPARED brief already allowed.
NEW_ALLOWED_PATHS = (
    "lib/features/practice_generator/domain/model/skill_evidence.dart",
    "lib/features/practice_generator/domain/policy/evidence_weight_policy.dart",
    "lib/features/vision/domain/evidence/public.dart",
    "test/features/practice_generator/evidence/skill_evidence_test.dart",
    "test/features/practice_generator/skill_estimate/evidence_weight_policy_test.dart",
)

ORIGINAL_ALLOWED_PATHS = (
    "lib/features/practice_generator/application/port/analysis_evidence_reader.dart",
    "lib/features/practice_generator/application/port/vision_evidence_reader.dart",
    "lib/features/practice_generator/data/adapter/analysis_evidence_adapter.dart",
    "lib/features/practice_generator/data/adapter/vision_evidence_adapter.dart",
    "lib/features/practice_generator/public.dart",
    "test/features/practice_generator/evidence_integration/analysis_evidence_adapter_test.dart",
    "test/features/practice_generator/evidence_integration/vision_evidence_adapter_test.dart",
    "test/fixtures/practice_generator/evidence_integration/",
    "docs/rounds/e07-r25-analysis-and-vision-evidence.md",
)

# A plausible neighbour in each widened area that must stay OUT of scope --
# proves the fix is a named-file addition, not a directory-wide opening.
SIBLING_OUT_OF_SCOPE_PATHS = (
    # Sibling domain model, not the one this halt needs.
    "lib/features/practice_generator/domain/model/adaptive_practice_plan.dart",
    # Sibling Vision internals the narrow contract must not re-export.
    "lib/features/vision/domain/landmarks/hand_landmarks.dart",
)

PROTECTED = ()  # none of the candidate paths touch .ai/router.toml's protected_paths

_ENUM_VALUES_RE = re.compile(
    # Enhanced-enum value list ends at the first `;`, not the class's own
    # closing `}` -- the body continues past the values with a constructor
    # and methods (each containing commas of their own, e.g. named args).
    r"enum\s+EvidenceSource\s*\{([^;]*);",
    re.MULTILINE | re.DOTALL,
)
_SWITCH_ARMS_RE = re.compile(
    r"sourceReliability\(EvidenceSource source\)\s*=>\s*switch\s*\(source\)\s*\{([^}]*)\}",
    re.MULTILINE | re.DOTALL,
)

# Field/type names that would signal a raw-media leak if they ever appeared
# in the fused evidence types this heal plans to re-export narrowly (ADR
# 0260 §1, ADR 0319, L190/L193). None of these are declared today -- proven
# below, not assumed.
FORBIDDEN_RAW_MARKERS = (
    "Uint8List",
    "CameraImage",
    "NormalizedPoint",
    "HandLandmarks",
    "PoseLandmarks",
    "filePath",
    "framePath",
    "imagePath",
)


class E07R25VisionEvidenceScopeTest(unittest.TestCase):
    def test_evidence_source_still_has_the_original_four_values(self) -> None:
        """Deliberately one-directional: see the module docstring's
        "Correction" section for why asserting the OTHER direction -- no
        value beyond these four -- breaks `main`'s own Router CI the moment
        the round legitimately adds `vision` on its own, still-unmerged
        branch."""
        text = SKILL_EVIDENCE.read_text(encoding="utf-8")
        match = _ENUM_VALUES_RE.search(text)
        self.assertIsNotNone(match, "EvidenceSource enum body not found")
        values = tuple(
            re.match(r"\s*(\w+)", line).group(1)
            for line in match.group(1).split(",")
            if line.strip()
        )
        missing = [v for v in ORIGINAL_EVIDENCE_SOURCE_VALUES if v not in values]
        self.assertEqual(
            missing,
            [],
            f"EvidenceSource value(s) disappeared: {missing} -- "
            f"{SKILL_EVIDENCE.relative_to(REPO_ROOT)}",
        )

    def test_evidence_weight_policy_switch_still_covers_the_original_four(
        self,
    ) -> None:
        """Locks in the gap ADR 0319 itself did not name: this switch has no
        default arm, so it will fail to compile the moment `EvidenceSource`
        gains a value with no matching arm -- unless the arm's file is also
        brief-allowed. Deliberately one-directional over the arm set, for
        the same reason as
        test_evidence_source_still_has_the_original_four_values above
        (module docstring, "Correction")."""
        text = EVIDENCE_WEIGHT_POLICY.read_text(encoding="utf-8")
        match = _SWITCH_ARMS_RE.search(text)
        self.assertIsNotNone(
            match, "sourceReliability's switch expression not found or reshaped"
        )
        self.assertNotIn(
            "default",
            match.group(1),
            "sourceReliability already has a default arm -- the exhaustive-"
            "switch compile-break this heal widened allowed_paths for may "
            "no longer apply; re-check before trusting NEW_ALLOWED_PATHS",
        )
        arms = re.findall(r"EvidenceSource\.(\w+)\s*=>", match.group(1))
        missing = [v for v in ORIGINAL_EVIDENCE_SOURCE_VALUES if v not in arms]
        self.assertEqual(
            missing, [], f"sourceReliability arm(s) disappeared: {missing}"
        )

    def test_vision_evidence_types_exist_and_stay_raw_free(self) -> None:
        for source, must_declare in (
            (VISION_EVIDENCE, ("class VisionEvidence", "enum ObservationState")),
            (VISION_OBSERVATION, ("class EvidenceMetric", "enum EvidenceMetricFamily")),
            (EVIDENCE_PROVENANCE, ("class EvidenceProvenance", "class EvidenceWindow")),
        ):
            text = source.read_text(encoding="utf-8")
            for needle in must_declare:
                self.assertIn(
                    needle,
                    text,
                    f"{needle} no longer declared in "
                    f"{source.relative_to(REPO_ROOT)} -- the E07-R25 H3 "
                    "narrow-contract plan assumed this type's current shape",
                )
            for marker in FORBIDDEN_RAW_MARKERS:
                self.assertNotIn(
                    marker,
                    text,
                    f"{source.relative_to(REPO_ROOT)} now references "
                    f"{marker!r} -- this fused-evidence type is no longer "
                    "safe to re-export through a narrow public.dart "
                    "unchanged (ADR 0260 §1); re-evaluate before the "
                    "follow-up round proceeds",
                )

    def test_allowed_paths_is_the_original_nine_plus_exactly_five_new_entries(
        self,
    ) -> None:
        allowed = load_brief(BRIEF).metadata.allowed_paths
        self.assertEqual(
            set(allowed) - set(ORIGINAL_ALLOWED_PATHS),
            set(NEW_ALLOWED_PATHS),
            "E07-R25 H3 must resolve by adding exactly the model/policy/"
            "contract/test files the gap requires -- not a wider or "
            "narrower change to allowed_paths (ADR 0112 §3)",
        )
        self.assertEqual(
            set(ORIGINAL_ALLOWED_PATHS) - set(allowed),
            set(),
            "an original ADR-0319 allowed path was dropped; the self-heal "
            "must only ADD scope, never remove it",
        )

    def test_new_paths_are_in_scope_via_the_real_audit(self) -> None:
        root = self._make_repo()
        base = self._head(root)
        allowed = load_brief(BRIEF).metadata.allowed_paths

        for relative in NEW_ALLOWED_PATHS:
            audit = self._audit_untracked(root, base, relative, allowed)
            self.assertTrue(
                audit.ok,
                f"{relative} must be in scope after the E07-R25 H3 brief "
                f"revision -- got violations: {audit.violations}",
            )

    def test_sibling_paths_outside_the_new_grants_remain_out_of_scope(self) -> None:
        root = self._make_repo()
        base = self._head(root)
        allowed = load_brief(BRIEF).metadata.allowed_paths

        for relative in SIBLING_OUT_OF_SCOPE_PATHS:
            audit = self._audit_untracked(root, base, relative, allowed)
            self.assertFalse(
                audit.ok,
                f"{relative} unexpectedly fell in scope -- the H3 fix must "
                "widen allowed_paths narrowly (named files), not open the "
                "whole domain/model or vision/domain directory",
            )
            self.assertIn(f"path outside allowed scope: {relative}", audit.violations)

    def test_brief_documents_the_self_heal_resolution(self) -> None:
        """RED before this self-heal (no H3-widening section exists yet on
        top of ADR 0319's own §0.0); GREEN once the resolution is recorded."""
        text = BRIEF.read_text(encoding="utf-8")
        self.assertIn("0319", text)
        self.assertIn("evidence_weight_policy.dart", text)
        for path in NEW_ALLOWED_PATHS:
            self.assertIn(path, text)

    # -- helpers -----------------------------------------------------------

    def _make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "heal@example.invalid"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Heal Test"], cwd=root, check=True)
        (root / ".gitignore").write_text("build/\n")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
        return root

    def _head(self, root: Path) -> str:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
        ).stdout.strip()

    def _audit_untracked(self, root: Path, base: str, relative: str, allowed):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("placeholder\n")
        return audit_legacy_scope(root, base=base, allowed_paths=allowed, protected_paths=PROTECTED)


if __name__ == "__main__":
    unittest.main()
