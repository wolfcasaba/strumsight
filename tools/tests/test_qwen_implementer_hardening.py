"""Az implementer-motor (Qwen) MÉRT gyengeségeinek gépi ellenszerei (ADR 0173).

Négy mért hibaminta, négy őr:

1. **„Bejelent és kilép"** — a modell a fordulót a következő lépés
   bejelentésével zárja, munka és jelzés nélkül (E04-R13, E04-R14, E04-R16
   mindkét kísérlete). Ellenszer: a burkoló automatikus folytatása UGYANABBAN a
   session-ben (`codex exec resume`), korlátos számban.
2. **Gondolkodás nélkül futott** — a Kilo-profil fejlécében `reasoning effort:
   none` állt. Ellenszer: motoronkénti `reasoning` oszlop → `-c
   model_reasoning_effort`.
3. **Backend-mérce csak a CI-ban** — `ruff format --check` piros a merge-kapunál
   (E04-R15 MAJOR-1). Ellenszer: a gate backend sávja, ami MAGÁTÓL bekapcsol.
4. **Jelzett, majd tovább futott** — a Codex helyesen írta meg a jelzésfájlt
   (`status=stopped`, scope-sértés), a folyamat mégis tovább dolgozott percekig
   (E06-R23 self-heal, ADR 0112, 2026-08-12: mért eset — a `claude -p`
   folyamat a jelzés UTÁN még hat commitot hozott létre, ~15 perccel később
   lépett csak ki magától). Ellenszer: az őr-ciklus a jelzésfájlt is figyeli,
   és a jelzés UTÁN azonnal kilövi a folyamatot, nem várja meg az
   elakadás-őrt vagy az abszolút időkorlátot.

A tesztek hamis `codex`/`python` binárissal futnak: hálózat és modellhívás
nélkül mérik a burkoló DÖNTÉSEIT (mikor folytat, mit ad át, mit ír a jelzésbe).
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "tools" / "codex-round.sh"
GATE = ROOT / "tools" / "round-gate.sh"
PREAMBLE = ROOT / "docs" / "execution" / "implementer-preamble.md"

SESSION_ID = "019fd369-a3ab-7713-9750-960f66886489"

FAKE_CODEX = """#!/usr/bin/env bash
# Hamis codex: a hívásait rögzíti, és a forgatókönyv szerint viselkedik.
set -uo pipefail
argv_log="$FAKE_CODEX_ARGV"
{
  printf 'CALL'
  for argument in "$@"; do printf '\\t%s' "$argument"; done
  printf '\\n'
} >> "$argv_log"

counter_file="$FAKE_CODEX_COUNTER"
count=$(cat "$counter_file" 2>/dev/null || echo 0)
count=$(( count + 1 ))
printf '%s' "$count" > "$counter_file"

# A valódi Codex a fejlécébe írja a session-azonosítót — a folytatás ebből él.
printf 'OpenAI Codex v0.146.0\\n--------\\nsession id: %s\\n--------\\n' "$FAKE_CODEX_SESSION"
[ -n "${FAKE_CODEX_EXTRA_LOG:-}" ] && printf '%s\\n' "$FAKE_CODEX_EXTRA_LOG"

case "${FAKE_CODEX_MODE:-signal-first}" in
  signal-first)
    [ "${FAKE_CODEX_NO_WORK:-0}" = "1" ] || printf 'munka\\n' >> "$FAKE_CODEX_WORKFILE"
    printf 'status=done\\nsummary=kesz\\n' > "$FAKE_CODEX_SIGNAL"
    ;;
  signal-on-continuation)
    if [ "$count" -ge 2 ]; then
      printf 'munka\\n' >> "$FAKE_CODEX_WORKFILE"
      printf 'status=done\\nsummary=folytatas utan kesz\\n' > "$FAKE_CODEX_SIGNAL"
    else
      printf 'codex\\nNow the action confirmation service, fake executors...\\n'
    fi
    ;;
  never-signal)
    printf 'codex\\nFirst Flutter compile is slow - waiting for the run to finish.\\n'
    ;;
  hang)
    sleep 120
    ;;
  signal-then-hang)
    # MÉRT eset (E06-R23 self-heal, 2026-08-12): a modell helyesen jelez, de a
    # folyamata nem áll le magától — ezt szimulálja a jelzés utáni hosszú sleep.
    printf 'munka\\n' >> "$FAKE_CODEX_WORKFILE"
    printf 'status=stopped\\nsummary=scope-sertes-a-diff-kilogott\\n' > "$FAKE_CODEX_SIGNAL"
    sleep 120
    ;;
