"""Test-mode firings must never mutate a shared working tree's real git branch.

Measured 2026-08-13, first as E99-R08 review finding F1, then independently
reproduced while gating E99-R08/H3 (self-heal): `tools/round-pipeline.sh`'s
step-3 workspace-restoration block runs a REAL `git checkout -q main` against
the *process's cwd* whenever that checkout is on a non-main branch with a
clean tree -- unconditionally, in both production and test invocations.
`round-pipeline.sh` resolves `repo_root` from its own `BASH_SOURCE` and `cd`s
there before anything else (tools/round-pipeline.sh:58-59), so every later
bare `git ...` call operates on wherever the invoked SCRIPT FILE physically
lives, not on the caller's `cwd`. Every `PipelineIntegrationTest` "full
firing" test in test_pipeline_integration.py invokes `ROOT/tools/round-pipeline.sh`
directly -- as long as ROOT happens to be checked out on `main` at test time
this is invisible, but the moment it is not (a round or heal branch, exactly
this self-heal's own worktree while it drafted its fix), the "recovery"
silently switches the real checkout to `main` mid-suite. Reproduced directly:
cloning the branch under test into an isolated directory and running the
unmodified suite there left the clone on `main` by the time pytest exited,
discarding the branch the suite was meant to be measuring.

The fix gates the mutation on `PIPELINE_STATE_DIR` being unset (production
cron never sets it; every test/review invocation does) so test-mode fails
closed instead of touching the tree's branch.

The regression test below builds a throwaway, self-contained repo rather than
cloning ROOT: cloning ROOT (or a clone of a clone, as this test itself may be
run from) cannot be relied on to expose a fetchable `main` -- an ordinary
`git clone` only advertises the source's OWN `refs/heads/*` as clonable, not
its `refs/remotes/origin/*`, and a CI checkout of just the round branch may
not have `main` reachable via `origin` at all. `origin` is instead pointed at
the throwaway repo itself, so the script's own `git fetch -q origin main`
step is a real, local, network-free operation regardless of how this test
itself was reached.
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT_SOURCE = ROOT / "tools" / "round-pipeline.sh"


class WorkspaceRestorationTestModeGuardTest(unittest.TestCase):
    def run_git(self, repo: Path, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", *args], cwd=repo, check=True, capture_output=True, text=True,
        )

    def make_throwaway_repo_on_a_clean_non_main_branch(self) -> Path:
        """A fully self-contained repo -- never ROOT, never a clone of it --
        carrying a real copy of the script under test, with `origin`
        pointed at itself so `git fetch -q origin main` is local and real.
        """
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        repo = Path(temporary.name) / "repo"
        repo.mkdir()
        self.run_git(repo, "init", "-q", "-b", "main")
        self.run_git(repo, "config", "user.email", "heal-test@example.invalid")
        self.run_git(repo, "config", "user.name", "Heal Test")

        tools_dir = repo / "tools"
        tools_dir.mkdir()
        (tools_dir / "round-pipeline.sh").write_text(
            SCRIPT_SOURCE.read_text(encoding="utf-8"), encoding="utf-8"
        )
        (tools_dir / "round-pipeline.sh").chmod(0o755)
        execution_dir = repo / "docs" / "execution"
        execution_dir.mkdir(parents=True)
        # round-pipeline.sh only checks these two for EXISTENCE before the
        # workspace-restoration block; their content is never read that early.
        (execution_dir / "pipeline-queue.tsv").write_text("", encoding="utf-8")
        (execution_dir / "pipeline-orchestrator-prompt.md").write_text("", encoding="utf-8")

        self.run_git(repo, "add", "-A")
        self.run_git(repo, "commit", "-q", "-m", "throwaway baseline")
        self.run_git(repo, "remote", "add", "origin", str(repo))
        self.run_git(repo, "checkout", "-q", "-b", "throwaway/workspace-guard-probe")
        return repo

    def branch_of(self, repo: Path) -> str:
        return self.run_git(repo, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()

    def test_a_test_mode_firing_fails_closed_instead_of_switching_the_real_branch(self) -> None:
        repo = self.make_throwaway_repo_on_a_clean_non_main_branch()
        self.assertEqual(self.branch_of(repo), "throwaway/workspace-guard-probe")
        self.assertEqual(self.run_git(repo, "status", "--porcelain").stdout, "")

        with tempfile.TemporaryDirectory() as state_name:
            state = Path(state_name)
            # CI runners (and any box without an interactive `claude` login)
            # have no `claude` CLI on PATH -- round-pipeline.sh's own
            # `command -v "$claude_bin"` / `command -v gh` preconditions,
            # checked before the workspace-restoration block, would die
            # first and never reach the code under test. Neither is ever
            # actually invoked on this path (the guard fires before any
            # dispatch), so unused stubs satisfy the existence checks the
            # same way test_pipeline_integration.py's full-firing tests
            # already stub `python3` for an analogous reason.
            stub_bin = state / "bin"
            stub_bin.mkdir()
            for name in ("claude", "gh"):
                stub = stub_bin / name
                stub.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                stub.chmod(0o755)

            env = dict(os.environ)
            env["PIPELINE_STATE_DIR"] = str(state)
            env["PIPELINE_NO_LAUNCH"] = "1"
            env["PATH"] = f"{stub_bin}:{env['PATH']}"

            result = subprocess.run(
                ["bash", str(repo / "tools" / "round-pipeline.sh")],
                cwd=repo, env=env, text=True, capture_output=True, check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "a driver nem mozdítja a megosztott munkafa ágát", result.stderr
            )
            self.assertEqual(
                self.branch_of(repo),
                "throwaway/workspace-guard-probe",
                "a test-mode firing must not touch the repo's real branch",
            )


if __name__ == "__main__":
    unittest.main()
