import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.security import (
    WorkspaceManifest,
    audit_scope,
    capture_workspace_manifest,
    redact_text,
    rebase_workspace_manifest,
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

    def test_baseline_validation_allows_flutter_required_generated_artifacts(self) -> None:
        # A lista NEM kitalált: ez a `git ls-files --others --ignored` NYERS
        # kimenete a /home/ubuntu/ss-auto-e02-r21 worktree-ből, `flutter
        # gen-l10n` után (2026-08-01). Ezek együtt buktatták el a precheck-et.
        generated = (
            "lib/l10n/app_localizations.dart",
            "lib/l10n/app_localizations_en.dart",
            "lib/l10n/app_localizations_hu.dart",
            "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
            "android/local.properties",
            "ios/Flutter/Generated.xcconfig",
            "ios/Flutter/flutter_export_environment.sh",
            "ios/Flutter/ephemeral/flutter_lldbinit",
            "ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift",
            "ios/Runner/GeneratedPluginRegistrant.h",
            "ios/Runner/GeneratedPluginRegistrant.m",
            ".flutter-plugins-dependencies",
        )
        root = self.make_repo()
        (root / ".gitignore").write_text(
            ".cache/\nlib/l10n/app_localizations*.dart\nandroid/local.properties\n"
            "android/app/src/main/java/io/flutter/plugins/\nios/Flutter/\n"
            "ios/Runner/GeneratedPluginRegistrant.*\n.flutter-plugins-dependencies\n"
        )
        subprocess.run(["git", "add", ".gitignore"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "flutter gitignore"], cwd=root, check=True)
        (root / ".cache" / "old").unlink()
        for relative in generated:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("generated by flutter\n")

        manifest = capture_workspace_manifest(root)

        self.assertEqual(set(manifest.ignored_paths), set(generated))
        self.assertEqual(validate_baseline_manifest(manifest), ())

    def test_baseline_validation_still_rejects_a_stray_ignored_secret(self) -> None:
        # A tágítás nem lehet parttalan: egy ismeretlen ignore-olt fájl
        # (pl. otthagyott kulcs vagy állapot) továbbra is megállítja a kört.
        root = self.make_repo()
        (root / ".cache" / "private.txt").write_text("api-key\n")

        violations = validate_baseline_manifest(capture_workspace_manifest(root))

        self.assertTrue(any("unsafe ignored" in item for item in violations))

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

    def test_rebased_manifest_excludes_committed_preflight_drift_but_keeps_model_diff(self) -> None:
        # E03-R08 H6 (2026-08-02): the persisted baseline was captured at
        # 8c084268, while the reused worktree had already committed its
        # f023b89 pre-flight.  Auditing from the old head falsely attributed
        # the committed router/pipeline changes to the model.  Rebasing must
        # preserve the later uncommitted model edit for the normal scope audit.
        root = self.make_repo()
        (root / ".cache" / "old").unlink()
        baseline = capture_workspace_manifest(root)
        (root / "tools").mkdir()
        (root / "tools" / "router.py").write_text("preflight infrastructure\n")
        subprocess.run(["git", "add", "tools/router.py"], cwd=root, check=True)
        subprocess.run(["git", "commit", "-qm", "preflight"], cwd=root, check=True)
        (root / "lib" / "allowed.dart").write_text("model change\n")

        stale_audit = audit_scope(
            root,
            allowed_paths=("lib/allowed.dart",),
            protected_paths=(".git",),
            baseline=baseline,
        )
        refreshed = rebase_workspace_manifest(root, baseline)
        refreshed_audit = audit_scope(
            root,
            allowed_paths=("lib/allowed.dart",),
            protected_paths=(".git",),
            baseline=refreshed,
        )

        self.assertFalse(stale_audit.ok)
        self.assertTrue(any("tools/router.py" in item for item in stale_audit.violations))
        self.assertEqual(validate_baseline_manifest(refreshed), ())
        self.assertTrue(refreshed_audit.ok, refreshed_audit.violations)
        self.assertEqual(refreshed_audit.changed_paths, ("lib/allowed.dart",))

    def test_rebased_manifest_accepts_a_clean_snapshot_from_pruned_history(self) -> None:
        # The actual E03-R08 H6 state retained 8c084268 after the worktree
        # had been recreated from a different main lineage at f023b89.  A
        # clean persisted snapshot still gives the later scope audit all the
        # information it needs; ancestry itself is not a security property.
        root = self.make_repo()
        (root / ".cache" / "old").unlink()
        captured = capture_workspace_manifest(root)
        stale = WorkspaceManifest(
            baseline_head="8c08426887ddbbfc08b1487c13f5efe9bc49c10c",
            untracked_paths=captured.untracked_paths,
            ignored_paths=captured.ignored_paths,
            tracked_paths=captured.tracked_paths,
        )
        (root / "lib" / "allowed.dart").write_text("model change\n")

        refreshed = rebase_workspace_manifest(root, stale)
        audit = audit_scope(
            root,
            allowed_paths=("lib/allowed.dart",),
            protected_paths=(".git",),
            baseline=refreshed,
        )

        self.assertEqual(validate_baseline_manifest(refreshed), ())
        self.assertTrue(audit.ok, audit.violations)
        self.assertEqual(audit.changed_paths, ("lib/allowed.dart",))


if __name__ == "__main__":
    unittest.main()