esac
exit 0
"""

FAKE_PYTHON = """#!/usr/bin/env bash
set -uo pipefail
{
  printf 'PY'
  for argument in "$@"; do printf '\\t%s' "$argument"; done
  printf '\\n'
} >> "$FAKE_PYTHON_ARGV"
exit 0
"""


def write_executable(path: Path, body: str) -> Path:
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)
    return path


def git(*arguments, cwd):
    return subprocess.run(["git", *arguments], cwd=cwd, capture_output=True, text=True, check=False)


def make_work_copy(directory: Path) -> Path:
    """Minimális git-munkapéldány: a burkoló git-parancsokat futtat rajta."""
    directory.mkdir(parents=True, exist_ok=True)
    git("init", "-q", cwd=directory)
    git("config", "user.email", "test@example.com", cwd=directory)
    git("config", "user.name", "Test", cwd=directory)
    (directory / "README.md").write_text("probe\n", encoding="utf-8")
    git("add", "-A", cwd=directory)
    git("commit", "-q", "-m", "init", cwd=directory)
    return directory


class WrapperContinuationTest(unittest.TestCase):
    """1. hibaminta: „bejelent és kilép"."""

    def run_wrapper(self, mode: str, *, extra_env=None, engine="qwen38-max", timeout=None):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        base = Path(self.directory.name)
        workdir = make_work_copy(base / "work")
        prompt = base / "prompt.md"
        prompt.write_text("Implementer feladat — E09-R01\n", encoding="utf-8")
        log = base / "round.log"
        argv_log = base / "argv.log"
        argv_log.touch()
        fake = write_executable(base / "fake-codex", FAKE_CODEX)

        environment = dict(os.environ)
        environment.update(
            {
                "CODEX_BIN": str(fake),
                "ROUND_ENGINE": engine,
                "FAKE_CODEX_ARGV": str(argv_log),
                "FAKE_CODEX_COUNTER": str(base / "counter"),
                "FAKE_CODEX_SIGNAL": str(workdir / ".codex-round-status"),
                "FAKE_CODEX_WORKFILE": str(workdir / "munka.txt"),
                "FAKE_CODEX_SESSION": SESSION_ID,
                "FAKE_CODEX_MODE": mode,
                "CODEX_MAX_CONTINUATIONS": "2",
                "CODEX_POLL_SECONDS": "1",
            }
        )
        environment.pop("ROUND_BRIEF", None)
        if extra_env:
            environment.update(extra_env)

        result = subprocess.run(
            ["bash", str(WRAPPER), str(workdir), str(prompt), str(log)],
            capture_output=True,
            text=True,
            env=environment,
            cwd=str(ROOT),
            timeout=timeout,
        )
        signal = (workdir / ".codex-round-status").read_text(encoding="utf-8")
        return result, signal, argv_log.read_text(encoding="utf-8"), log.read_text(encoding="utf-8")

    def make_work_copy(self, path: Path) -> Path:  # pragma: no cover - kényelmi alias
        return make_work_copy(path)

    def test_a_clean_first_turn_is_not_continued(self) -> None:
        _result, signal, argv, _log = self.run_wrapper("signal-first")
        self.assertIn("status=done", signal)
        self.assertIn("continuations=0", signal)
        self.assertNotIn("resume", argv)

    def test_an_announced_but_unfinished_turn_is_resumed_in_the_same_session(self) -> None:
        """A mért hibaminta: a folytatás nem újrakezdés, hanem ugyanaz a session."""
        _result, signal, argv, log = self.run_wrapper("signal-on-continuation")
        self.assertIn("status=done", signal)
        self.assertIn("continuations=1", signal)
        self.assertIn(f"session_id={SESSION_ID}", signal)
        resume_calls = [line for line in argv.splitlines() if "\tresume\t" in line]
        self.assertEqual(len(resume_calls), 1, argv)
        self.assertIn(SESSION_ID, resume_calls[0])
        self.assertIn("automatikus folytatás #1", log)

    def test_continuations_are_bounded_and_reported(self) -> None:
        _result, signal, argv, _log = self.run_wrapper("never-signal")
        self.assertIn("status=unknown", signal)
        self.assertIn("continuations=2", signal, "a folytatás nem korlátlan")
        self.assertEqual(len([line for line in argv.splitlines() if "\tresume\t" in line]), 2)

    def test_a_killed_turn_is_never_resumed(self) -> None:
        """Kilövés után a tény a kilövés — a folytatás ott elfedné a hibát."""
        _result, signal, argv, _log = self.run_wrapper(
            "hang", extra_env={"CODEX_ROUND_TIMEOUT": "1", "ENGINE_ROUND_TIMEOUT": "1"}
        )
        self.assertIn("status=timeout", signal)
        self.assertIn("continuations=0", signal)
        self.assertNotIn("resume", argv)

    def test_a_process_that_keeps_running_after_signaling_is_killed_promptly(self) -> None:
        """MÉRT hibaminta (E06-R23 self-heal, ADR 0112, 2026-08-12): a Codex
        helyesen írta meg a `status=stopped` jelzést, de a folyamata ennek
        ellenére percekig futott tovább (hat további commit a jelzés UTÁN).
        A burkolónak a jelzés megjelenése UTÁN azonnal ki kell lőnie a
        folyamatot — nem szabad megvárnia az elakadás-őrt vagy az abszolút
        időkorlátot, amelyek órákig is elérhetnek."""
        started = time.monotonic()
        _result, signal, _argv, _log = self.run_wrapper(
            "signal-then-hang",
            extra_env={"CODEX_POLL_SECONDS": "1", "CODEX_ROUND_TIMEOUT": "600", "ENGINE_ROUND_TIMEOUT": "600"},
            timeout=30,
        )
        elapsed = time.monotonic() - started
        self.assertIn("status=stopped", signal)
        self.assertNotIn("status=timeout", signal, "a jelzés a tény, nem az időtúllépés")
        self.assertLess(
            elapsed, 15,
            "a burkolónak pár másodpercen belül ki kell lőnie a folyamatot a jelzés után, "
            f"nem a 600s-es időkorlátig várnia (mért: {elapsed:.1f}s)",
        )

    def test_the_preamble_is_prepended_to_every_task(self) -> None:
        _result, _signal, argv, _log = self.run_wrapper("signal-first")
        self.assertIn("A forduló a JELZÉSSEL ér véget", argv)

    def test_the_preamble_can_be_switched_off(self) -> None:
        _result, _signal, argv, _log = self.run_wrapper(
            "signal-first", extra_env={"CODEX_NO_PREAMBLE": "1"}
        )
        self.assertNotIn("A forduló a JELZÉSSEL ér véget", argv)

    def test_reasoning_effort_is_passed_only_when_the_registry_declares_one(self) -> None:
        _result, _signal, argv, _log = self.run_wrapper("signal-first", engine="qwen38-max")
        self.assertIn("model_reasoning_effort=medium", argv)

        _result, _signal, argv_plain, _log = self.run_wrapper("signal-first", engine="qwen-plus")
        self.assertNotIn("model_reasoning_effort", argv_plain)


