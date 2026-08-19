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
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.legacy_scope import audit_legacy_scope

REPO_ROOT = Path(__file__).resolve().parents[2]
BRIEF = REPO_ROOT / "docs" / "rounds" / "e99-r18-gov-12-generated-public-barrels.md"

# The brief's allowed_paths, unchanged by this self-heal (verbatim from the
# `ai-router` block, both before and after the §0.0 revision).
ORIGINAL_ALLOWED_PATHS = (
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
            "E99-R18/H3 must resolve by REVERTING the measured debris, not by "
            "widening allowed_paths -- the list must stay exactly what the "
            "PREPARED brief already granted",
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


if __name__ == "__main__":
    unittest.main()
