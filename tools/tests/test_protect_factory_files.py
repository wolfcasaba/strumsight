"""Contract tests for the PreToolUse measure guard (ADR 0138).

The hook is exercised as a subprocess because that IS its contract: JSON on
stdin, exit 0 = allow, exit 2 = block, stderr = the message the model sees.
"""

import json
import os
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK = REPO_ROOT / ".claude" / "hooks" / "protect_factory_files.py"


class ProtectFactoryFilesTest(unittest.TestCase):
    def run_hook(self, payload: dict, *, escape: bool = False) -> subprocess.CompletedProcess:
        environment = dict(os.environ)
        environment["CLAUDE_PROJECT_DIR"] = str(REPO_ROOT)
        if escape:
            environment["STRUMSIGHT_GATE_EDIT_OK"] = "1"
        else:
            environment.pop("STRUMSIGHT_GATE_EDIT_OK", None)
        return subprocess.run(
            ["python3", str(HOOK)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=environment,
        )

    def edit(self, path: str) -> dict:
        return {"tool_name": "Edit", "tool_input": {"file_path": path}}

    def test_blocks_the_gate_script(self) -> None:
        result = self.run_hook(self.edit(str(REPO_ROOT / "tools/round-gate.sh")))

        self.assertEqual(result.returncode, 2)
        self.assertIn("H-GATEGUARD", result.stderr)

    def test_blocks_ci_workflow_and_ci_checker(self) -> None:
        for relative in (".github/workflows/build-apk.yml", "tool/ci/check_assets.dart"):
            with self.subTest(relative=relative):
                result = self.run_hook(self.edit(str(REPO_ROOT / relative)))
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_blocks_the_router_security_module_and_the_hook_itself(self) -> None:
        for relative in (
            "tools/ai_router/security.py",
            "tools/scope-audit.py",
            ".claude/hooks/protect_factory_files.py",
            ".claude/settings.json",
        ):
            with self.subTest(relative=relative):
                result = self.run_hook(self.edit(str(REPO_ROOT / relative)))
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_blocks_secret_paths_even_with_the_human_escape(self) -> None:
        result = self.run_hook(self.edit(str(REPO_ROOT / ".env")), escape=True)

        self.assertEqual(result.returncode, 2)
        self.assertIn("titok", result.stderr)

    def test_human_escape_allows_measure_edits_and_says_so(self) -> None:
        result = self.run_hook(self.edit(str(REPO_ROOT / "tools/round-gate.sh")), escape=True)

        self.assertEqual(result.returncode, 0)
        self.assertIn("STRUMSIGHT_GATE_EDIT_OK=1", result.stderr)

    def test_allows_the_paths_the_pipeline_itself_must_write(self) -> None:
        # Ha ezek bármelyikét blokkolnánk, a saját csővezetékünk állna meg:
        # a queue-t az orchestrátor írja, a HANDOFF/RTM a kör zárórituáléja.
        for relative in (
            "docs/execution/pipeline-queue.tsv",
            "HANDOFF.md",
            "docs/execution/06-requirements-traceability-matrix.md",
            "docs/rounds/e04-r10-tool-contract-and-registry.md",
            "lib/features/ai_tutor/domain/tools/tutor_tool.dart",
            "test/features/ai_tutor/domain/tutor_tool_registry_test.dart",
        ):
            with self.subTest(relative=relative):
                result = self.run_hook(self.edit(str(REPO_ROOT / relative)))
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_blocks_a_mutating_bash_command_against_the_measure(self) -> None:
        payload = {
            "tool_name": "Bash",
            "tool_input": {"command": "sed -i 's/exit 1/exit 0/' tools/round-gate.sh"},
        }

        result = self.run_hook(payload)

        self.assertEqual(result.returncode, 2, result.stderr)

    def test_allows_a_read_only_bash_command_mentioning_the_measure(self) -> None:
        payload = {
            "tool_name": "Bash",
            "tool_input": {"command": "grep -n analyze tools/round-gate.sh"},
        }

        result = self.run_hook(payload)

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unreadable_payload_blocks_rather_than_allows(self) -> None:
        environment = dict(os.environ)
        environment["CLAUDE_PROJECT_DIR"] = str(REPO_ROOT)
        result = subprocess.run(
            ["python3", str(HOOK)], input="not json", capture_output=True, text=True, env=environment
        )

        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
