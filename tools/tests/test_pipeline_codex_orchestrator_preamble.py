"""The Codex/Terra orchestrator preamble must explain exec_command's yield
behavior and forbid restarting a yielded long-running command.

Measured 2026-08-15 (E07-R04, H-NOSIGNAL self-heal, orchestrator session
`01a006b4-bf64-7bd3-a25b-789fcc8d7e16`,
`~/.codex-terra/sessions/2026/08/15/rollout-2026-08-15T18-35-03-*.jsonl`):
the mandatory CI-wait call, `tools/wait-for-ci.sh 31902706136`, got a
`"Script running with cell ID 94"` / `"...96"` / `"...98"` response from the
`exec_command`/`write_stdin` tool THREE separate times, each around 11
seconds of wall time regardless of the requested `yield_time_ms` (30000,
then 60000) -- the yield is not bounded by that value the way the existing
preamble text ("Nincs 600 s-os Bash-plafonod ... futtathatod eloterben,
vegig") implies. The actually-awaited Full Gate run took 13 minutes
(19:00:39-19:13:30Z) and finished green, but the orchestrator re-invoked the
identical `exec_command` fresh each time instead of resuming the session it
was already given, so it never read a real result. After the third attempt
it ended its turn narrating "still running, I won't write a false signal"
without ever calling `tools/codex-signal.sh`-equivalent (the round-signal
file) -- three orphaned `wait-for-ci.sh` processes kept polling until the
whole `codex exec` process died with the turn, which is exactly the
H-NOSIGNAL halt this test's companion fix addresses.

A control repro in the same environment (plain `sleep 300` and a `gh api
rate_limit` poll loop, both run via the identical `codex exec -s
danger-full-access` invocation) proves there is no hard kill timeout: both
completed cleanly -- but only because the model correctly resumed the SAME
yielded session across several `write_stdin`/`wait` calls instead of
restarting. The preamble's job is to translate Claude-harness assumptions
for Codex/Terra (SS1); it must name this resume-not-restart rule instead of
implying a single foreground call always sees the command through.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREAMBLE = ROOT / "docs" / "execution" / "pipeline-codex-orchestrator-preamble.md"


class CodexOrchestratorPreambleYieldResumeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.text = PREAMBLE.read_text(encoding="utf-8")

    def test_the_preamble_names_the_yielded_cell_response(self) -> None:
        """Must name the literal tool response so the pattern is recognizable."""
        self.assertIn("cell ID", self.text)

    def test_the_preamble_forbids_restarting_a_yielded_command(self) -> None:
        self.assertIn("SOSE indítsd újra magát a parancsot", self.text)

    def test_the_preamble_cites_the_measured_e07_r04_incident(self) -> None:
        self.assertIn("E07-R04", self.text)
        self.assertIn("H-NOSIGNAL", self.text)

    def test_the_preamble_names_wait_for_ci_specifically(self) -> None:
        """wait-for-ci.sh is the concrete, recurring case this bites (CI runs
        routinely take 10+ minutes, far past a single yield window)."""
        self.assertIn("wait-for-ci.sh", self.text)


class CodexOrchestratorPreambleNoStatusOnlyTurnEndTest(unittest.TestCase):
    """Following the yield-resume rule above correctly is not sufficient on
    its own -- the preamble must also forbid ending a turn on bare status
    narration while a poll session is still open.

    Measured 2026-08-16 (E07-R09, H-NOSIGNAL self-heal, orchestrator session
    `01a00823-261b-7e70-94ad-b7c011007011`,
    `~/.codex-terra/sessions/2026/08/16/rollout-2026-08-16T01-15-16-*.jsonl`):
    the orchestrator correctly resumed the SAME `wait-for-ci.sh` session
    (`session_id 75633`) across 17 consecutive `write_stdin` polls over
    ~8.5 minutes -- exactly what the E07-R04 fix above requires, and not a
    bug. `wait-for-ci.sh`'s own `max_wait` (1800s) was nowhere near
    exhausted, and the actually-awaited Full Gate run (databaseId
    31920433829) did not reach a terminal state until 02:03:14Z
    (`conclusion=failure`) -- the wait was genuine, not a stall. The turn
    nonetheless ended at 01:58:45Z on a single text message ("... Full
    Gate ... still running; not merged yet") with no further tool call and
    no round-signal file, which the driver correctly recognised as
    H-NOSIGNAL (`ELAKADÁS-GYORSÍTÓ`, tools/round-pipeline.sh) rather than
    waiting out the full 20-minute stall guard. The existing preamble text
    told the model how to resume a yielded command but never said a bare
    non-terminal status update could not, by itself, end the turn.
    """

    def setUp(self) -> None:
        self.text = PREAMBLE.read_text(encoding="utf-8")

    def test_the_preamble_forbids_ending_a_turn_on_status_text_alone(self) -> None:
        self.assertIn("NEM érhet véget csak szöveggel", self.text)

    def test_the_preamble_cites_the_measured_e07_r09_incident(self) -> None:
        self.assertIn("E07-R09", self.text)
        self.assertIn("75633", self.text)

    def test_the_preamble_names_the_specific_still_running_status_message(self) -> None:
        """Must name the literal failure shape (a truthful-but-incomplete
        status message) so it's recognizable, not just an abstract rule."""
        self.assertIn("még tart; merge még nem történt", self.text)


class CodexOrchestratorPreambleNoStopAfterSuccessfulSubtaskTest(unittest.TestCase):
    """A successful, terminal sub-command result (e.g. the round-gate's own
    summary) is not the same as the round being done -- the preamble must
    forbid ending the turn on status text even when the last tool call
    itself genuinely succeeded.

    Measured 2026-08-19 (E07-R29, H-NOSIGNAL self-heal, orchestrator session
    `01a01ab2-9b80-7780-84f7-f21daf3759af`,
    `~/.codex-terra/sessions/2026/08/19/rollout-2026-08-19T15-45-07-*.jsonl`):
    the final independent re-verification's `tools/round-gate.sh` call, run
    in a fresh clone, finished at 16:56:47Z with a genuine, terminal,
    successful result (exit code 0, the gate's own "MINDEN GATE ZOLD"
    summary across all 14 steps). Unlike L282/L290, this was not a yield and
    not a non-terminal poll -- the command actually completed. The turn
    still ended six seconds later, at 16:56:53Z, on a single text summary
    ("... 14/14 zold, de a kotelezo CI-dispatch, exact-SHA ellenorzes es
    merge meg hatravan.") with no further tool call and no round-signal
    file -- the model correctly stated that mandatory work remained, and
    stopped anyway. The existing preamble rules cover restarting a yielded
    command (L282) and ending a turn on a non-terminal poll (L290), but
    neither says a successful SUB-task result cannot itself be mistaken for
    the round being finished.
    """

    def setUp(self) -> None:
        self.text = PREAMBLE.read_text(encoding="utf-8")

    def test_the_preamble_forbids_treating_a_successful_subtask_as_round_done(self) -> None:
        self.assertIn(
            "egy alparancs sikeres lezárása attól még nem azonos a kör lezárásával",
            self.text,
        )

    def test_the_preamble_cites_the_measured_e07_r29_incident(self) -> None:
        self.assertIn("E07-R29", self.text)
        self.assertIn("01a01ab2-9b80-7780-84f7-f21daf3759af", self.text)

    def test_the_preamble_names_the_specific_still_pending_status_message(self) -> None:
        """Must name the literal failure shape (a truthful status message
        following a genuinely successful gate run) so it's recognizable."""
        self.assertIn(
            "kötelező CI-dispatch, exact-SHA ellenőrzés és merge még hátravan",
            self.text,
        )


if __name__ == "__main__":
    unittest.main()
