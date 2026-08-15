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


if __name__ == "__main__":
    unittest.main()