class ClaimGuardTest(WrapperContinuationTest):
    """Anti-hallucináció őrök (2026-08-06): a jelentést a FA igazolja, nem a szöveg."""

    def test_a_done_signal_without_any_work_is_downgraded(self) -> None:
        _result, signal, _argv, _log = self.run_wrapper(
            "signal-first", extra_env={"FAKE_CODEX_NO_WORK": "1"}
        )
        self.assertIn("status=unknown", signal)
        self.assertIn("NEM mozdult", signal)

    def test_a_done_signal_with_real_work_is_kept(self) -> None:
        _result, signal, _argv, _log = self.run_wrapper("signal-first")
        self.assertIn("status=done", signal)

    def test_a_truncated_gate_call_is_reported_in_the_signal(self) -> None:
        """MÉRT M3-hibaminta: a gate `| tail` mögé futtatása (E02-R07, háromszor)."""
        _result, signal, _argv, _log = self.run_wrapper(
            "signal-first",
            extra_env={"FAKE_CODEX_EXTRA_LOG": "tools/round-gate.sh test/x | tail -5"},
        )
        self.assertIn("gate_shape=VIOLATION", signal)

    def test_a_clean_gate_call_is_reported_as_ok(self) -> None:
        _result, signal, _argv, _log = self.run_wrapper(
            "signal-first", extra_env={"FAKE_CODEX_EXTRA_LOG": "tools/round-gate.sh test/x"}
        )
        self.assertIn("gate_shape=ok", signal)


class PreambleContentTest(unittest.TestCase):
    """A preambulum minden pontja MÉRT esetre hivatkozik."""

    def test_every_measured_failure_mode_is_named(self) -> None:
        text = PREAMBLE.read_text(encoding="utf-8")
        for marker in ("E04-R13", "E04-R14", "E04-R16", "E04-R15", "ruff format", "codex-signal.sh"):
            with self.subTest(marker=marker):
                self.assertIn(marker, text)


