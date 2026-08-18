"""Az implementer-őr hook mérése (ADR 0309).

Minden eset egy MÉRT hibaosztályt képvisel; a hook szerződése:
exit 0 = engedélyez, exit 2 = blokkol, a stderr a modellhez megy.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
HOOK = REPO_ROOT / "tools" / "hooks" / "implementer_guard.py"
SETTINGS = REPO_ROOT / "tools" / "implementer-settings.json"
WRAPPER = REPO_ROOT / "tools" / "mm-round.sh"

BRIEF = """# E99-R99 — próbakör

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/demo/widget.dart",
  "test/fixtures/demo/",
  "docs/rounds/e99-r99-demo.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```
"""


def run_hook(payload: dict, *, project: Path, env: dict | None = None) -> subprocess.CompletedProcess:
    environment = dict(os.environ)
    environment.pop("STRUMSIGHT_ROUND_BRIEF", None)
    environment["CLAUDE_PROJECT_DIR"] = str(project)
    environment.update(env or {})
    return subprocess.run(
        ["python3", str(HOOK)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        env=environment,
        timeout=120,
    )


class ImplementerGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.project = Path(self._tmp.name)
        brief = self.project / "docs" / "rounds" / "e99-r99-demo.md"
        brief.parent.mkdir(parents=True)
        brief.write_text(BRIEF, encoding="utf-8")
        self.round_env = {
            "STRUMSIGHT_ROUND_BRIEF": "docs/rounds/e99-r99-demo.md",
            "STRUMSIGHT_ROUND_ID": "E99-R99",
        }
        self.addCleanup(self._tmp.cleanup)

    def write_payload(self, path: str, *, tool: str = "Write") -> dict:
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": tool,
            "tool_input": {"file_path": path},
            "cwd": str(self.project),
        }

    def bash_payload(self, command: str) -> dict:
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": command},
            "cwd": str(self.project),
        }

    # --- kapcsoló ---------------------------------------------------------

    def test_no_op_outside_an_implementer_round(self) -> None:
        """Orchesztrátor- és interaktív session: a hook nem szól bele semmibe."""
        result = run_hook(self.write_payload("lib/tilos.dart"), project=self.project)
        self.assertEqual(result.returncode, 0, result.stderr)

    # --- scope (fail-closed) ---------------------------------------------

    def test_write_inside_allowed_paths_passes(self) -> None:
        result = run_hook(
            self.write_payload("lib/features/demo/widget.dart"),
            project=self.project,
            env=self.round_env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_write_inside_an_allowed_directory_passes(self) -> None:
        result = run_hook(
            self.write_payload("test/fixtures/demo/case_one.json"),
            project=self.project,
            env=self.round_env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_write_outside_allowed_paths_is_blocked_with_the_stop_protocol(self) -> None:
        """MÉRT hibaosztály: a listán kívül létrehozott fájl javító körré vált."""
        result = run_hook(
            self.write_payload("lib/features/demo/extra_helper.dart"),
            project=self.project,
            env=self.round_env,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("codex-signal.sh stopped", result.stderr)

    def test_multiedit_targets_are_checked_too(self) -> None:
        payload = {
            "hook_event_name": "PreToolUse",
            "tool_name": "MultiEdit",
            "tool_input": {"edits": [{"file_path": "lib/features/demo/widget.dart"},
                                     {"file_path": "lib/other/sneaky.dart"}]},
            "cwd": str(self.project),
        }
        result = run_hook(payload, project=self.project, env=self.round_env)
        self.assertEqual(result.returncode, 2)

    def test_unparseable_brief_fails_closed(self) -> None:
        (self.project / "docs" / "rounds" / "e99-r99-demo.md").write_text("nincs blokk", encoding="utf-8")
        result = run_hook(
            self.write_payload("lib/features/demo/widget.dart"),
            project=self.project,
            env=self.round_env,
        )
        self.assertEqual(result.returncode, 2)

    # --- tiltott parancsalakok -------------------------------------------

    def test_forbidden_bash_shapes_are_blocked(self) -> None:
        forbidden = (
            "tools/round-gate.sh test/x_test.dart | tail -20",
            "tools/round-gate.sh test/x_test.dart &",
            "flutter analyze lib/ && flutter test test/x_test.dart",
            "git stash push -u",
            "git push origin HEAD:branch --force",
            "pip install pytest",
            "git -C /home/ubuntu/music-theory checkout main",
        )
        for command in forbidden:
            with self.subTest(command=command):
                result = run_hook(self.bash_payload(command), project=self.project, env=self.round_env)
                self.assertEqual(result.returncode, 2, f"átengedve: {command}")
                self.assertIn("IMPLEMENTER-ŐR", result.stderr)

    def test_legitimate_bash_passes(self) -> None:
        allowed = (
            "tools/round-gate.sh test/x_test.dart",
            "flutter test test/x_test.dart",
            "git add -A && git commit -m 'E99-R99: widget'",
            "tools/safe-force-push.sh origin HEAD:branch",
            "grep -rn 'foo' lib | head -5",
        )
        for command in allowed:
            with self.subTest(command=command):
                result = run_hook(self.bash_payload(command), project=self.project, env=self.round_env)
                self.assertEqual(result.returncode, 0, f"blokkolva: {command} — {result.stderr}")

    # --- lezáró jelzés ----------------------------------------------------

    def test_stop_without_a_signal_is_blocked_but_bounded(self) -> None:
        """H-NOSIGNAL: 18 önjavító kör, a két self-heal-kimerülés mindkettő ez."""
        payload = {"hook_event_name": "Stop", "cwd": str(self.project)}
        first = run_hook(payload, project=self.project, env=self.round_env)
        second = run_hook(payload, project=self.project, env=self.round_env)
        third = run_hook(payload, project=self.project, env=self.round_env)
        self.assertEqual(first.returncode, 2)
        self.assertIn("codex-signal.sh done", first.stderr)
        self.assertEqual(second.returncode, 2)
        self.assertEqual(third.returncode, 0, "az őr nem korlátos — végtelen ciklus veszélye")

    def test_stop_with_a_terminal_signal_passes(self) -> None:
        (self.project / ".codex-round-status").write_text(
            "round=E99-R99\nstatus=done\n", encoding="utf-8"
        )
        result = run_hook({"hook_event_name": "Stop", "cwd": str(self.project)},
                          project=self.project, env=self.round_env)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_stop_with_a_progress_only_signal_is_blocked(self) -> None:
        (self.project / ".codex-round-status").write_text(
            "round=E99-R99\nstatus=progress\n", encoding="utf-8"
        )
        result = run_hook({"hook_event_name": "Stop", "cwd": str(self.project)},
                          project=self.project, env=self.round_env)
        self.assertEqual(result.returncode, 2)

    # --- formázás ---------------------------------------------------------

    def test_post_tool_use_never_blocks(self) -> None:
        target = self.project / "lib" / "features" / "demo"
        target.mkdir(parents=True)
        (target / "widget.dart").write_text("class A {}\n", encoding="utf-8")
        payload = {
            "hook_event_name": "PostToolUse",
            "tool_name": "Write",
            "tool_input": {"file_path": "lib/features/demo/widget.dart"},
            "cwd": str(self.project),
        }
        env = dict(self.round_env)
        env["DART_BIN"] = "/bin/true"
        result = run_hook(payload, project=self.project, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)


class GuardWiringTest(unittest.TestCase):
    """A hook csak akkor ér valamit, ha a burkoló tényleg betölti."""

    def test_settings_register_every_guarded_event(self) -> None:
        settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
        for event in ("PreToolUse", "PostToolUse", "Stop"):
            with self.subTest(event=event):
                entries = settings["hooks"][event]
                commands = [
                    hook["command"]
                    for entry in entries
                    for hook in entry["hooks"]
                ]
                self.assertTrue(
                    any("tools/hooks/implementer_guard.py" in command for command in commands),
                    f"{event}: nincs bekötve az implementer-őr",
                )

    def test_wrapper_loads_the_settings_and_exports_the_brief(self) -> None:
        wrapper = WRAPPER.read_text(encoding="utf-8")
        self.assertIn("--settings", wrapper)
        self.assertIn("STRUMSIGHT_ROUND_BRIEF", wrapper)
        self.assertIn("implementer-settings.json", wrapper)

    def test_guard_is_backwards_compatible_when_the_files_are_missing(self) -> None:
        """Régi kör-ágon (a fájlok nélkül) a burkoló viselkedése változatlan."""
        wrapper = WRAPPER.read_text(encoding="utf-8")
        self.assertIn('[ -f "$guard_settings" ]', wrapper)
        self.assertIn('[ -f "$guard_hook" ]', wrapper)


if __name__ == "__main__":
    unittest.main()


class ScopeAuditWiringTest(unittest.TestCase):
    """A kör utáni audit némán kimaradt, ha a hívó nem adott ROUND_BRIEF-et."""

    def test_wrapper_exports_round_brief_for_the_post_round_audit(self) -> None:
        wrapper = WRAPPER.read_text(encoding="utf-8")
        self.assertIn('export ROUND_BRIEF="$round_brief"', wrapper)


class EngineSettingsWiringTest(unittest.TestCase):
    """A nyilvántartás oszlopai ne maradjanak holt konfigurációk."""

    def test_wrapper_passes_the_registry_max_output(self) -> None:
        wrapper = WRAPPER.read_text(encoding="utf-8")
        self.assertIn("CLAUDE_CODE_MAX_OUTPUT_TOKENS", wrapper)
        self.assertIn("ENGINE_MAX_OUTPUT", wrapper)

    def test_wrapper_passes_the_round_auditor_agent(self) -> None:
        wrapper = WRAPPER.read_text(encoding="utf-8")
        self.assertIn("--agents", wrapper)
        self.assertIn("implementer-agents.json", wrapper)

    def test_round_auditor_asks_the_three_measured_questions(self) -> None:
        agents = json.loads((REPO_ROOT / "tools" / "implementer-agents.json").read_text(encoding="utf-8"))
        auditor = agents["round-auditor"]
        prompt = auditor["prompt"]
        for needle in ("allowed_paths", "acceptance", "AUDIT: OK", "AUDIT: LELET"):
            with self.subTest(needle=needle):
                self.assertIn(needle, prompt.replace("§6 acceptance", "acceptance"))
        self.assertIn("description", auditor)

    def test_preamble_names_the_auditor_agent(self) -> None:
        preamble = (REPO_ROOT / "docs" / "execution" / "implementer-preamble-minimax.md").read_text(encoding="utf-8")
        self.assertIn("round-auditor", preamble)
