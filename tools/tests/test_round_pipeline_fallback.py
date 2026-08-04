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
            self.assertIn("pipeline-E03-R09-fallback:", events_file.read_text())


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
