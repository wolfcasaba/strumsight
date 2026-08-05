import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class RoundPipelineFallbackTest(unittest.TestCase):
    def test_terra_fallback_activates_when_claude_weekly_limit(self) -> None:
        """A live Claude limit log must end the tmux wait before its deadline."""
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            bin_dir = directory / "bin"
            state_dir = directory / "state"
            bin_dir.mkdir()
            state_dir.mkdir()
            session_log = state_dir / "claude.log"
            signal_file = state_dir / "round-status"
            events_file = state_dir / "tmux-events"
            prompt_file = directory / "prompt.md"
            prompt_file.write_text("# Pipeline fallback fixture\n")

            fake_tmux = bin_dir / "tmux"
            fake_tmux.write_text(
                "#!/usr/bin/env bash\n"
                "set -eu\n"
                "state=${FAKE_TMUX_STATE:?}\n"
                "case \"$1\" in\n"
                "  kill-session) rm -f \"$state/session-${3}\" ;;\n"
                "  new-session) touch \"$state/session-${4}\" ;;\n"
                "  has-session) test -f \"$state/session-${3}\" ;;\n"
                "  pipe-pane) printf '%s' \"${5#cat >> }\" > \"$state/log-${3}\" ;;\n"
                "  send-keys)\n"
                "    session=$3\n"
                "    command=$4\n"
                "    printf '%s\\n' \"$session:$command\" >> \"$FAKE_TMUX_EVENTS\"\n"
                "    if [[ $command == *\"$FAKE_CLAUDE_BIN\"* ]]; then\n"
                "      printf '%s\\n' 'Claude usage limit reached; limit will reset tomorrow.' >> \"$(cat \"$state/log-$session\")\"\n"
                "    else\n"
                "      printf '%s\\n' 'outcome=merged' 'summary=Terra fallback completed' > \"$FAKE_SIGNAL_FILE\"\n"
                "    fi\n"
                "    ;;\n"
                "  list-panes) printf '%s\\n' '/dev/pts/999' ;;\n"
                "  *) echo \"unexpected tmux call: $*\" >&2; exit 1 ;;\n"
                "esac\n"
            )
            fake_tmux.chmod(0o755)

            fake_sleep = bin_dir / "sleep"
            fake_sleep.write_text(
                "#!/usr/bin/env bash\n"
                "/bin/sleep 0.05\n"
            )
            fake_sleep.chmod(0o755)
            for name in ("fake-claude", "fake-codex"):
                binary = bin_dir / name
                binary.write_text("#!/usr/bin/env bash\nexit 0\n")
                binary.chmod(0o755)

            source_functions = (
                "source <(sed -n '1,/^# --- Önjavítás/p' \"$PIPELINE_SCRIPT\")\n"
                f"repo_root={ROOT}\n"
                f"run_orchestrator_session pipeline-E03-R09 {prompt_file} "
                f"{session_log} {signal_file} 5 E03-R09\n"
            )
            environment = dict(os.environ)
            environment.update(
                PATH=f"{bin_dir}:{environment['PATH']}",
                PIPELINE_SCRIPT=str(script),
                PIPELINE_STATE_DIR=str(state_dir),
                CLAUDE_BIN=str(bin_dir / "fake-claude"),
                CODEX_BIN=str(bin_dir / "fake-codex"),
                FAKE_CLAUDE_BIN=str(bin_dir / "fake-claude"),
                FAKE_TMUX_STATE=str(state_dir),
                FAKE_TMUX_EVENTS=str(events_file),
                FAKE_SIGNAL_FILE=str(signal_file),
            )

            started = time.monotonic()
            completed = subprocess.run(
                ["bash", "-c", source_functions],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            elapsed = time.monotonic() - started

            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertLess(elapsed, 2, completed.stdout + completed.stderr)
            self.assertTrue((state_dir / "claude-blocked-until").exists())
            events = events_file.read_text()
            self.assertIn("pipeline-E03-R09-fallback:", events)
            # Keretkímélés (user-döntés 2026-08-04): a Claude-session indító
            # parancsa explicit effort-szintet visz — a session-default agentic
            # munkán a legmagasabb sáv felé húz, ami a heti keretet égeti.
            claude_launch = next(
                line for line in events.splitlines() if "fake-claude" in line
            )
            self.assertIn("--effort medium", claude_launch)


class SessionConfigTest(unittest.TestCase):
    """A kör- és önjavító session modell/effort-beállítása mérhető szerződés.

    User-döntés 2026-08-04 (keretkímélés): a kör-orchestrátor Opus 4.8 marad
    (terv + review + merge-kapu), de effort=medium; az önjavító session
    Sonnet 5 (infrastruktúra-diagnózis, nem termékítélet). Az Opus-vonalon
    belüli "olcsóbb modell" (4.6) NEM spórolna: azonos tokenár, 4096-os
    cache-minimum, nincs xhigh — a valódi kar az effort és a heal-modell.
    """

    def _config(self, kind: str, env: dict | None = None) -> str:
        script = ROOT / "tools" / "round-pipeline.sh"
        environment = dict(os.environ)
        environment.update(env or {})
        completed = subprocess.run(
            ["bash", str(script), "--session-config", kind],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        return completed.stdout.strip()

    def test_round_orchestrator_runs_opus_48_at_medium_effort(self) -> None:
        self.assertEqual(
            self._config("round", {"PIPELINE_MODEL": "", "PIPELINE_EFFORT": ""}),
            "model=claude-opus-4-8 effort=medium",
        )

    def test_selfheal_runs_opus_48_at_medium_effort(self) -> None:
        # User-döntés 2026-08-05: az orchestrátor MINDEN székben Opus 4.8 — a
        # heal-kör is ítéletet hoz (gyökérok-osztályozás, motorválasztás), nem
        # csak infrastruktúra-diagnózist.
        self.assertEqual(
            self._config("heal", {"PIPELINE_SELFHEAL_MODEL": "", "PIPELINE_EFFORT": ""}),
            "model=claude-opus-4-8 effort=medium",
        )

    def test_selfheal_model_stays_operator_overridable(self) -> None:
        self.assertEqual(
            self._config(
                "heal",
                {"PIPELINE_SELFHEAL_MODEL": "claude-sonnet-5", "PIPELINE_EFFORT": ""},
            ),
            "model=claude-sonnet-5 effort=medium",
        )

    def test_env_overrides_stay_operator_controllable(self) -> None:
        self.assertEqual(
            self._config(
                "round", {"PIPELINE_MODEL": "claude-opus-5", "PIPELINE_EFFORT": "high"}
            ),
            "model=claude-opus-5 effort=high",
        )


class ClaudeProcessLivenessTest(unittest.TestCase):
    """A pane-liveness heurisztika a VALÓDI process-neveket kell hogy ismerje.

    Mért reprodukció (2026-08-04): a PR #84 óta a check a `claude-code` comm-ra
    illesztett, miközben ezen a boxon a `ps -o comm=` mért értéke `claude`
    (launcher) vagy `claude.exe` (node bináris). Következmény: a 10s-es türelmi
    idő után minden ÉLŐ Claude-session „kvótahalálnak" minősült, 5 órás
    motorzárlattal — `.pipeline/chain.log`-ban 6 hamis pozitív
    2026-08-03T13:35 és 2026-08-04T08:20 között, azaz a lánc soha nem futott
    Claude-on, hiába volt kvóta.
    """

    def _matches(self, comm: str) -> bool:
        script = ROOT / "tools" / "round-pipeline.sh"
        completed = subprocess.run(
            ["bash", str(script), "--claude-process-comm-check", comm],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        return completed.returncode == 0

    def test_measured_claude_process_names_count_as_alive(self) -> None:
        for comm in ("claude", "claude.exe", "claude-code"):
            with self.subTest(comm=comm):
                self.assertTrue(self._matches(comm))

    def test_unrelated_processes_do_not_count_as_alive(self) -> None:
        for comm in ("bash", "node", "codex", "tmux", "claudette", "", "my-claude"):
            with self.subTest(comm=comm):
                self.assertFalse(self._matches(comm))


if __name__ == "__main__":
    unittest.main()
