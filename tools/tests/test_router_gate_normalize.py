import importlib.util
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODEL_ROUTER_PATH = REPO_ROOT / "tools" / "model-router.py"


def _load_model_router():
    tools_dir = str(REPO_ROOT / "tools")
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
    spec = importlib.util.spec_from_file_location("model_router_under_test", MODEL_ROUTER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class GateNormalizeTest(unittest.TestCase):
    # E02-R21 H4 (Update 7, measured 2026-08-02): the router STOPPED after
    # its whole 2 M3 + 1 Terra budget was spent, with real, ADR-0111-correct
    # production wiring already on disk -- the only failure was `dart format`
    # (RECOVERED_M3_CALL_1/2) and then 3 `unused_import` warnings at
    # test/features/practice/application/practice_production_wiring_test.dart:32,42,47
    # (FINAL_GATE, `analyze`). Both are mechanically fixable and neither
    # needed another model call.

    def make_repo(self) -> tuple[Path, dict[str, str]]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "pubspec.yaml").write_text("name: fake\n", encoding="utf-8")
        (root / "l10n.yaml").write_text("arb-dir: lib/l10n\n", encoding="utf-8")
        for name in ("lib", "test", "tool"):
            (root / name).mkdir()
        (root / "tool" / "check_architecture.dart").write_text("void main() {}\n")
        (root / "tools").mkdir()
        gate_copy = root / "tools" / "round-gate.sh"
        gate_copy.write_bytes((REPO_ROOT / "tools" / "round-gate.sh").read_bytes())
        gate_copy.chmod(gate_copy.stat().st_mode | stat.S_IXUSR)
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        fix_marker = root / ".dart_fix_applied"
        dart = root / "dart"
        flutter = root / "flutter"
        make_executable(
            dart,
            "#!/usr/bin/env python3\n"
            "import os, pathlib, sys\n"
            "args = sys.argv[1:]\n"
            "marker = pathlib.Path(os.environ['FIX_MARKER'])\n"
            "if args[:1] == ['fix']:\n"
            "    marker.write_text('applied')\n"
            "sys.exit(0)\n",
        )
        make_executable(
            flutter,
            "#!/usr/bin/env python3\n"
            "import os, pathlib, sys\n"
            "args = sys.argv[1:]\n"
            "marker = pathlib.Path(os.environ['FIX_MARKER'])\n"
            "l10n_output = pathlib.Path('lib/l10n/app_localizations.dart')\n"
            "if args[:1] == ['gen-l10n']:\n"
            "    l10n_output.parent.mkdir(parents=True, exist_ok=True)\n"
            "    l10n_output.write_text('// generated localization output')\n"
            "if args[:1] == ['analyze']:\n"
            "    if not marker.exists() and not l10n_output.exists():\n"
            "        print(\n"
            "            'test/features/practice/application/'\n"
            "            'practice_production_wiring_test.dart:32:8 - '\n"
            "            \"unused_import: Unused import: 'practice_session_providers.dart'.\"\n"
            "        )\n"
            "        sys.exit(3)\n"
            "sys.exit(0)\n",
        )
        env = {
            **os.environ,
            "FLUTTER_BIN": str(flutter),
            "DART_BIN": str(dart),
            "FIX_MARKER": str(fix_marker),
            "ROUND_GATE_SLEEP_SECONDS": "0",
        }
        return root, env

    def test_pre_gate_normalize_clears_unused_imports_before_analyze_runs(self) -> None:
        module = _load_model_router()
        root, env = self.make_repo()
        old_environ = dict(os.environ)
        os.environ.clear()
        os.environ.update(env)
        try:
            config = module.load_config(REPO_ROOT / ".ai" / "router.toml")
            gate = module._gate_runner(config, module.ProcessRunner())
            result = gate(root, ("test/example_test.dart",), False)
        finally:
            os.environ.clear()
            os.environ.update(old_environ)

        self.assertEqual(result.outcome, "pass", result.log)

    def test_without_normalize_the_same_worktree_would_have_stopped_on_analyze(self) -> None:
        # RED companion: this asserts the gate script alone (the pre-fix
        # behaviour) fails on the unused-import warning when nothing has
        # run `dart fix` first -- proving the normalize step is what turns
        # the FINAL_GATE from `code_failure`/`analyze` into `pass`.
        root, env = self.make_repo()
        gate_script = REPO_ROOT / "tools" / "round-gate.sh"
        result_file = root / "result.json"

        completed = subprocess.run(
            [str(gate_script), "--result-json", str(result_file), "test/example_test.dart"],
            cwd=root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 10)

    def test_baseline_gate_generates_flutter_l10n_without_normalizing(self) -> None:
        # Measured reproduction (E03-R09/H6, 2026-08-03): a fresh Flutter
        # worktree had no ignored lib/l10n/app_localizations*.dart output, so
        # the baseline format passed but analyze emitted 625 errors before a
        # model call.  The baseline must generate Flutter's required l10n
        # output, but must not run the post-model dart fix normalizer.
        module = _load_model_router()
        root, env = self.make_repo()
        old_environ = dict(os.environ)
        os.environ.clear()
        os.environ.update(env)
        try:
            config = module.load_config(REPO_ROOT / ".ai" / "router.toml")
            gate = module._gate_runner(config, module.ProcessRunner(), baseline=True)
            result = gate(root, (), False)
        finally:
            os.environ.clear()
            os.environ.update(old_environ)

        self.assertFalse((root / ".dart_fix_applied").exists())
        self.assertTrue((root / "lib/l10n/app_localizations.dart").exists())
        self.assertEqual(result.outcome, "pass", result.log)


if __name__ == "__main__":
    unittest.main()