class BackendGateLaneTest(unittest.TestCase):
    """3. hibaminta: a backend-mérce eddig csak a CI-ban futott."""

    def make_repo(self, directory: Path, *, touch_backend: bool) -> Path:
        make_work_copy(directory)
        (directory / "pubspec.yaml").write_text("name: sandbox\n", encoding="utf-8")
        (directory / "test").mkdir(exist_ok=True)
        backend = directory / "backend"
        (backend / "app").mkdir(parents=True, exist_ok=True)
        (backend / "tests").mkdir(parents=True, exist_ok=True)
        (backend / "app" / "main.py").write_text("x = 1\n", encoding="utf-8")
        git("add", "-A", cwd=directory)
        git("commit", "-q", "-m", "backend", cwd=directory)
        if touch_backend:
            (backend / "app" / "main.py").write_text("x = 2\n", encoding="utf-8")
        return directory

    def gate_env(self, directory: Path, **overrides) -> dict:
        environment = dict(os.environ)
        environment.update(
            {
                "FLUTTER_BIN": "/bin/true",
                "DART_BIN": "/bin/true",
                "ROUND_GATE_SLEEP_SECONDS": "0",
                "ROUND_GATE_LOCK": str(directory / "gate.lock"),
                "HOME": str(directory / "fake-home"),
            }
        )
        environment.update(overrides)
        (directory / "fake-home").mkdir(exist_ok=True)
        return environment

    def test_plan_reports_skip_without_backend_changes(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            directory = self.make_repo(Path(name), touch_backend=False)
            result = subprocess.run(
                ["bash", str(GATE), "--backend-plan"],
                cwd=str(directory),
                capture_output=True,
                text=True,
                env=self.gate_env(directory),
            )
            self.assertEqual(result.stdout.strip(), "skip")

    def test_plan_reports_run_when_the_round_touched_the_backend(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            directory = self.make_repo(Path(name), touch_backend=True)
            result = subprocess.run(
                ["bash", str(GATE), "--backend-plan"],
                cwd=str(directory),
                capture_output=True,
                text=True,
                env=self.gate_env(directory),
            )
            self.assertEqual(result.stdout.strip(), "run")

    def test_backend_round_runs_ruff_format_check_and_pytest(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            directory = self.make_repo(Path(name), touch_backend=True)
            argv_log = directory / "python-argv.log"
            argv_log.touch()
            stub = write_executable(directory / "fake-python", FAKE_PYTHON)
            environment = self.gate_env(
                directory,
                ROUND_GATE_BACKEND_PYTHON=str(stub),
                FAKE_PYTHON_ARGV=str(argv_log),
            )
            result = subprocess.run(
                ["bash", str(GATE), "test/example"],
                cwd=str(directory),
                capture_output=True,
                text=True,
                env=environment,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = argv_log.read_text(encoding="utf-8")
            self.assertIn("ruff\tformat\t--check", calls)
            self.assertIn("ruff\tcheck", calls)
            self.assertIn("pytest", calls)

    def test_missing_backend_venv_is_an_environment_failure_not_a_silent_skip(self) -> None:
        """Fail-closed: mérhetetlen mérce nem lehet zöld."""
        with tempfile.TemporaryDirectory() as name:
            directory = self.make_repo(Path(name), touch_backend=True)
            result_json = directory / "result.json"
            environment = self.gate_env(
                directory, ROUND_GATE_BACKEND_PYTHON=str(directory / "nincs-ilyen")
            )
            result = subprocess.run(
                ["bash", str(GATE), "--result-json", str(result_json), "test/example"],
                cwd=str(directory),
                capture_output=True,
                text=True,
                env=environment,
            )
            self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
            payload = json.loads(result_json.read_text(encoding="utf-8"))
            self.assertEqual(payload["failed_step"], "preflight.backend")

    def test_a_dart_only_round_does_not_pay_for_the_backend_lane(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            directory = self.make_repo(Path(name), touch_backend=False)
            argv_log = directory / "python-argv.log"
            argv_log.touch()
            stub = write_executable(directory / "fake-python", FAKE_PYTHON)
            environment = self.gate_env(
                directory,
                ROUND_GATE_BACKEND_PYTHON=str(stub),
                FAKE_PYTHON_ARGV=str(argv_log),
            )
            result = subprocess.run(
                ["bash", str(GATE), "test/example"],
                cwd=str(directory),
                capture_output=True,
                text=True,
                env=environment,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(argv_log.read_text(encoding="utf-8"), "")


if __name__ == "__main__":
    unittest.main()
