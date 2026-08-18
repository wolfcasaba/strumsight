"""Regression guard for the E07-R21 self-heal (ADR 0112, halt H2, 2026-08-18).

Measured root cause of the halt: the PREPARED E07-R21 brief (written
2026-08-15, before E07-R18 was implemented) assumes plan activation is a
step the presentation layer can defer until the learner explicitly confirms
a preview. E07-R18's actual, merged `GenerationOrchestrator._run()` fuses
assembly, validation, repair, and activation into ONE atomic call:
`generate()` calls `activation.activate(activePlan)` as its own terminal
effect (`generation_orchestrator.dart:150-154`), and the already-green
`generation_orchestrator_test.dart` (A2-late, A5, A6) asserts exactly this --
a successful `generate()` always leaves `activation.calls == 1` and returns a
plan with `status == PlanStatus.active`. There is no existing seam that
returns a validated-but-not-yet-active plan.

The halted round's own pre-flight measured this contradiction correctly
(`rg -n -C 3 'final activePlan = plan.copyWith(...)|await
activation.activate(...)'
lib/features/practice_generator/application/service/generation_orchestrator.dart`
-> lines 150-154) and concluded the fix required touching R21's forbidden
zone -- the generator's application layer -- then halted H2 for a human
decision (widen R18's activation boundary in a new round/ADR, or narrow R21
to a non-integrated preview component).

That conclusion over-reaches the same way the E07-R19/H3 halt did (see
test_e07_r19_repository_contract_scope.py): every one of R21's own
acceptance criteria (A1-A8) is satisfiable by a PlanPreviewController that
never calls GenerationOrchestrator/PlanGeneratorController at all -- it
operates on an already-built AdaptivePracticePlan it is given, revalidates
edits through the existing, unmodified PlanValidator (already exported via
public.dart), and takes the EXISTING GenerationPlanActivation interface
(also already exported via public.dart) as its own confirm-time dependency,
instead of inventing a new type or importing/modifying anything else in
application/**. Wiring that dependency to the real orchestrator -- which
still cannot produce a pre-activation checkpoint result today -- is explicit
follow-up work for a later round, not this one.

This guard locks in the facts that resolution depends on, so the same halt
cannot silently return:

  * generate() still fuses activation into the terminal effect of a
    successful run (if a future round decouples them, this test turns red
    ON PURPOSE, because R21's §0.0 assumption -- "the real orchestrator
    cannot be reused directly this round" -- would need a fresh look, not a
    silent drift);
  * GenerationPlanActivation is still declared and still exported exactly
    where the brief's §0.0 says it is, so the presentation layer can keep
    depending on it by type without importing anything else from
    application/**;
  * the brief's §0.0 documents the resolution and keeps `allowed_paths`
    byte-for-byte unchanged, and ADR 0266 carries the dated clarification
    that its "no partial activation" decision does not mandate R18's choice
    to auto-activate a *complete* plan.
"""

import re
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief

REPO_ROOT = Path(__file__).resolve().parents[2]
ORCHESTRATOR = (
    REPO_ROOT
    / "lib"
    / "features"
    / "practice_generator"
    / "application"
    / "service"
    / "generation_orchestrator.dart"
)
ORCHESTRATOR_TEST = (
    REPO_ROOT
    / "test"
    / "features"
    / "practice_generator"
    / "application"
    / "generation_orchestrator_test.dart"
)
PUBLIC_BARREL = (
    REPO_ROOT / "lib" / "features" / "practice_generator" / "public.dart"
)
BRIEF = REPO_ROOT / "docs" / "rounds" / "e07-r21-plan-preview-and-explanation.md"
ADR_0266 = (
    REPO_ROOT
    / "docs"
    / "adr"
    / "0266-generation-orchestration-and-no-partial-activation.md"
)

# The brief's allowed_paths before AND after this self-heal -- the fix must
# not add a single entry (ADR 0112 §3, and the E07-R19 precedent: prefer
# brief clarification over scope-widening when one is honestly available).
ORIGINAL_ALLOWED_PATHS = (
    "lib/features/practice_generator/presentation/screens/plan_preview_screen.dart",
    "lib/features/practice_generator/presentation/widgets/plan_day_card.dart",
    "lib/features/practice_generator/presentation/widgets/plan_block_card.dart",
    "lib/features/practice_generator/presentation/widgets/plan_reason_sheet.dart",
    "lib/features/practice_generator/presentation/controller/plan_preview_controller.dart",
    "lib/l10n/app_en.arb",
    "lib/l10n/app_hu.arb",
    "lib/features/practice_generator/public.dart",
    "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
    "test/features/practice_generator/presentation/plan_reason_sheet_test.dart",
    "docs/rounds/e07-r21-plan-preview-and-explanation.md",
)


