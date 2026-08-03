import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "prepare-flutter-generated.sh"


class PrepareFlutterGeneratedTest(unittest.TestCase):
    def test_generates_ignored_l10n_output_after_package_resolution(self) -> None:
        # Measured E03-R14/H7 input: a clean merge checkout has no ignored
        # AppLocalizations output. The pre-fix post-merge gate therefore
        # analyzed stale/missing getters rather than the merged ARB surface.
        with tempfile.TemporaryDirectory() as directory_name:
            root = Path(directory_name)
            tools = root / "tools"
            tools.mkdir()
            script = tools / SCRIPT.name
            script.write_bytes(SCRIPT.read_bytes())
            script.chmod(script.stat().st_mode | stat.S_IXUSR)
            (root / "pubspec.yaml").write_text("name: fake\n", encoding="utf-8")
            (root / "l10n.yaml").write_text("arb-dir: lib/l10n\n", encoding="utf-8")
            flutter = root / "flutter"
            log = root / "commands.log"
            flutter.write_text(
                "#!/usr/bin/env python3\n"
                "import os, pathlib, sys\n"
                "with open(os.environ['COMMAND_LOG'], 'a', encoding='utf-8') as output:\n"
                "    output.write(' '.join(sys.argv[1:]) + '\\n')\n"
                "if sys.argv[1:] == ['gen-l10n']:\n"
                "    generated = pathlib.Path('lib/l10n/app_localizations.dart')\n"
                "    generated.parent.mkdir(parents=True, exist_ok=True)\n"
                "    generated.write_text('// generated', encoding='utf-8')\n",
                encoding="utf-8",
            )
            flutter.chmod(flutter.stat().st_mode | stat.S_IXUSR)

            completed = subprocess.run(
                [str(script)],
                cwd=root,
                env={**os.environ, "FLUTTER_BIN": str(flutter), "COMMAND_LOG": str(log)},
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(log.read_text(encoding="utf-8").splitlines(), ["pub get", "gen-l10n"])
            self.assertTrue((root / "lib/l10n/app_localizations.dart").exists())

    def test_skips_generation_when_no_l10n_configuration_exists(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            root = Path(directory_name)
            tools = root / "tools"
            tools.mkdir()
            script = tools / SCRIPT.name
            script.write_bytes(SCRIPT.read_bytes())
            script.chmod(script.stat().st_mode | stat.S_IXUSR)
            (root / "pubspec.yaml").write_text("name: fake\n", encoding="utf-8")
            flutter = root / "flutter"
            log = root / "commands.log"
            flutter.write_text(
                "#!/usr/bin/env python3\n"
                "import os, sys\n"
                "with open(os.environ['COMMAND_LOG'], 'a', encoding='utf-8') as output:\n"
                "    output.write(' '.join(sys.argv[1:]) + '\\n')\n",
                encoding="utf-8",
            )
            flutter.chmod(flutter.stat().st_mode | stat.S_IXUSR)

            completed = subprocess.run(
                [str(script)],
                cwd=root,
                env={**os.environ, "FLUTTER_BIN": str(flutter), "COMMAND_LOG": str(log)},
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(log.read_text(encoding="utf-8").splitlines(), ["pub get"])
