import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GATE = REPO_ROOT / "tools" / "round-gate.sh"


def make_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class RoundGateTest(unittest.TestCase):
    def make_repo(self, flutter_body: str | None = None) -> tuple[Path, dict[str, str]]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "pubspec.yaml").write_text("name: fake\n", encoding="utf-8")
        for name in ("lib", "test", "tool"):
            (root / name).mkdir()
        (root / "tool" / "check_architecture.dart").write_text("void main() {}\n")
        log = root / "commands.jsonl"
        dart = root / "dart"
        flutter = root / "flutter"
        make_executable(
            dart,
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['COMMAND_LOG'], 'a') as f: f.write(json.dumps(['dart', *sys.argv[1:]])+'\\n')\n",
        )
        make_executable(
            flutter,
            flutter_body
            or "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['COMMAND_LOG'], 'a') as f: f.write(json.dumps(['flutter', *sys.argv[1:]])+'\\n')\n",
        )
        env = {
            **os.environ,
            "FLUTTER_BIN": str(flutter),
            "DART_BIN": str(dart),
            "COMMAND_LOG": str(log),
            "ROUND_GATE_SLEEP_SECONDS": "0",
        }
        return root, env

    def test_writes_structured_pass_result(self) -> None:
        root, env = self.make_repo()
        result_file = root / "result.json"

        completed = subprocess.run(
            [str(GATE), "--result-json", str(result_file), "test/example_test.dart"],
            cwd=root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(result_file.read_text())
        self.assertEqual(result["schema_version"], 1)
        self.assertEqual(result["outcome"], "pass")
        self.assertEqual(result["exit_code"], 0)
        commands = [json.loads(line) for line in (root / "commands.jsonl").read_text().splitlines()]
        self.assertIn(["flutter", "test", "test/example_test.dart"], commands)

    def test_code_failure_has_stable_router_exit(self) -> None:
        root, env = self.make_repo(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "with open(os.environ['COMMAND_LOG'], 'a') as f: f.write(json.dumps(['flutter', *sys.argv[1:]])+'\\n')\n"
            "raise SystemExit(7 if sys.argv[1:2] == ['analyze'] else 0)\n"
        )
        result_file = root / "result.json"

        completed = subprocess.run(
            [str(GATE), "--result-json", str(result_file), "test/example_test.dart"],
            cwd=root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 10)
        result = json.loads(result_file.read_text())
        self.assertEqual(result["outcome"], "code_failure")
        self.assertEqual(result["failed_step"], "analyze")
        self.assertEqual(result["command_exit_code"], 7)
        self.assertRegex(result["error_hash"], r"^sha256:[0-9a-f]{64}$")

    def test_missing_tool_is_environment_failure(self) -> None:
        root, env = self.make_repo()
        env["FLUTTER_BIN"] = str(root / "missing-flutter")
        result_file = root / "result.json"

        completed = subprocess.run(
            [str(GATE), "--result-json", str(result_file), "test/example_test.dart"],
            cwd=root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 20)
        self.assertEqual(json.loads(result_file.read_text())["outcome"], "environment_failure")

    def test_no_test_path_is_invalid_gate(self) -> None:
        root, env = self.make_repo()
        result_file = root / "result.json"

        completed = subprocess.run(
            [str(GATE), "--result-json", str(result_file)],
            cwd=root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 30)
        self.assertEqual(json.loads(result_file.read_text())["outcome"], "invalid_gate")

    def test_result_path_may_come_from_environment(self) -> None:
        root, env = self.make_repo()
        result_file = root / "result.json"
        env["ROUND_GATE_RESULT_FILE"] = str(result_file)

        completed = subprocess.run(
            [str(GATE), "test/example_test.dart"],
            cwd=root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(json.loads(result_file.read_text())["outcome"], "pass")


if __name__ == "__main__":
    unittest.main()
