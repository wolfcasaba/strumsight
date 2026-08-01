import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.security import (
    audit_scope,
    capture_workspace_manifest,
    redact_text,
    validate_baseline_manifest,
)


class SecurityTest(unittest.TestCase):
    def test_redacts_headers_keys_assignments_queries_and_exact_secrets(self) -> None:
        text = (
            "Authorization: Bearer bearer-secret\n"
            "MINIMAX_API_KEY=env-secret\n"
            "key=sk-abcdefghijklmnopqrstuvwxyz123456\n"
            "https://example.test/?token=query-secret\n"
            "exact-value"
        )
        redacted = redact_text(text, secret_values=("exact-value",))

        for secret in (
            "bearer-secret",
            "env-secret",
            "sk-abcdefghijklmnopqrstuvwxyz123456",
            "query-secret",
            "exact-value",
        ):
            self.assertNotIn(secret, redacted)
        self.assertIn("[REDACTED]", redacted)

    def make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "router@example.invalid"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Router Test"], cwd=root, check=True)
        (root / ".gitignore").write_text(".cache/\n")
        (root / "lib").mkdir()
        (root / "lib" / "allowed.dart").write_text("baseline\n")
        (root / "lib" / "forbidden.dart").write_text("baseline\n")
        (root / ".cache").mkdir()
        (root / ".cache" / "old").write_text("old\n")
        subprocess.run(["git", "add", ".gitignore", "lib"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
        return root

    def test_scope_audit_covers_modified_untracked_ignored_deleted_and_symlink(self) -> None:
        root = self.make_repo()
        baseline = capture_workspace_manifest(root)
        (root / "lib" / "allowed.dart").write_text("changed\n")
        (root / "lib" / "new.dart").write_text("new\n")
        (root / "lib" / "forbidden.dart").unlink()
        (root / ".cache" / "hidden").write_text("hidden\n")
        (root / "lib" / "link.dart").symlink_to("/tmp")

        audit = audit_scope(
            root,
            allowed_paths=("lib/allowed.dart", "lib/new.dart", "lib/link.dart"),
            protected_paths=(".git",),
            baseline=baseline,
            ignored_allow_paths=(),
        )

        self.assertFalse(audit.ok)
        self.assertIn("lib/forbidden.dart", audit.changed_paths)
        self.assertIn(".cache/hidden", audit.changed_paths)
        self.assertTrue(any("symlink" in violation for violation in audit.violations))
        self.assertTrue(any("forbidden.dart" in violation for violation in audit.violations))
        self.assertTrue(any(".cache/hidden" in violation for violation in audit.violations))

    def test_generated_ignored_prefix_may_be_explicitly_allowed(self) -> None:
        root = self.make_repo()
        (root / ".gitignore").write_text(".cache/\n.dart_tool/\n")
        subprocess.run(["git", "add", ".gitignore"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "ignore generated"], cwd=root, check=True)
        baseline = capture_workspace_manifest(root)
        (root / ".dart_tool").mkdir()
        (root / ".dart_tool" / "state").write_text("generated\n")

        audit = audit_scope(
            root,
            allowed_paths=("lib/allowed.dart",),
            protected_paths=(".git",),
            baseline=baseline,
            ignored_allow_paths=(".dart_tool",),
        )

        self.assertTrue(audit.ok, audit.violations)

    def test_baseline_validation_rejects_tracked_untracked_and_unsafe_ignored(self) -> None:
        root = self.make_repo()
        (root / "lib" / "allowed.dart").write_text("dirty\n")
        (root / "scratch.txt").write_text("untracked\n")
        (root / ".cache" / "private.txt").write_text("ignored\n")

        manifest = capture_workspace_manifest(root)
        violations = validate_baseline_manifest(manifest)

        self.assertTrue(any("tracked changes" in item for item in violations))
        self.assertTrue(any("untracked files" in item for item in violations))
        self.assertTrue(any("unsafe ignored" in item for item in violations))

    def test_baseline_validation_allows_known_generated_ignored_files(self) -> None:
        root = self.make_repo()
        (root / ".gitignore").write_text(".cache/\n.dart_tool/\n__pycache__/\n")
        subprocess.run(["git", "add", ".gitignore"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "ignore generated"], cwd=root, check=True)
        (root / ".cache" / "old").unlink()
        (root / ".dart_tool").mkdir()
        (root / ".dart_tool" / "state").write_text("generated\n")
        (root / "tools" / "__pycache__").mkdir(parents=True)
        (root / "tools" / "__pycache__" / "router.pyc").write_bytes(b"cache")

        manifest = capture_workspace_manifest(root)

        self.assertEqual(validate_baseline_manifest(manifest), ())

    def test_scope_audit_rejects_a_model_created_commit(self) -> None:
        root = self.make_repo()
        baseline = capture_workspace_manifest(root)
        (root / "lib" / "allowed.dart").write_text("model change\n")
        subprocess.run(["git", "add", "lib/allowed.dart"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "model must not own Git"], cwd=root, check=True)

        audit = audit_scope(
            root,
            allowed_paths=("lib/allowed.dart",),
            protected_paths=(".git",),
            baseline=baseline,
        )

        self.assertFalse(audit.ok)
        self.assertTrue(any("commit" in violation for violation in audit.violations))


if __name__ == "__main__":
    unittest.main()