class E07R21ActivationBoundaryScopeTest(unittest.TestCase):
    def test_generate_still_fuses_activation_as_its_terminal_effect(self) -> None:
        """Forcing function, not a regression: if a later round gives
        generate() a pre-activation checkpoint, this must be noticed and
        R21's §0.0 resolution re-examined deliberately, not silently
        outdated."""
        lines = ORCHESTRATOR.read_text(encoding="utf-8").splitlines()
        copy_active = next(
            (
                i
                for i, line in enumerate(lines)
                if "plan.copyWith(status: PlanStatus.active)" in line
            ),
            None,
        )
        activate_call = next(
            (
                i
                for i, line in enumerate(lines)
                if "await activation.activate(activePlan)" in line
            ),
            None,
        )
        self.assertIsNotNone(
            copy_active, "generate() no longer builds an active-status plan copy"
        )
        self.assertIsNotNone(
            activate_call, "generate() no longer calls activation.activate(...)"
        )
        self.assertLess(
            copy_active,
            activate_call,
            "activation.activate(...) must still follow the active-status copy "
            "inside the same generate() run",
        )
        self.assertLessEqual(
            activate_call - copy_active,
            10,
            "the active-status copy and the activation call have drifted apart "
            "-- re-check whether generate() still activates unconditionally",
        )

    def test_orchestrator_test_still_requires_activation_on_success(self) -> None:
        """Locks in that R18's own, already-green test still treats a
        successful generate() as activation having happened -- the exact
        contract R21 must not silently assume it can bypass in-process."""
        text = ORCHESTRATOR_TEST.read_text(encoding="utf-8")
        self.assertIn("activation.calls, 1", text)
        self.assertIn("PlanStatus.active", text)

    def test_generation_plan_activation_stays_public_and_reusable(self) -> None:
        text = ORCHESTRATOR.read_text(encoding="utf-8")
        self.assertRegex(
            text, r"abstract interface class GenerationPlanActivation\b"
        )
        barrel = PUBLIC_BARREL.read_text(encoding="utf-8")
        self.assertIn(
            "export 'application/service/generation_orchestrator.dart';", barrel
        )
        self.assertIn("export 'domain/service/plan_validator.dart';", barrel)

    def test_allowed_paths_unchanged_no_application_widening(self) -> None:
        """The one forbidden exit from H2: widening allowed_paths into the
        generator's application layer instead of composing against its
        already-public GenerationPlanActivation/PlanValidator contracts."""
        allowed = load_brief(BRIEF).metadata.allowed_paths
        self.assertEqual(
            allowed,
            ORIGINAL_ALLOWED_PATHS,
            "E07-R21 H2 must resolve by brief clarification, not by widening "
            "allowed_paths into the forbidden application-layer zone "
            "(ADR 0112 §3)",
        )

    def test_brief_documents_the_h2_resolution(self) -> None:
        """RED before the self-heal (no §0.0 section exists yet on the
        PREPARED brief); GREEN once the resolution is recorded."""
        text = BRIEF.read_text(encoding="utf-8")
        self.assertRegex(text, r"(?m)^## 0\.0 Pre-flight rev")
        self.assertIn("GenerationPlanActivation", text)
        self.assertIn("PlanValidator", text)
        self.assertIn("ADR 0112", text)

    def test_adr_0266_documents_the_clarification(self) -> None:
        """RED before the self-heal; GREEN once ADR 0266 carries the dated
        amendment distinguishing 'no partial activation' from 'no automatic
        activation of a complete plan' -- the mischaracterization the R21
        brief's own frontmatter made."""
        text = ADR_0266.read_text(encoding="utf-8")
        self.assertRegex(text, r"(?m)^## M[oó]dos[ií]t[aá]s.*ADR 0112")
        self.assertIn("E07-R21", text)


if __name__ == "__main__":
    unittest.main()
