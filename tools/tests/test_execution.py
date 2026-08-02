import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.execution import ProcessRunner, build_codex_argv, run_codex

_GIT_GUARD = Path(__file__).resolve().parents[1] / "ai_router" / "git-guard" / "git"


def _run_git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True)


def make_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class ExecutionTest(unittest.TestCase):
    def test_build_codex_argv_is_explicit_and_prompt_free(self) -> None:
        argv = build_codex_argv("codex", "m3", Path("/tmp/worktree"))

        self.assertEqual(
            argv,
            [
                "codex",
                "--ask-for-approval",
                "never",
                "exec",
                "--profile",
                "m3",
                "--cd",
                "/tmp/worktree",
                "--sandbox",
                "danger-full-access",
                "--ephemeral",
                "--json",
                "-",
            ],
        )

    def test_build_codex_argv_uses_danger_full_access_for_terra_too(self) -> None:
        # E02-R21 H4: `--sandbox workspace-write` needs a bwrap network
        # namespace this container cannot create (`bwrap --unshare-net`
        # fails with "Failed RTM_NEWADDR: Operation not permitted"), so
        # every real (non-smoke) Codex call silently ran zero shell commands.
        # `tools/codex-round.sh` already uses `danger-full-access` for the
        # same reason; isolation comes from the dedicated worktree, not bwrap.
        argv = build_codex_argv("codex", "terra", Path("/tmp/worktree"))

        sandbox_index = argv.index("--sandbox")
        self.assertEqual(argv[sandbox_index + 1], "danger-full-access")

    def test_git_guard_blocks_commit_and_push_but_passes_through_other_subcommands(
        self,
    ) -> None:
        # E03-R05 H6 (measured 2026-08-02): MiniMax-M3 committed d0546f0 in
        # worktree ss-router-e03-r05-2 despite the router's prompt telling it
        # not to (router.py _initial_prompt is "Do not commit, push, ..." as
        # its second line) — security.py's scope-audit caught it, but only
        # after burning a whole M3 attempt and halting the pipeline. This
        # tests the shim directly: it must reject commit/push regardless of
        # how the subcommand is spelled (leading global flags), and must not
        # interfere with any other git subcommand a model legitimately needs.
        real_git = shutil.which("git")
        self.assertIsNotNone(real_git)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _run_git(root, "init", "-q")
            _run_git(root, "config", "user.email", "m3@example.invalid")
            _run_git(root, "config", "user.name", "M3")
            (root / "README.md").write_text("baseline\n", encoding="utf-8")
            _run_git(root, "add", "README.md")
            _run_git(root, "commit", "-q", "-m", "baseline")
            baseline_head = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
            ).stdout.strip()
            guard_env = {**os.environ, "STRUMSIGHT_REAL_GIT": real_git}

            (root / "README.md").write_text("baseline\nmodel change\n", encoding="utf-8")
            status = subprocess.run(
                [str(_GIT_GUARD), "status", "--porcelain"],
                cwd=root,
                env=guard_env,
                text=True,
                capture_output=True,
            )
            self.assertEqual(status.returncode, 0)
            self.assertIn("README.md", status.stdout)

            add = subprocess.run(
                [str(_GIT_GUARD), "add", "README.md"],
                cwd=root,
                env=guard_env,
                text=True,
                capture_output=True,
            )
            self.assertEqual(add.returncode, 0)

            for blocked_argv in (["commit", "-m", "model commit"], ["push"], ["-C", str(root), "commit", "-m", "x"]):
                blocked = subprocess.run(
                    [str(_GIT_GUARD), *blocked_argv],
                    cwd=root,
                    env=guard_env,
                    text=True,
                    capture_output=True,
                )
                self.assertNotEqual(blocked.returncode, 0, blocked_argv)
                self.assertIn("blocked", blocked.stderr)

            head_after = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
            ).stdout.strip()
            self.assertEqual(head_after, baseline_head)

    def test_run_codex_blocks_a_model_commit_at_the_shell_layer(self) -> None:
        # Reproduces d0546f0 end-to-end through the real run_codex wiring: a
        # fake "codex" process (standing in for MiniMax-M3) tries to commit
        # a change on its own, the way the real M3 call did in
        # ss-router-e03-r05-2. Before the git-guard was wired into
        # run_codex's env, this commit succeeded (RED); after, `git commit`
        # fails inside the model's own subprocess and HEAD never moves.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _run_git(root, "init", "-q")
            _run_git(root, "config", "user.email", "m3@example.invalid")
            _run_git(root, "config", "user.name", "M3")
            (root / "README.md").write_text("baseline\n", encoding="utf-8")
            _run_git(root, "add", "README.md")
            _run_git(root, "commit", "-q", "-m", "baseline")
            baseline_head = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
            ).stdout.strip()

            fake = root / "codex"
            result_file = root / "result.json"
            make_executable(
                fake,
                "#!/usr/bin/env python3\n"
                "import json, pathlib, subprocess, sys\n"
                "sys.stdin.read()\n"
                "pathlib.Path('model_change.txt').write_text('model change\\n')\n"
                "subprocess.run(['git', 'add', 'model_change.txt'], check=True)\n"
                "commit = subprocess.run(['git', 'commit', '-q', '-m', 'model commit'])\n"
                "pathlib.Path('result.json').write_text(json.dumps({'commit_returncode': commit.returncode}))\n"
                "print(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':'DONE'}}))\n",
            )

            run_codex(
                profile="m3",
                worktree=root,
                prompt="ignore",
                runner=ProcessRunner(),
                codex_bin=str(fake),
                timeout_seconds=5,
            )

            head_after = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True
            ).stdout.strip()
            payload = json.loads(result_file.read_text())

            self.assertNotEqual(payload["commit_returncode"], 0)
            self.assertEqual(head_after, baseline_head)

    def test_run_codex_passes_prompt_on_stdin_and_parses_jsonl(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / "codex"
            argv_file = root / "argv.json"
            stdin_file = root / "stdin.txt"
            make_executable(
                fake,
                "#!/usr/bin/env python3\n"
                "import json, os, pathlib, sys\n"
                "pathlib.Path(os.environ['ARGV_FILE']).write_text(json.dumps(sys.argv[1:]))\n"
                "pathlib.Path(os.environ['STDIN_FILE']).write_text(sys.stdin.read())\n"
                "print(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':'M3_OK'}}))\n",
            )
            prompt = "private prompt body"
            result = run_codex(
                profile="m3",
                worktree=root,
                prompt=prompt,
                runner=ProcessRunner(),
                codex_bin=str(fake),
                env={**os.environ, "ARGV_FILE": str(argv_file), "STDIN_FILE": str(stdin_file)},
                timeout_seconds=5,
            )

            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.agent_messages, ("M3_OK",))
            self.assertEqual(stdin_file.read_text(), prompt)
            self.assertNotIn(prompt, " ".join(json.loads(argv_file.read_text())))

    def test_run_codex_preserves_raw_stdout_for_non_jsonl_output(self) -> None:
        # Measured (E03-R08 H6 self-heal): the real MiniMax-M3 CLI exited
        # nonzero with changed_paths=0 and no JSON event matched any known
        # failure pattern (quota/429/timeout/network/credential/env), so
        # router.py's classify_provider_failure() fell through to the
        # STOPPED catch-all. The state file only ever held that catch-all
        # string — CodexResult never captured process.stdout, only the
        # subset of lines that happened to parse as JSON (run_codex's
        # `except json.JSONDecodeError: continue` silently drops anything
        # else), so a plain-text self-halt line the CLI prints before a
        # non-JSON exit is unrecoverable after the fact. This reproduces
        # that shape directly: a fake CLI that prints one non-JSON
        # diagnostic line, then exits nonzero.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / "codex"
            make_executable(
                fake,
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "sys.stdin.read()\n"
                "print('fatal: MiniMax CLI self-halted before producing a diff')\n"
                "sys.exit(1)\n",
            )
            result = run_codex(
                profile="m3",
                worktree=root,
                prompt="ignore",
                runner=ProcessRunner(),
                codex_bin=str(fake),
                timeout_seconds=5,
            )

            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.events, ())
            self.assertIn(
                "fatal: MiniMax CLI self-halted before producing a diff", result.stdout
            )

    def test_runner_reports_timeout_without_shell(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / "slow"
            make_executable(fake, "#!/usr/bin/env python3\nimport time\ntime.sleep(2)\n")

            result = ProcessRunner().run(
                [str(fake)], input_text="safe", cwd=Path(directory), timeout_seconds=0.05
            )

            self.assertTrue(result.timed_out)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
