import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class RoundPipelineFallbackEngineExitTest(unittest.TestCase):
    """A Codex/Terra fallback-ágon a pane EGYETLEN előtér-parancsot kap
    (`codex exec …`). Ha az a folyamat magától, jelzésfájl nélkül kilép, a
    tmux-session — a mögötte élő üres shell miatt — ÉLETBEN marad: a
    `has-session` ellenőrzés ezt sosem kapja el.

    Mért eset (E99-R13 H-NOSIGNAL önjavítás, 2026-08-15): a `codex exec`
    process 11:03:26-kor lépett ki, a session-napló utolsó írása is ekkor
    történt, de a driver csak a 20 perces log-elakadás-őrnél, 11:23:38-kor
    ismerte fel a hiányzó jelzést — a Claude-ágnak már volt pane-process-
    ellenőrzése (kvóta-célra), a Codex/Terra fallback-ágnak nem.

    Ez a teszt egy olyan pane-t szimulál, ahol a `ps -t <pane_tty>` már NEM
    listázza a motor process-ét (csak az üres shellt) — a `run_tmux_session`-
    nek ezt a 20 perces stall-őrnél JÓVAL hamarabb kell észrevennie, ha kapott
    egy nem üres `fallback_process_pattern` argumentumot.
    """

    def _fake_tmux(self, bin_dir: Path) -> None:
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
            "  list-panes) printf '%s\\n' '/dev/pts/9' ;;\n"
            "  send-keys)\n"
            "    session=$3\n"
            "    # EGYETLEN sor, mintha a `codex exec` a kilépése előtti\n"
            "    # utolsó pane-tartalmat írta volna — utána soha többé.\n"
            "    printf '%s\\n' 'last output before codex exec exited' >> \"$(cat \"$state/log-$session\")\"\n"
            "    ;;\n"
            "  *) echo \"unexpected tmux call: $*\" >&2; exit 1 ;;\n"
            "esac\n"
        )
        fake_tmux.chmod(0o755)

    def _fake_ps(self, bin_dir: Path) -> None:
        # A `FAKE_PS_COMM` dönti el, mit "lát" a pane-en a `ps -t <tty> -o
        # comm=` hívás — a valódi mérés szerint ez pontosan a `ps` kimenete,
        # a `-t`/`-o` argumentumok tartalma a fake szempontjából lényegtelen.
        fake_ps = bin_dir / "ps"
        fake_ps.write_text(
            "#!/usr/bin/env bash\n"
            "printf '%s\\n' \"${FAKE_PS_COMM:-bash}\"\n"
        )
        fake_ps.chmod(0o755)

    def _fake_sleep(self, bin_dir: Path) -> None:
        # Lásd test_round_pipeline_stall_guard.py azonos trükkjét: a belső
        # `sleep`-eket fel kell gyorsítani, hogy a poll-loop gyorsan újra
        # ellenőrizhessen — a `date +%s`-re épülő időzítés emiatt nem torzul,
        # csak a loop kap gyakrabban esélyt megnézni.
        fake_sleep = bin_dir / "sleep"
        fake_sleep.write_text(
            "#!/usr/bin/env bash\n"
            "/bin/sleep 0.05\n"
        )
        fake_sleep.chmod(0o755)

    def _run(self, directory: Path, *, fake_ps_comm: str, extra_env: dict):
        bin_dir = directory / "bin"
        state_dir = directory / "state"
        bin_dir.mkdir()
        state_dir.mkdir()
        session_log = state_dir / "codex.log"
        signal_file = state_dir / "round-status"

        self._fake_tmux(bin_dir)
        self._fake_ps(bin_dir)
        self._fake_sleep(bin_dir)

        environment = dict(os.environ)
        environment.update(
            PATH=f"{bin_dir}:{environment['PATH']}",
            PIPELINE_STATE_DIR=str(state_dir),
            FAKE_TMUX_STATE=str(state_dir),
            FAKE_PS_COMM=fake_ps_comm,
            PIPELINE_CLAUDE_PROCESS_GRACE_SECONDS="0",
        )
        environment.update(extra_env)

        script = ROOT / "tools" / "round-pipeline.sh"
        source_functions = (
            "source <(sed -n '1,/^# --- Önjavítás/p' \"$PIPELINE_SCRIPT\")\n"
            "run_tmux_session fallback-probe irrelevant-command "
            f"{session_log} {signal_file} 8 fallback-probe 0 "
            "\"$CODEX_PROCESS_COMM_PATTERN\"\n"
            "echo \"RESULT_EXIT=$?\"\n"
        )
        environment["PIPELINE_SCRIPT"] = str(script)

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
        return completed, elapsed, signal_file

    def test_dead_engine_process_is_detected_before_the_stall_guard(self) -> None:
        with tempfile.TemporaryDirectory() as directory_name:
            completed, elapsed, signal_file = self._run(
                Path(directory_name),
                fake_ps_comm="bash",  # a codex process már nem fut a pane-en
                extra_env={"PIPELINE_ORCH_STALL_SECONDS": "6"},
            )

            # A lényeg: a JELZÉS-GYORSÍTÓNAK ezt jóval a 6s-es stall-őr ELŐTT
            # el kell kapnia — nagyvonalú biztonsági ráhagyással egy lassú
            # CI-futóhoz.
            self.assertLess(
                elapsed, 3,
                f"a motor-kilépés-őr nem lépett ki időben (elapsed={elapsed:.1f}s); "
                f"stdout={completed.stdout!r} stderr={completed.stderr!r}",
            )
            self.assertIn(
                "ELAKADÁS-GYORSÍTÓ", completed.stderr,
                f"a motor-kilépés-őr log-üzenete hiányzik; stdout={completed.stdout!r} "
                f"stderr={completed.stderr!r}",
            )
            # A lassú, log-mtime-alapú stall-őrnek ITT nem szabadna elsülnie —
            # a gyorsítónak kell megelőznie.
            self.assertNotIn("ELAKADÁS:", completed.stderr)
            self.assertFalse(signal_file.exists())
            self.assertIn("RESULT_EXIT=1", completed.stdout)

    def test_live_engine_process_is_not_killed_early(self) -> None:
        # Negatív kontroll (a false-positive ellen, E99-R13 H-NOSIGNAL
        # önjavítás): amíg a `ps -t <pane_tty>` a motor process-ét mutatja —
        # akkor is, ha az épp egy gyerek tool-hívásban blokkol, hiszen a
        # szülő process a `ps -t` listázásban VÁLTOZATLANUL szerepel, lásd a
        # javítás indoklását — a gyorsítónak NEM szabad megszakítania a
        # várakozást; a hívónak a rendes (itt: időkorlát) útvonalon kell
        # kilépnie.
        with tempfile.TemporaryDirectory() as directory_name:
            completed, elapsed, signal_file = self._run(
                Path(directory_name),
                fake_ps_comm="codex",  # a codex process él a pane-en
                extra_env={
                    "PIPELINE_ORCH_STALL_SECONDS": "3600",
                },
            )

            self.assertNotIn(
                "ELAKADÁS-GYORSÍTÓ", completed.stderr,
                f"a gyorsító tévesen élő motor-processzt jelzett holtnak; "
                f"stdout={completed.stdout!r} stderr={completed.stderr!r}",
            )
            self.assertIn("időkorlát lejárt", completed.stderr)
            self.assertFalse(signal_file.exists())
            self.assertIn("RESULT_EXIT=1", completed.stdout)


if __name__ == "__main__":
    unittest.main()
