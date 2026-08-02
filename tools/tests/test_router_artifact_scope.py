import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.security import audit_scope, capture_workspace_manifest


class RouterArtifactScopeTest(unittest.TestCase):
    def test_non_authoritative_router_mirror_is_explicitly_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "router@example.invalid"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Router Test"], cwd=root, check=True)
            (root / ".gitignore").write_text(".ai/runs/\n")
            (root / "lib").mkdir()
            (root / "lib" / "allowed.dart").write_text("baseline\n")
            subprocess.run(["git", "add", ".gitignore", "lib/allowed.dart"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
            baseline = capture_workspace_manifest(root)
            mirror = root / ".ai" / "runs" / "E03-R01"
            mirror.mkdir(parents=True)
            (mirror / "result.json").write_text("{}\n")

            audit = audit_scope(
                root,
                allowed_paths=("lib/allowed.dart",),
                protected_paths=(".git",),
                baseline=baseline,
            )

            self.assertTrue(audit.ok, audit.violations)

    def test_resume_workflow_artifacts_do_not_self_conflict_with_scope_audit(self) -> None:
        # Mért reprodukció (E02-R21, H6 halt, 3. eset, L38): a dokumentált
        # `resume` munkafolyamat (docs/execution/02-codex-playbook.md §13,
        # pipeline-orchestrator-prompt.md §1.1) az orchestrátort arra
        # kötelezi, hogy a review-findings fájlt és a docs/reviews/*.md
        # review-jelentést A MUNKAPÉLDÁNYBA írja, a router pedig a saját
        # `.codex-round-status` jelzőfájlját is oda írja
        # (tools/codex-signal.sh). A fix előtt mindhárom "path outside
        # allowed scope"-ot dobott — a router self-blokkolta a saját
        # dokumentált munkafolyamatát.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "router@example.invalid"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Router Test"], cwd=root, check=True)
            (root / ".gitignore").write_text(".codex-round-status\n.ai/runs/\n")
            (root / "lib").mkdir()
            (root / "lib" / "allowed.dart").write_text("baseline\n")
            (root / "docs" / "reviews").mkdir(parents=True)
            review = root / "docs" / "reviews" / "e03-r01-review.md"
            review.write_text("# Review\n\nVerdikt: HALT\n")
            subprocess.run(
                ["git", "add", ".gitignore", "lib/allowed.dart", "docs/reviews/e03-r01-review.md"],
                cwd=root,
                check=True,
            )
            subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
            baseline = capture_workspace_manifest(root)

            # (1) a router saját jelzőfájlja (gitignore-olt, mint élesben)
            (root / ".codex-round-status").write_text("READY_FOR_REVIEW\n")
            # (2) az orchestrátor a `resume`-hoz a munkapéldányba írt
            # review-findings fájlt ad át a router-nek
            findings = root / ".ai" / "review-findings-e03-r01.md"
            findings.parent.mkdir(parents=True, exist_ok=True)
            findings.write_text("## Findings\n- BLOCKER: ...\n")
            # (3) az orchestrátor kiegészíti a MÁR TRACKELT review-jelentést
            # (a `resume` update szakasza) — ez a valódi H6 reprodukció:
            # egy tracked fájl módosítása, nem egy új ignorált/untracked fájl
            review.write_text(review.read_text() + "\n## Update\nresume attempt\n")

            audit = audit_scope(
                root,
                allowed_paths=("lib/allowed.dart",),
                protected_paths=(".git",),
                baseline=baseline,
            )

            self.assertTrue(audit.ok, audit.violations)
            self.assertEqual(audit.scoped_changed_paths, ())

    def test_coverage_lcov_artifact_is_generated_ignored(self) -> None:
        # Mért reprodukció (E03-R02, H6 halt): a brief §6 elfogadási
        # kritériuma >=90% sor-lefedettséget ír elő, amit az implementer
        # `flutter test --coverage`-dzsel mér — ez a StrumSight saját
        # .gitignore:34 `/coverage/` szabálya miatt gitignore-olt
        # `coverage/lcov.info`-t hagy a munkapéldányban. A fix előtt a
        # GENERATED_IGNORED_PREFIXES nem tartalmazta a "coverage"-ot, tehát
        # EGYETLEN, a briefnek megfelelően lefedettséget mérő kör sem ment
        # volna át az auditon, egy egyébként tökéletesen scope-tiszta
        # implementátorral sem.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.email", "router@example.invalid"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Router Test"], cwd=root, check=True)
            (root / ".gitignore").write_text("/coverage/\n")
            (root / "lib").mkdir()
            (root / "lib" / "allowed.dart").write_text("baseline\n")
            subprocess.run(["git", "add", ".gitignore", "lib/allowed.dart"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-qm", "baseline"], cwd=root, check=True)
            baseline = capture_workspace_manifest(root)

            coverage_dir = root / "coverage"
            coverage_dir.mkdir()
            (coverage_dir / "lcov.info").write_text("TN:\nend_of_record\n")

            audit = audit_scope(
                root,
                allowed_paths=("lib/allowed.dart",),
                protected_paths=(".git",),
                baseline=baseline,
            )

            self.assertTrue(audit.ok, audit.violations)
            self.assertEqual(audit.scoped_changed_paths, ())


if __name__ == "__main__":
    unittest.main()
