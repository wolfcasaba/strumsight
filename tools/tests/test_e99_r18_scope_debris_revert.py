r"""Regression guard for the E99-R18 self-heal (ADR 0112, halt H3, 2026-08-19).

Measured root cause of the halt: the MiniMax implementer
(`/home/ubuntu/ss-minimax-e99-r18`, branch
`minimax/e99-r18-gov-12-generated-public-barrels`, HEAD `e9c4a26b`) left three
UNTRACKED files outside the brief's `allowed_paths`:

    test_project/lib/features/demo/public.dart
    test_project/lib/features/demo/public/application.dart
    test_project/lib/features/demo/public/domain.dart

`.codex-round-status` recorded the machine verdict independently
(`scope_audit=VIOLATION`,
`scope_audit_base=6a6344a07d2fcfcebeb4916e43179b110ea9b7d9`,
`scope_audit_violations=path outside allowed scope: test_project/...` for all
three), and the Terra orchestrator session halted H3 rather than resolving it
on its own authority.

This is the MIRROR of the E07-R29/H3 precedent
(`tools/tests/test_e07_r29_accessibility_privacy_scope.py`), not a repeat of
it. There, the out-of-list paths were genuinely missing deliverables and the
fix widened `allowed_paths`. Here, measurement shows the opposite: `grep -rn
"test_project"` over the whole stopped worktree returns zero hits in any
tracked or untracked source, the automated test
(`test/tooling/gen_public_barrel_test.dart`) already isolates its own fixture
under `Directory.systemTemp`, and the three debris files are byte-identical to
that same test's in-memory `seedFreshBarrel()` fixture -- a manual, one-off
smoke check that was never meant to land in the repository tree. None of the
round's D1-D4 tasks or its §5 "Tilos zóna" (practice_generator only) name any
`demo`/`test_project` scaffold. Per
`docs/execution/pipeline-orchestrator-prompt.md`'s own VIOLATION-handling row
("a listán kívüli fájlokat vissza kell állítani, vagy H3 halt") and its §2
list of the orchestrator's own authority (narrowing `allowed_paths` requires
no escalation), the correct resolution is REVERT: delete the debris, leave
`allowed_paths` untouched. The brief's new "## 0.0 Pre-flight revízió" section
documents exactly this.

This guard locks in four things, all against the REAL measured paths and
content (not an invented fixture):

  * the brief actually carries the documented §0.0 resolution (this is the
    one genuinely red-before/green-after case here: before this self-heal's
    brief edit, no such section existed);
  * `allowed_paths` is byte-identical to the PREPARED brief -- the measured
    debris paths were deliberately NOT added;
  * the real `audit_legacy_scope()` -- the same function
    `tools/scope-audit.py` calls -- reproduces the measured VIOLATION when the
    three debris files are present (untracked, exact content captured from
    the stopped worktree);
  * the same audit is clean once they are absent, i.e. once the prescribed
    revert has actually happened.

UPDATE (E99-R18/H3 self-heal, second occurrence, ADR 0112, 2026-08-20): the
H8 self-heal (2026-08-20, see brief §0.0b) committed
`tools/tests/test_round_slots_generated_paths_and_patterns_coexist.py`
directly onto the round branch, outside the normal brief-authoring flow --
so it was never part of `ORIGINAL_ALLOWED_PATHS`. The round's own,
independently measured §0.0c D4 narrowing (glob -> explicit
`practice_generator` registry) then legitimately needed to edit that same
file to keep its `GENERATED_PATH_PATTERNS` assertions truthful, which a
second H3 halt correctly flagged as out of scope. This is the E07-R29
pattern this module's docstring above describes (a genuinely needed,
tracked, gate-exercised file), not a repeat of the `test_project/` debris
pattern.

Widening `allowed_paths` for that one file collides with THIS module's own
`test_allowed_paths_are_byte_identical_to_the_prepared_brief` cell below --
and fixing that cell requires editing THIS file, which the original brief
never listed either. That second-order edit is where the chain actually
stops: `grep -rl "ORIGINAL_ALLOWED_PATHS\|e99-r18-gov-12-generated-public-
barrels" tools/tests/` (2026-08-20) shows no third file references either
name, so no further file needs adding. `ORIGINAL_ALLOWED_PATHS` below
therefore carries exactly TWO additional, measured, documented entries (see
brief §0.0d): the coexist-test file, and this file's own path. The
`test_project/demo` debris-exclusion assertions later in this file are
UNCHANGED: this update widens the allowlist for a different, justified
reason, not a reopening of the original H3 debris question.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e99-r18-gov-12-generated-public-barrels.md"

# The brief's allowed_paths, verbatim from the current `ai-router` block.
# Unchanged by the original §0.0 debris-revert self-heal (2026-08-19); the
# §0.0d self-heal (2026-08-20) added exactly TWO entries -- the coexist-test
# file the D4 fix needed, and this guard's own path (needed to update the
# pinned tuple below) -- for the reason documented in the module docstring's
# UPDATE note above. The `test_project/demo` debris paths below are still
# deliberately absent from this tuple.
ORIGINAL_ALLOWED_PATHS = (
    "tool/gen_public_barrel.dart",
    "tool/check_architecture.dart",
    "lib/features/practice_generator/public.dart",
    "lib/features/practice_generator/public/",
    "tools/round-slots.py",
    "tools/tests/test_round_slots_generated_barrels.py",
    "tools/tests/test_round_slots_generated_paths_and_patterns_coexist.py",
    "tools/tests/test_e99_r18_scope_debris_revert.py",
    "test/tooling/gen_public_barrel_test.dart",
    "test/core/architecture_dependency_test.dart",
    "docs/rounds/e99-r18-gov-12-generated-public-barrels.md",
)

# Reproduced verbatim from `.codex-round-status`'s `scope_audit_violations=`
# on the stopped MiniMax worktree -- real measured data, not an invented
# fixture.
MEASURED_VIOLATION_PATHS = (
    "test_project/lib/features/demo/public.dart",
    "test_project/lib/features/demo/public/application.dart",
    "test_project/lib/features/demo/public/domain.dart",
)

# Byte-identical to the content actually found on disk in the stopped
# worktree (captured before any cleanup) -- itself a mirror of
# `gen_public_barrel_test.dart`'s in-memory `seedFreshBarrel()` fixture.
DEBRIS_CONTENTS = {
    "test_project/lib/features/demo/public.dart": (
        "/// Public domain contract for cross-feature Demo consumers.\n"
        "library;\n"
        "\n"
        "export 'application/port/a.dart';\n"
        "export 'application/usecase/b.dart';\n"
        "\n"
        "export 'domain/model/c.dart';\n"
        "export 'domain/policy/d.dart' hide X;\n"
    ),
    "test_project/lib/features/demo/public/application.dart": (
        "export '../application/port/a.dart';\n"
        "export '../application/usecase/b.dart';\n"
    ),
    "test_project/lib/features/demo/public/domain.dart": (
        "export '../domain/model/c.dart';\n"
        "export '../domain/policy/d.dart' hide X;\n"
    ),
}

# No protected-path fragment of the real .ai/router.toml touches any
# candidate path; an empty tuple keeps this guard focused on allowed_paths.
PROTECTED = ()


class E99R18ScopeDebrisRevertTest(unittest.TestCase):
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

    def _write_debris(self, root: Path) -> None:
        for relative, content in DEBRIS_CONTENTS.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")

    def test_brief_documents_the_h3_debris_revert_resolution(self) -> None:
        text = BRIEF.read_text(encoding="utf-8")
        self.assertIn("0.0 Pre-flight revízió", text)
        for relative in MEASURED_VIOLATION_PATHS:
            self.assertIn(
                relative,
                text,
                f"the §0.0 revision must name the exact measured path {relative}",
            )
        self.assertIn(
            "REVERT",
            text,
            "the §0.0 revision must record REVERT (not allow-list expansion) "
            "as the resolution",
        )

    def test_allowed_paths_are_byte_identical_to_the_prepared_brief(self) -> None:
        allowed = load_brief(BRIEF).metadata.allowed_paths
        self.assertEqual(
            tuple(allowed),
            ORIGINAL_ALLOWED_PATHS,
            "allowed_paths must stay exactly what the brief's §0.0d self-heal "
            "prepared -- the original §0.0 debris revert plus the two, "
            "separately measured and documented entries (coexist-test file "
            "and this guard's own path; see module docstring UPDATE note); "
            "no other path may be added",
        )
        for relative in MEASURED_VIOLATION_PATHS:
            self.assertNotIn(
                relative,
                allowed,
                f"{relative} is confirmed debris (see module docstring) -- it "
                "must never be legitimized via allowed_paths",
            )

    def test_measured_debris_reproduces_the_scope_violation_via_the_real_audit(self) -> None:
        root = self._make_repo()
        base = self._head(root)
        allowed = load_brief(BRIEF).metadata.allowed_paths
        self._write_debris(root)

        audit = audit_legacy_scope(root, base=base, allowed_paths=allowed, protected_paths=PROTECTED)

        self.assertFalse(audit.ok)
        for relative in MEASURED_VIOLATION_PATHS:
            self.assertIn(f"path outside allowed scope: {relative}", audit.violations)

    def test_the_real_audit_is_clean_once_the_debris_is_reverted(self) -> None:
        root = self._make_repo()
        base = self._head(root)
        allowed = load_brief(BRIEF).metadata.allowed_paths
        # No debris written this time -- this is the prescribed post-revert
        # state (the correct continuation per the §0.0 revision).

        audit = audit_legacy_scope(root, base=base, allowed_paths=allowed, protected_paths=PROTECTED)

        self.assertTrue(audit.ok, audit.violations)


# The brief's allowed_paths BEFORE the §0.0d self-heal edit -- verbatim from
# the `ai-router` block as the H8 self-heal (§0.0b) left it, i.e. the exact
# state that produced the second, 2026-08-20 H3 violation below.
PRE_H3_20260820_ALLOWED_PATHS = (
    "tool/gen_public_barrel.dart",
    "tool/check_architecture.dart",
    "lib/features/practice_generator/public.dart",
    "lib/features/practice_generator/public/",
    "tools/round-slots.py",
    "tools/tests/test_round_slots_generated_barrels.py",
    "test/tooling/gen_public_barrel_test.dart",
    "test/core/architecture_dependency_test.dart",
    "docs/rounds/e99-r18-gov-12-generated-public-barrels.md",
)

# `git diff --name-status 7458ca8330a66b9329b20009c400cb4a7bab3a14..HEAD` on
# the stopped round worktree (`/home/ubuntu/ss-minimax-e99-r18`, HEAD
# `826f930f`), reproduced verbatim -- ten paths, all pre-existing tracked
# files (`M`), none of them debris/untracked. This is the round's own D1-D4
# work; it does NOT include this self-heal's own bookkeeping edits.
MEASURED_ROUND_DIFF_20260820 = (
    "docs/rounds/e99-r18-gov-12-generated-public-barrels.md",
    "lib/features/practice_generator/public/application.dart",
    "lib/features/practice_generator/public/data.dart",
    "lib/features/practice_generator/public/domain.dart",
    "lib/features/practice_generator/public/presentation.dart",
    "test/tooling/gen_public_barrel_test.dart",
    "tool/gen_public_barrel.dart",
    "tools/round-slots.py",
    "tools/tests/test_round_slots_generated_barrels.py",
    "tools/tests/test_round_slots_generated_paths_and_patterns_coexist.py",
)

THE_H3_20260820_DISPUTED_PATH = "tools/tests/test_round_slots_generated_paths_and_patterns_coexist.py"


class E99R18H3SecondOccurrenceAllowlistTest(unittest.TestCase):
    """Regression guard for the SECOND E99-R18/H3 halt (2026-08-20): the D4
    §0.0c fix needed to edit `test_round_slots_generated_paths_and_patterns_
    coexist.py`, a file H8 committed directly onto the round branch, never
    added to `allowed_paths`. See brief §0.0d for the full measurement and
    the module docstring's UPDATE note for why the fix is two entries."""

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

    def _touch_measured_diff(self, root: Path) -> None:
        for relative in MEASURED_ROUND_DIFF_20260820:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"-- touched by the measured 2026-08-20 round diff: {relative}\n", encoding="utf-8")

    def test_measured_round_diff_was_out_of_scope_before_the_fix(self) -> None:
        """RED: reproduces the exact second halt against the PRE-fix allowed_paths."""
        root = self._make_repo()
        base = self._head(root)
        self._touch_measured_diff(root)

        audit = audit_legacy_scope(
            root, base=base, allowed_paths=PRE_H3_20260820_ALLOWED_PATHS, protected_paths=PROTECTED
        )

        self.assertFalse(audit.ok)
        self.assertIn(f"path outside allowed scope: {THE_H3_20260820_DISPUTED_PATH}", audit.violations)

    def test_measured_round_diff_is_in_scope_after_the_fix(self) -> None:
        """GREEN: the same measured diff against the brief's CURRENT (fixed)
        allowed_paths -- loaded live, so a future edit that drops the §0.0d
        entries fails this test honestly instead of trivially passing."""
        root = self._make_repo()
        base = self._head(root)
        self._touch_measured_diff(root)
        allowed = load_brief(BRIEF).metadata.allowed_paths

        audit = audit_legacy_scope(root, base=base, allowed_paths=allowed, protected_paths=PROTECTED)

        self.assertTrue(audit.ok, audit.violations)

    def test_the_fix_widened_the_allowlist_by_exactly_two_entries(self) -> None:
        """The §0.0d resolution is additive-by-exactly-two (see module
        docstring UPDATE note for why the chain stops there), not a rewrite:
        proves nothing the H8 self-heal or the original brief author already
        granted was silently dropped or replaced."""
        allowed = tuple(load_brief(BRIEF).metadata.allowed_paths)
        added = set(allowed) - set(PRE_H3_20260820_ALLOWED_PATHS)
        removed = set(PRE_H3_20260820_ALLOWED_PATHS) - set(allowed)
        self.assertEqual(added, {THE_H3_20260820_DISPUTED_PATH, "tools/tests/test_e99_r18_scope_debris_revert.py"})
        self.assertEqual(removed, set())


if __name__ == "__main__":
    unittest.main()
