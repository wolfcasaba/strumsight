"""Contract tests for the PreToolUse measure guard (ADR 0138).

The hook is exercised as a subprocess because that IS its contract: JSON on
stdin, exit 0 = allow, exit 2 = block, stderr = the message the model sees.
"""

import json
import os
import subprocess
import tempfile
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


class BashWriteTargetTest(unittest.TestCase):
    """Only the WRITE TARGET counts — mentioning a protected path is not a write.

    Measured 2026-08-05 (docs/LESSONS.md L117): the first version scanned every
    token, so appending a lesson whose text mentioned the measure, running the
    guard's own test, and committing the change were all blocked.
    """

    def run_hook(self, command: str) -> subprocess.CompletedProcess:
        environment = dict(os.environ)
        environment["CLAUDE_PROJECT_DIR"] = str(REPO_ROOT)
        environment.pop("STRUMSIGHT_GATE_EDIT_OK", None)
        return subprocess.run(
            ["python3", str(HOOK)],
            input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
            capture_output=True,
            text=True,
            env=environment,
        )

    def assertBlocked(self, command: str) -> None:
        self.assertEqual(self.run_hook(command).returncode, 2, f"nem blokkolt: {command}")

    def assertAllowed(self, command: str) -> None:
        result = self.run_hook(command)
        self.assertEqual(result.returncode, 0, f"tévesen blokkolt: {command}\n{result.stderr}")

    def test_writes_to_the_measure_are_blocked(self) -> None:
        for command in (
            "echo x > tools/round-gate.sh",
            "echo x >tools/round-gate.sh",
            "echo x >> .github/workflows/build-apk.yml",
            "sed -i 's/a/b/' tools/round-gate.sh",
            "cat new.yml | tee .github/actions/flutter-gates/action.yml",
            "cp /tmp/x.py tools/ai_router/security.py",
            "mv /tmp/x.py tools/model-router.py",
            "install /tmp/x.sh tools/round-scope-audit.sh",
            "rm tools/round-gate.sh",
            "chmod +x tool/ci/check_assets.dart",
            # könyvtár-célpont: a fájl-globok önmagukban nem fognák
            "cp -t .github/workflows /tmp/x.yml",
            "rm -rf tool/ci",
        ):
            with self.subTest(command=command):
                self.assertBlocked(command)

    def test_merely_mentioning_the_measure_is_allowed(self) -> None:
        for command in (
            # A saját dokumentálásunk: a SZÖVEG említi a mércét, az ÍRÁS máshova megy.
            "cat >> docs/LESSONS.md <<'EOF'\nlásd tools/round-gate.sh\nEOF",
            "git commit -m 'feat: tools/round-gate.sh mellé új kapu'",
            "git add tools/ai_router/legacy_scope.py",
            "grep -rn analyze tools/round-gate.sh",
            "bash tools/round-scope-audit.sh /tmp/probe abc123 /tmp/probe/.codex-round-status",
            "python3 -m unittest tools.tests.test_protect_factory_files",
            "diff /tmp/new.yml .github/workflows/build-apk.yml",
            "cp .github/workflows/build-apk.yml /tmp/backup.yml",
        ):
            with self.subTest(command=command):
                self.assertAllowed(command)

    def test_unparseable_command_does_not_crash_the_guard(self) -> None:
        # Lezáratlan idézőjel: nem elemezhető, de a hook nem hal meg.
        self.assertIn(self.run_hook("echo 'unterminated > tools/round-gate.sh").returncode, (0, 2))


class MarkerEscapeTest(unittest.TestCase):
    """The human escape must be usable from inside a running session (L117)."""

    def run_hook(self, project: Path, target: Path) -> subprocess.CompletedProcess:
        environment = dict(os.environ)
        environment["CLAUDE_PROJECT_DIR"] = str(project)
        environment.pop("STRUMSIGHT_GATE_EDIT_OK", None)
        return subprocess.run(
            ["python3", str(HOOK)],
            input=json.dumps({"tool_name": "Edit", "tool_input": {"file_path": str(target)}}),
            capture_output=True,
            text=True,
            env=environment,
        )

    def test_marker_file_authorizes_measure_edits_and_names_the_reason(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            project = Path(directory_name)
            (project / ".claude").mkdir()
            (project / ".claude" / "gate-edit-authorized").write_text(
                "GOV-03: user-engedély a factory-hardening kapukhoz\n"
            )

            result = self.run_hook(project, project / "tools" / "round-gate.sh")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("GOV-03", result.stderr)

    def test_without_the_marker_the_same_edit_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            project = Path(directory_name)

            result = self.run_hook(project, project / "tools" / "round-gate.sh")

            self.assertEqual(result.returncode, 2)

    def test_marker_never_unlocks_secret_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            project = Path(directory_name)
            (project / ".claude").mkdir()
            (project / ".claude" / "gate-edit-authorized").write_text("bármi\n")

            result = self.run_hook(project, project / ".env")

            self.assertEqual(result.returncode, 2)
            self.assertIn("titok", result.stderr)


if __name__ == "__main__":
    unittest.main()
