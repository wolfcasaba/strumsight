"""Az elakadás-őr NE öljön meg egy némán megszakított, de ÉLŐ sessiont az
első néma ablakban — előbb ébressze.

MÉRT eset (E13-R14 H-NOSIGNAL, önjavítás 2026-08-24). Az orchestrátor-session
(`~/.claude/projects/-home-ubuntu-music-theory/4615efa7-….jsonl`) 15:48:46-kor
előtérbe tette a `tools/wait-for-round.sh /home/ubuntu/ss-sonnet-impl-e13-r14
540` hívást. 15:51:11-kor KÍVÜLRŐL érkezett rá egy megszakítás — a naplóban
egymás után a `tool_result` `is_error=true` „The user doesn't want to proceed
with this tool use…" és a `[Request interrupted by user for tool use]` sor —,
követő prompt NÉLKÜL. Ettől kezdve a session üres prompton állt: a tmux-session
élt, a Claude-process élt, a panel viszont többé nem írt (a session-napló
mtime-ja 15:51-en megállt).

A driver akkori összes ellenőrzése ezt kihagyta (jelzésfájl / kvóta-minta /
session-halál / pane-process-halál mind „rendben"-t adott), így 16:11:39-kor a
20 perces elakadás-őr ölte meg a sessiont és jelzett H-NOSIGNAL-t. Közben az
implementer 16:03:33-kor `status=done`-nal BEFEJEZTE a kört
(`/home/ubuntu/ss-sonnet-impl-e13-r14/.codex-round-status`) — a lánc egy KÉSZ
kört ejtett el, mert senki nem szólt az üres prompton álló sessionhöz.

Egy üres prompton álló interaktív session önmagától sosem indul újra: csak
kívülről éleszthető. Ez a teszt ezt a két, egymást kiegészítő szerződést rögzíti:

1. néma panel + ÉLŐ interaktív Claude-process → előbb ÉBRESZTÉS megy be, és ha
   a session válaszol (jelzésfájl), a kör SIKERESEN zárul — nincs H-NOSIGNAL;
2. az őr ettől nem gyengül: kimerített ébresztés-keret után a `break`/kill
   ugyanúgy lecsap, a jelzésfájl nélküli futás továbbra is bukik.
"""

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

# Szándékosan irreális tty-szám: a `ps -t <n>` így sosem talál el véletlenül
# egy, a boxon ténylegesen futó folyamatot (flaky-védelem).
FAKE_PANE_TTY = "/dev/pts/65530"


