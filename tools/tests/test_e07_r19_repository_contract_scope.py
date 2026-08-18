"""Regression guard for the E07-R19 self-heal (ADR 0112, halt H3, 2026-08-18).

Measured root cause of the halt: the PREPARED E07-R19 brief's pre-flight
callout told the implementer to measure Core's atomic-write API and reread
the E07-R04 draft-repository pattern, but did not say what to conclude when
neither exists. The round's own pre-flight (sonnet-impl via Terra, branch
`sonnet-impl/e07-r19-local-plan-repository`, commit `1801a399`) measured:

  * no `PracticePlanRepository` / `PracticeOutcome` domain contract exists
    anywhere under `lib/features/practice_generator/domain` (the SDD Ch8
    §30.1 interface sketch is an epic-level aspiration, not yet built);
  * `KeyValueStore` (`lib/core/storage/key_value_store.dart`) exposes no
    atomic-write operation beyond a single `writeString(key, value)` call.

...and concluded BOTH gaps require forbidden-zone changes (a new domain file,
a new Core API, or importing `song_trainer`'s internal, non-public
`atomic_file_writer.dart`), then halted H3 (`.pipeline/HALTED`,
halted_at=2026-08-18T11:24:19+00:00) because the brief's `allowed_paths`
contains no `domain/**` or `core/**` entry.

That conclusion over-reaches. The round's own §0 pre-flight callout already
names the R04 precedent (`GenerationDraftRepository`,
`lib/features/practice_generator/data/local/generation_draft_repository.dart`)
-- a CONCRETE repository class with no matching abstract domain interface,
built entirely on existing domain types. And a single `KeyValueStore.
writeString` call is already all-or-nothing from the caller's perspective
(the Future either completes with the full value persisted or throws --
there is no API surface to observe a torn write of one key); the "no
half-written record" invariant (§5.3/A3) is achievable purely through write
ORDERING inside the already-allowed `data/local/` files, the same idiom
already proven by `lib/core/storage/storage_migrator.dart`
(`WrapJsonDocumentMigration.apply`: "write new, then remove old") and
`json_document_store.dart` (`JsonDocumentStore.write`: "quarantine copy ->
new document -> drop legacy key"). Neither gap needs a new domain file, a new
Core API, or a cross-feature import.

This guard locks in both halves of that resolution as machine checks so the
same halt cannot silently return:

  * the measured facts the resolution depends on (phantom types absent,
    reusable existing types present) -- if a future round adds the real
    domain contract or removes a type this brief relies on, this test turns
    red on purpose and forces a deliberate look, not a silent drift;
  * the brief's §0.0 revision documents the resolution and keeps
    `allowed_paths` byte-for-byte unchanged -- the fix is a documented brief
    clarification, not a scope widening into the forbidden zone (ADR 0112
    §3).
"""

import re
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief

REPO_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPO_ROOT / "lib" / "features" / "practice_generator" / "domain"
BRIEF = REPO_ROOT / "docs" / "rounds" / "e07-r19-local-plan-repository.md"

# Measured 2026-08-18: the SDD Ch8 §30.1 interface sketch names these types;
# none exists anywhere in the domain layer (0 refs measured via
# `rg -n "PracticePlanRepository|PracticeOutcome|PracticePlanId"
# lib/features/practice_generator`).
PHANTOM_TYPES = ("PracticePlanRepository", "PracticeOutcome", "PracticePlanId")

# The existing domain types the §0.0 resolution reuses instead -- each
# already ships on main (verified below by declaration grep, not assumed).
REUSED_TYPES = {
    "AdaptivePracticePlan": DOMAIN_ROOT / "model" / "adaptive_practice_plan.dart",
    "PlanId": DOMAIN_ROOT / "id" / "planner_ids.dart",
    "PracticePlanSummary": DOMAIN_ROOT / "model" / "adaptive_practice_plan.dart",
    "PlanRevision": DOMAIN_ROOT / "model" / "plan_revision.dart",
    "OutcomeId": DOMAIN_ROOT / "id" / "planner_ids.dart",
}

# The brief's allowed_paths before AND after this self-heal -- the fix must
# not add a single entry (that would be scope-widening into domain/core).
ORIGINAL_ALLOWED_PATHS = (
    "lib/features/practice_generator/data/local/local_practice_plan_repository.dart",
    "lib/features/practice_generator/data/local/practice_plan_serializer.dart",
    "lib/features/practice_generator/data/local/practice_plan_migrator.dart",
    "lib/features/practice_generator/public.dart",
    "test/features/practice_generator/data/local_repository_test.dart",
    "test/features/practice_generator/data/practice_plan_migrator_test.dart",
    "docs/rounds/e07-r19-local-plan-repository.md",
)

_DECL_RE_TEMPLATE = (
    r"(?m)^\s*(?:final\s+|sealed\s+|abstract\s+|base\s+|interface\s+)*"
    r"(?:class|enum|mixin)\s+{}\b"
)


def _declared_anywhere(root: Path, type_name: str) -> bool:
    pattern = re.compile(_DECL_RE_TEMPLATE.format(re.escape(type_name)))
    for dart_file in root.rglob("*.dart"):
        if pattern.search(dart_file.read_text(encoding="utf-8")):
            return True
    return False


class E07R19RepositoryContractScopeTest(unittest.TestCase):
    def test_phantom_domain_types_are_still_absent(self) -> None:
        """Forcing function, not a regression: if a later round adds the real
        contract, this must be noticed and the brief re-examined deliberately,
        not silently left claiming a gap that no longer exists."""
        present = [t for t in PHANTOM_TYPES if _declared_anywhere(DOMAIN_ROOT, t)]
        self.assertEqual(
            present,
            [],
            "A domain contract for these types now exists; the E07-R19 §0.0 "
            f"resolution (reuse existing types) must be re-evaluated: {present}",
        )

    def test_reused_types_exist_where_the_brief_says(self) -> None:
        for type_name, source in REUSED_TYPES.items():
            text = source.read_text(encoding="utf-8")
            pattern = re.compile(_DECL_RE_TEMPLATE.format(re.escape(type_name)))
            self.assertRegex(
                text,
                pattern,
                f"{type_name} must be declared in {source.relative_to(REPO_ROOT)} "
                "for the E07-R19 §0.0 resolution to hold",
            )

    def test_allowed_paths_unchanged_no_domain_or_core_widening(self) -> None:
        """The one forbidden exit from H3: widening allowed_paths into
        domain/** or core/** instead of reusing what already exists."""
        allowed = load_brief(BRIEF).metadata.allowed_paths
        self.assertEqual(
            allowed,
            ORIGINAL_ALLOWED_PATHS,
            "E07-R19 H3 must resolve by brief clarification, not by widening "
            "allowed_paths into the forbidden domain/core zone (ADR 0112 §3)",
        )

    def test_brief_documents_the_h3_resolution(self) -> None:
        """RED before the self-heal (no §0.0 section exists yet on the
        PREPARED brief); GREEN once the resolution is recorded."""
        text = BRIEF.read_text(encoding="utf-8")
        self.assertIn("## 0.0 Pre-flight revízió", text)
        self.assertIn("GenerationDraftRepository", text)
        for type_name in REUSED_TYPES:
            self.assertIn(type_name, text)
        # The write-ordering precedent this round's atomicity strategy reuses.
        self.assertIn("WrapJsonDocumentMigration", text)
        self.assertIn("JsonDocumentStore", text)


if __name__ == "__main__":
    unittest.main()
