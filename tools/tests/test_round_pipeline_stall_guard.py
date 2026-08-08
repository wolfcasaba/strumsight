import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class RoundPipelineStallGuardTest(unittest.TestCase):
    """A tmux-session ÉLETBEN maradhat úgy, hogy a panelje néma marad.

    Mért eset (E05-R17 H-NOSIGNAL, önjavítás 2026-08-08): az orchestrátor
    interaktív tmux-session "API Error: Server error mid-response" után
    visszaesett a promptra és többé nem írt semmit — a tmux-session és a
    Claude-process ÉLETBEN maradt (a driver akkori összes ellenőrzése ezt
    nézte: jelzésfájl / kvóta-minta / session-halál / pane-process-halál),
    ezért a driver az egész 4 órás abszolút időkorlátot kivárta, mielőtt
    H-NOSIGNAL-t jelzett — mérve: session-napló utolsó módosítása 22:56:45,
    a driver csak 00:21:18-kor (a timeout_s lejártakor) vette észre, azaz
    1h24m33s néma várakozás egyetlen új sor nélkül.

    Ez a teszt EGY tmux-session-t szimulál, ami `has-session`-re örökké
    élőt jelez, de a session-naplóba csak EGYSZER ír (az API-hiba előtti
    utolsó pane-tartalom), utána soha többé — pontosan az elakadt minta.
    A `run_tmux_session`-nek a session-napló mtime-ja alapján KELL
    észrevennie ezt, jóval a (nagyra állított) abszolút `timeout_s` előtt.
    """

    def test_silent_but_alive_session_is_detected_before_the_timeout(self) -> None:
        script = ROOT / "tools" / "round-pipeline.sh"
        with tempfile.TemporaryDirectory() as directory_name:
            directory = Path(directory_name)
            bin_dir = directory / "bin"
            state_dir = directory / "state"
            bin_dir.mkdir()
            state_dir.mkdir()
            session_log = state_dir / "claude.log"
            signal_file = state_dir / "round-status"

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
                "    # EGYETLEN sor, majd örök csend — a session (és a mögötte\n"
                "    # álló process) élve marad, csak nem ír többet a panelre.\n"
                "    printf '%s\\n' 'last output before the API error' >> \"$(cat \"$state/log-$session\")\"\n"
                "    ;;\n"
                "  *) echo \"unexpected tmux call: $*\" >&2; exit 1 ;;\n"
                "esac\n"
            )
            fake_tmux.chmod(0o755)

            # A `sleep`-et fel KELL gyorsítani, két okból: (1) a fő
            # poll-loop `sleep 30`-cal zár, valódi sleep mellett a
            # stall-őr csak 30s-enként kapna esélyt újra megnézni a
            # log-mtime-ot; (2) a pinger-alhéj `while sleep 1800; do`
            # ciklusa a `run_tmux_session` visszatérése UTÁN kapott
            # `kill`-t csak a folyamatban lévő `sleep` visszatértekor
            # dolgozza fel — valódi 1800s-es sleep esetén a `kill`
            # gyakorlatilag hatástalan (a gyerek túléli, és nyitva
            # tartja a capture_output pipe-ját), a teszt lefagy (mérve:
            # 120s+ a `sleep`-fake NÉLKÜL). A `stall_seconds=1` így is a
            # VALÓS (`date +%s`) eltelt időt méri — csak a loop gyorsabban
            # kap esélyt újra ellenőrizni, a szemantika nem változik.
            fake_sleep = bin_dir / "sleep"
            fake_sleep.write_text(
                "#!/usr/bin/env bash\n"
                "/bin/sleep 0.05\n"
            )
            fake_sleep.chmod(0o755)

            environment = dict(os.environ)
            environment.update(
                PATH=f"{bin_dir}:{environment['PATH']}",
                PIPELINE_STATE_DIR=str(state_dir),
                FAKE_TMUX_STATE=str(state_dir),
                PIPELINE_ORCH_STALL_SECONDS="1",
            )

            source_functions = (
                "source <(sed -n '1,/^# --- Önjavítás/p' \"$PIPELINE_SCRIPT\")\n"
                f"run_tmux_session stall-probe irrelevant-command "
                f"{session_log} {signal_file} 30 stall-probe 0\n"
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

            # A lényeg: a driver ne várja ki a 30s-es timeout_s-t egy néma,
            # de élő session-re — a stall-őrnek ennél jóval hamarabb kell
            # kilépnie (nagy biztonsági ráhagyással, hogy egy lassú CI-futó
            # se legyen flaky).
            self.assertLess(
                elapsed, 15,
                f"a stall-őr nem lépett ki időben (elapsed={elapsed:.1f}s); "
                f"stdout={completed.stdout!r} stderr={completed.stderr!r}",
            )
            self.assertIn(
                "ELAKADÁS", completed.stderr,
                f"a stall-őr log-üzenete hiányzik; stdout={completed.stdout!r} "
                f"stderr={completed.stderr!r}",
            )
            # `run_tmux_session` jelzésfájl nélkül fejeződik be — a hívó
            # (`run_orchestrator_session` / a driver H-NOSIGNAL ága) ezt
            # ugyanúgy "nincs jelzés"-ként kezeli, mint eddig; a stall-őr
            # csak a FELISMERÉS idejét rövidíti le, a szemantikát nem
            # változtatja meg.
            self.assertFalse(signal_file.exists())
            self.assertIn("RESULT_EXIT=1", completed.stdout)


if __name__ == "__main__":
    unittest.main()