class RoundPipelineStallNudgeTest(unittest.TestCase):
    def _run(self, directory: Path, *, revive: bool, nudges: str = "1"):
        """Egy `run_tmux_session` futás néma, de élő Claude-panellel.

        `revive=True` esetén a beküldött ébresztésre a fake tmux úgy reagál,
        ahogy egy valóban felébredő session: ír a panelre és leteszi a
        kör-jelzésfájlt. `revive=False` a menthetetlen esetet játssza: az
        ébresztés bemegy, de a panel néma marad.
        """
        bin_dir = directory / "bin"
        state_dir = directory / "state"
        bin_dir.mkdir()
        state_dir.mkdir()
        session_log = state_dir / "claude.log"
        signal_file = state_dir / "round-status"
        sent_keys = state_dir / "sent-keys"

        revive_flag = "1" if revive else "0"
        fake_tmux = bin_dir / "tmux"
        fake_tmux.write_text(
            "#!/usr/bin/env bash\n"
            "set -eu\n"
            "state=${FAKE_TMUX_STATE:?}\n"
            'case "$1" in\n'
            '  kill-session) rm -f "$state/session-${3}" ;;\n'
            '  new-session) touch "$state/session-${4}" ;;\n'
            '  has-session) test -f "$state/session-${3}" ;;\n'
            "  pipe-pane) printf '%s' \"${5#cat >> }\" > \"$state/log-${3}\" ;;\n"
            # A pane-en ÉL egy interaktív Claude — pontosan az E13-R14 állapot.
            f"  list-panes) printf '%s\\n' '{FAKE_PANE_TTY}' ;;\n"
            "  send-keys)\n"
            "    session=$3\n"
            # A driver ADR 0498 D1 óta `--`-sal zárja le a kapcsolókat, hogy a
            # kötőjellel kezdődő prompt se váljon tmux-opcióvá — a hasznos teher
            # ilyenkor az $5. A stub ezt a valódi tmux szemantikája szerint oldja
            # fel, nem rögzített argumentum-pozícióval.
            "    payload=$4\n"
            '    if [ "$payload" = "--" ]; then payload=${5:-}; fi\n'
            '    printf \'%s\\n\' "$payload" >> "$state/sent-keys"\n'
            # Az INDÍTÓ parancs egyetlen sort ír a panelre, aztán a session
            # elnémul (a kívülről megszakított, üres prompton álló állapot).
            '    case "$payload" in\n'
            "      FOLYTASD*)\n"
            f"        if [ '{revive_flag}' = '1' ]; then\n"
            "          printf '%s\\n' 'resumed after the nudge' >> \"$(cat \"$state/log-$session\")\"\n"
            '          printf \'status=done\\n\' > "${FAKE_SIGNAL_FILE:?}"\n'
            "        fi\n"
            "        ;;\n"
            '      *) printf \'%s\\n\' \'last output before the interrupt\' >> "$(cat "$state/log-$session")" ;;\n'
            "    esac\n"
            "    ;;\n"
            '  *) echo "unexpected tmux call: $*" >&2; exit 1 ;;\n'
            "esac\n"
        )
        fake_tmux.chmod(0o755)

        # A pane-process mérése a driver saját `ps -t <tty> -o comm=` hívása.
        # A fake csak a fenti fake pane-tty-re felel `claude`-dal.
        fake_ps = bin_dir / "ps"
        fake_ps.write_text(
            "#!/usr/bin/env bash\n"
            f"if [ \"${{2:-}}\" = \"{FAKE_PANE_TTY.rsplit('/', 1)[-1]}\" ]; then\n"
            "  printf '%s\\n' claude\n"
            "fi\n"
        )
        fake_ps.chmod(0o755)

        # Ugyanaz a `sleep`-gyorsítás, mint a stall-guard tesztben: a
        # poll-loop `sleep 30`-ja és a pinger-alhéj `sleep 1800`-ja nélküle
        # használhatatlanul lassúvá tenné a futást. Az eltelt időt a driver
        # végig VALÓS `date +%s`-sel méri, a szemantika nem változik.
        fake_sleep = bin_dir / "sleep"
        fake_sleep.write_text("#!/usr/bin/env bash\n/bin/sleep 0.05\n")
        fake_sleep.chmod(0o755)

        environment = dict(os.environ)
        environment.update(
            PATH=f"{bin_dir}:{environment['PATH']}",
            PIPELINE_STATE_DIR=str(state_dir),
            FAKE_TMUX_STATE=str(state_dir),
            FAKE_SIGNAL_FILE=str(signal_file),
            PIPELINE_ORCH_STALL_SECONDS="1",
            PIPELINE_ORCH_STALL_NUDGES=nudges,
            PIPELINE_SCRIPT=str(ROOT / "tools" / "round-pipeline.sh"),
        )

        script = (
            "source <(sed -n '1,/^# --- Önjavítás/p' \"$PIPELINE_SCRIPT\")\n"
            f"run_tmux_session nudge-probe irrelevant-command "
            f"{session_log} {signal_file} 30 nudge-probe 0\n"
            'echo "RESULT_EXIT=$?"\n'
        )

        started = time.monotonic()
        completed = subprocess.run(
            ["bash", "-c", script],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        return completed, time.monotonic() - started, signal_file, sent_keys

    def test_silent_but_alive_session_is_woken_instead_of_killed(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            completed, elapsed, signal_file, sent_keys = self._run(
                Path(name), revive=True
            )
            context = (
                f"elapsed={elapsed:.1f}s stdout={completed.stdout!r} "
                f"stderr={completed.stderr!r}"
            )

            self.assertIn("ELAKADÁS-ÉBRESZTŐ", completed.stderr, context)
            self.assertTrue(sent_keys.exists(), context)
            self.assertIn(
                "FOLYTASD", sent_keys.read_text(),
                f"nem ment be folytatás-prompt a néma, de élő panelbe; {context}",
            )
            # A lényeg: a megszakított session ÚJRA dolgozott, a kör jelzett —
            # ez az a H-NOSIGNAL, amit az E13-R14-ben elvesztettünk.
            self.assertTrue(signal_file.exists(), context)
            self.assertIn("RESULT_EXIT=0", completed.stdout, context)
            self.assertNotIn(
                "ELAKADÁS: a(z)", completed.stderr,
                f"a driver az ELSŐ néma ablakban megölte az élő sessiont; {context}",
            )

    def test_the_guard_still_kills_after_the_nudge_budget_is_spent(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            completed, elapsed, signal_file, sent_keys = self._run(
                Path(name), revive=False
            )
            context = (
                f"elapsed={elapsed:.1f}s stdout={completed.stdout!r} "
                f"stderr={completed.stderr!r}"
            )

            self.assertIn("ELAKADÁS-ÉBRESZTŐ", completed.stderr, context)
            self.assertIn("FOLYTASD", sent_keys.read_text(), context)
            # Az őr nem gyengült: a keret kimerülése után ugyanúgy öl, és
            # jelzésfájl híján a futás továbbra is bukik — jóval a 30s-es
            # abszolút `timeout_s` előtt.
            self.assertIn("ELAKADÁS: a(z)", completed.stderr, context)
            self.assertFalse(signal_file.exists(), context)
            self.assertIn("RESULT_EXIT=1", completed.stdout, context)
            self.assertEqual(
                1, sent_keys.read_text().count("FOLYTASD"),
                f"az ébresztés-keret nem korlátos; {context}",
            )
            self.assertLess(elapsed, 15, context)

    def test_zero_budget_keeps_the_pre_heal_behaviour(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            completed, elapsed, signal_file, sent_keys = self._run(
                Path(name), revive=True, nudges="0"
            )
            context = (
                f"elapsed={elapsed:.1f}s stdout={completed.stdout!r} "
                f"stderr={completed.stderr!r}"
            )

            self.assertNotIn("ELAKADÁS-ÉBRESZTŐ", completed.stderr, context)
            self.assertNotIn("FOLYTASD", sent_keys.read_text(), context)
            self.assertIn("ELAKADÁS: a(z)", completed.stderr, context)
            self.assertFalse(signal_file.exists(), context)
            self.assertIn("RESULT_EXIT=1", completed.stdout, context)


if __name__ == "__main__":
    unittest.main()
