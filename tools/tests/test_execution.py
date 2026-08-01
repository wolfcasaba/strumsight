import json
import os
import stat
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.execution import ProcessRunner, build_codex_argv, run_codex


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
