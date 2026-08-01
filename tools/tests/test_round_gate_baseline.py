import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GATE = ROOT / "tools" / "round-gate.sh"


class RoundGateBaselineTest(unittest.TestCase):
    def test_baseline_mode_allows_zero_existing_target_tests(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pubspec.yaml").write_text("name: fake\n")
            for name in ("lib", "test", "tool"):
                (root / name).mkdir()
            (root / "tool" / "check_architecture.dart").write_text("void main() {}\n")
            tool = root / "tool-ok"
            tool.write_text("#!/usr/bin/env python3\nraise SystemExit(0)\n")
            tool.chmod(tool.stat().st_mode | stat.S_IXUSR)
            result_path = root / "result.json"

            completed = subprocess.run(
                [str(GATE), "--result-json", str(result_path), "--baseline"],
                cwd=root,
                env={
                    **os.environ,
                    "FLUTTER_BIN": str(tool),
                    "DART_BIN": str(tool),
                    "ROUND_GATE_SLEEP_SECONDS": "0",
                },
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(json.loads(result_path.read_text())["outcome"], "pass")


if __name__ == "__main__":
    unittest.main()
