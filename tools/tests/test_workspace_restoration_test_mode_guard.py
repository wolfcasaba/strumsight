"""Test-mode firings must never mutate a shared working tree's real git branch.

Measured 2026-08-13, first as E99-R08 review finding F1, then independently
reproduced while gating E99-R08/H3 (self-heal): `tools/round-pipeline.sh`'s
step-3 workspace-restoration block runs a REAL `git checkout -q main` against
the *process's cwd* whenever that checkout is on a non-main branch with a
clean tree -- unconditionally, in both production and test invocations. Every
`PipelineIntegrationTest` "full firing" test in test_pipeline_integration.py
calls `bash tools/round-pipeline.sh` with `cwd=ROOT` (the real repo). As long
as ROOT happens to be checked out on `main` at test time this is invisible,
but the moment it is not (a round or heal branch, exactly this self-heal's own
worktree while it drafts its fix), the "recovery" silently switches the real
checkout to `main` mid-suite -- reproduced directly: cloning the branch under
test into an isolated directory and running the unmodified suite there left
the clone on `main` by the time pytest exited, discarding the branch the
suite was meant to be measuring.

The fix gates the mutation on `PIPELINE_STATE_DIR` being unset (production
cron never sets it; every test/review invocation does) so test-mode fails
closed instead of touching the tree's branch.
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class WorkspaceRestorationTestModeGuardTest(unittest.TestCase):
    def make_offline_clone_on_a_clean_non_main_branch(self) -> Path:
        """A fully local, network-free clone -- never ROOT itself -- so a
        pre-fix run's real `git checkout main` lands on disposable state.

        round-pipeline.sh's very first lines resolve `repo_root` from its own
        `BASH_SOURCE` and `cd` there before anything else (tools/round-pipeline.sh:58-59)
        -- every later bare `git ...` call operates on wherever the SCRIPT
        FILE lives, not on the caller's `cwd`. The clone's own copy of the
        script must be invoked (`clone/tools/round-pipeline.sh`), never
        ROOT's, or this test silently exercises ROOT's real working tree.
        """
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        clone = Path(temporary.name) / "clone"
        subprocess.run(
            ["git", "clone", "--local", "-q", str(ROOT), str(clone)],
            check=True, capture_output=True, text=True,
        )
        subprocess.run(
            ["git", "checkout", "-q", "-b", "throwaway/workspace-guard-probe"],
            cwd=clone, check=True, capture_output=True, text=True,
        )
        return clone

    def branch_of(self, repo: Path) -> str:
        return subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=repo, check=True, capture_output=True, text=True,
        ).stdout.strip()

    def test_a_test_mode_firing_fails_closed_instead_of_switching_the_real_branch(self) -> None:
        clone = self.make_offline_clone_on_a_clean_non_main_branch()
        self.assertEqual(self.branch_of(clone), "throwaway/workspace-guard-probe")

        with tempfile.TemporaryDirectory() as state_name:
            state = Path(state_name)
            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PIPELINE_NO_LAUNCH"] = "1"

            result = subprocess.run(
                ["bash", str(clone / "tools" / "round-pipeline.sh")],
                cwd=clone, env=env, text=True, capture_output=True, check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "a driver nem mozdítja a megosztott munkafa ágát", result.stderr
            )
            self.assertEqual(
                self.branch_of(clone),
                "throwaway/workspace-guard-probe",
                "test-mode firing must not have touched the clone's real branch",
            )


if __name__ == "__main__":
    unittest.main()
