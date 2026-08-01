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


if __name__ == "__main__":
    unittest.main()
