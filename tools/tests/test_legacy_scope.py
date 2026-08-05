import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.legacy_scope import audit_legacy_scope, collect_changed_paths
from tools.ai_router.security import SecurityError

ALLOWED = ("lib/features/tutor", "test/features/tutor", "docs/rounds/e04-r10.md")
PROTECTED = (".git", ".ai/router.toml", ".pipeline", "tools/ai_router")


class LegacyScopeTest(unittest.TestCase):
    def make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "gov@example.invalid"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Gov Test"], cwd=root, check=True)
        (root / ".gitignore").write_text("build/\n")
        for relative in (
            "lib/features/tutor/tool.dart",
            "lib/core/foundation/app_failure.dart",
            "test/features/tutor/tool_test.dart",
            "docs/rounds/e04-r10.md",
        ):
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("baseline\n")
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
        return root

    def head(self, root: Path) -> str:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
        ).stdout.strip()

    def commit_all(self, root: Path, message: str) -> None:
        subprocess.run(["git", "add", "-A"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", message], cwd=root, check=True)

    def audit(self, root: Path, base: str):
        return audit_legacy_scope(
            root, base=base, allowed_paths=ALLOWED, protected_paths=PROTECTED
        )

    def test_in_scope_work_passes_whether_committed_or_not(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        (root / "lib/features/tutor/tool.dart").write_text("implemented\n")
        self.commit_all(root, "committed work")
        (root / "test/features/tutor/tool_test.dart").write_text("uncommitted\n")
        (root / "lib/features/tutor/registry.dart").write_text("new untracked\n")

        audit = self.audit(root, base)

        self.assertTrue(audit.ok, audit.format())
        self.assertEqual(audit.violations, ())
        # A commitolt, a nem commitolt és az új untracked fájl mind LÁTSZIK —
        # a legacy protokoll megköveteli a commitot, ezért a mozdult HEAD
        # önmagában nem sértés (ellentétben a router baseline-jével).
        self.assertIn("lib/features/tutor/tool.dart", audit.changed_paths)
        self.assertIn("test/features/tutor/tool_test.dart", audit.changed_paths)
        self.assertIn("lib/features/tutor/registry.dart", audit.changed_paths)

    def test_committed_out_of_scope_file_is_a_violation(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        (root / "lib/core/foundation/app_failure.dart").write_text("scope creep\n")
        self.commit_all(root, "out of scope")

        audit = self.audit(root, base)

        self.assertFalse(audit.ok)
        self.assertIn(
            "path outside allowed scope: lib/core/foundation/app_failure.dart", audit.violations
        )

    def test_protected_path_is_reported_as_protected_not_merely_out_of_scope(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        target = root / "tools/ai_router/security.py"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("weakened\n")

        audit = self.audit(root, base)

        self.assertFalse(audit.ok)
        self.assertIn("protected path changed: tools/ai_router/security.py", audit.violations)

    def test_generated_and_ignored_artefacts_are_exempt(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        (root / "build").mkdir()
        (root / "build/app.apk").write_text("artifact\n")
        (root / ".codex-round-status").write_text("status=done\n")
        (root / "docs/reviews").mkdir(parents=True)
        (root / "docs/reviews/e04-r10-review.md").write_text("report\n")

        audit = self.audit(root, base)

        self.assertTrue(audit.ok, audit.format())
        self.assertIn(".codex-round-status", audit.exempt_paths)
        self.assertIn("docs/reviews/e04-r10-review.md", audit.exempt_paths)

    def test_deleted_in_scope_file_is_visible_and_allowed(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        (root / "lib/features/tutor/tool.dart").unlink()
        self.commit_all(root, "delete in scope")

        audit = self.audit(root, base)

        self.assertTrue(audit.ok, audit.format())
        self.assertIn("lib/features/tutor/tool.dart", audit.changed_paths)

    def test_deleted_out_of_scope_file_is_a_violation(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        (root / "lib/core/foundation/app_failure.dart").unlink()
        self.commit_all(root, "delete out of scope")

        audit = self.audit(root, base)

        self.assertFalse(audit.ok)
        self.assertIn(
            "path outside allowed scope: lib/core/foundation/app_failure.dart", audit.violations
        )

    def test_symlink_escape_is_rejected_even_inside_an_allowed_prefix(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        link = root / "lib/features/tutor/escape"
        link.symlink_to("/etc")
        (root / "lib/features/tutor/other.dart").write_text("ok\n")

        audit = self.audit(root, base)

        self.assertFalse(audit.ok)
        self.assertTrue(
            any(violation.startswith("symlink path is not allowed") for violation in audit.violations),
            audit.violations,
        )

    def test_empty_allowed_paths_is_rejected_rather_than_allowing_everything(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        with self.assertRaises(SecurityError):
            audit_legacy_scope(root, base=base, allowed_paths=(), protected_paths=PROTECTED)

    def test_collect_changed_paths_is_sorted_and_deduplicated(self) -> None:
        root = self.make_repo()
        base = self.head(root)

        (root / "lib/features/tutor/tool.dart").write_text("changed\n")
        (root / "lib/features/tutor/added.dart").write_text("added\n")

        changed = collect_changed_paths(root, base)

        self.assertEqual(list(changed), sorted(set(changed)))


if __name__ == "__main__":
    unittest.main()
