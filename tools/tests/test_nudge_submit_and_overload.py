"""Az ébresztő KÜLÖN Enterrel küld be, és a 529 saját, rövid ablakot kap (ADR 0498).

MÉRT eset (2026-09-03 13:31–13:50). Mindkét futó kör sessionje ugyanabban a
percben esett el `API Error: 529 Overloaded`-del, ÜRES prompton maradt, és az
`E15-R12` 1 óra 22 percnyi turn-munkát vesztett. A driver ébresztője pedig ezt
az alakot használta:

    tmux send-keys -t "$tmux_session" "$STALL_NUDGE_TEXT" Enter

`tmux capture-pane`-nel mérve a szöveg BENN MARADT a beviteli dobozban (négy
sorra tördelve) — a `claude` TUI a gyorsan érkező, hosszú szöveget
beillesztésnek kezeli, és a közvetlenül utána érkező Enter ÚJ SORT ír. Egy
külön, később küldött Enter azonnal beküldte.
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-pipeline.sh"
PREFIX = "1,/^# --- Reviewer-függetlenség/p"

# A MÉRT naplósor, betűre a session-E15-R12-20260903T121009.log-ból.
MEASURED_529_LINE = (
    "●API Error: 529 Overloaded. This is a server-side issue, usually "
    "temporary — try again in a moment. If it persists, check https://status.claude.com."
)


class NudgeSubmitTest(unittest.TestCase):
    def test_the_text_and_the_enter_are_two_separate_send_key_calls(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            calls = state / "tmux-calls"
            shell = (
                f"source <(sed -n '{PREFIX}' \"$PIPELINE_SCRIPT\")\n"
                'tmux() { printf "%s\\n" "$*" >> "$CALLS"; }\n'
                "NUDGE_SUBMIT_DELAY=0\n"
                'send_nudge_to_pane pipeline-E15-R12 "FOLYTASD (elakadas-ebreszto): teszt"\n'
            )
            environment = dict(os.environ)
            environment.update(
                PIPELINE_SCRIPT=str(SCRIPT),
                PIPELINE_STATE_DIR=str(state),
                CALLS=str(calls),
            )
            completed = subprocess.run(
                ["bash", "-c", shell], cwd=ROOT, env=environment, text=True, capture_output=True
            )
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            lines = calls.read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 2, f"nem KÉT hívás: {lines}")
            self.assertIn("FOLYTASD", lines[0])
            self.assertNotIn("Enter", lines[0], "a régi, MÉRTEN nem beküldő alak")
            self.assertTrue(lines[1].endswith("Enter"), lines[1])
            self.assertNotIn("FOLYTASD", lines[1])

    def test_the_text_is_passed_after_a_double_dash(self) -> None:
        """Kötőjellel kezdődő prompt se váljon tmux-kapcsolóvá."""
        source = SCRIPT.read_text(encoding="utf-8")
        block = source.split("send_nudge_to_pane() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('send-keys -t "$pane" -- "$text"', block)


class ApiOverloadWindowTest(unittest.TestCase):
    def _match(self, text: str) -> bool:
        shell = (
            f"source <(sed -n '{PREFIX}' \"$PIPELINE_SCRIPT\")\n"
            'printf "%s" "$SAMPLE" | grep -qaE "$API_OVERLOAD_PATTERN"\n'
        )
        environment = dict(os.environ)
        environment.update(PIPELINE_SCRIPT=str(SCRIPT), SAMPLE=text)
        return (
            subprocess.run(["bash", "-c", shell], cwd=ROOT, env=environment, capture_output=True).returncode
            == 0
        )

    def test_the_measured_529_line_matches(self) -> None:
        self.assertTrue(self._match(MEASURED_529_LINE))

    def test_ordinary_output_does_not_match(self) -> None:
        self.assertFalse(self._match("Cooked for 1h 22m 21s — running the round gate"))
        self.assertFalse(self._match("529 files scanned"))

    def test_the_overload_window_is_shorter_and_its_budget_larger(self) -> None:
        shell = (
            f"source <(sed -n '{PREFIX}' \"$PIPELINE_SCRIPT\")\n"
            'printf "%s %s %s\\n" "${PIPELINE_ORCH_OVERLOAD_SECONDS:-120}" '
            '"${PIPELINE_ORCH_OVERLOAD_NUDGES:-4}" "${PIPELINE_ORCH_STALL_NUDGES:-1}"\n'
        )
        completed = subprocess.run(
            ["bash", "-c", shell],
            cwd=ROOT,
            env={**os.environ, "PIPELINE_SCRIPT": str(SCRIPT)},
            text=True,
            capture_output=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        overload_seconds, overload_budget, stall_budget = completed.stdout.split()
        self.assertLess(int(overload_seconds), 20 * 60)
        self.assertGreater(int(overload_budget), int(stall_budget))

    def test_the_driver_actually_selects_the_shorter_window(self) -> None:
        """Forrás-szintű őr: a küszöböt a napló VÉGE választja meg."""
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("active_stall_seconds=$overload_seconds", source)
        self.assertIn("active_nudge_budget=$overload_budget", source)
        self.assertIn('[ "$log_age" -ge "$active_stall_seconds" ]', source)
        self.assertIn('[ "$nudges_sent" -lt "$active_nudge_budget" ]', source)


if __name__ == "__main__":
    unittest.main()


class FeedbackPromptTest(unittest.TestCase):
    """ADR 0498 D3 — a promptot blokkoló visszajelzés-kérdés elbocsátása.

    MÉRVE 2026-09-03 14:04 (`E15-R12`): a 529 után a CLI a beviteli doboz FÖLÉ
    egy kérdést tett ki (`How is Claude doing this session? … 0: Dismiss`), ami
    elnyelte a beküldést — az ébresztő bement, a kör mégis tétlen maradt.
    """

    MEASURED_PANE = (
        "● API Error: 529 Overloaded. This is a server-side issue, usually\n"
        "  temporary — try again in a moment.\n"
        "✻ Cooked for 3m 41s\n"
        "● How is Claude doing this session? (optional)\n"
        "  1: Bad    2: Fine   3: Good   0: Dismiss\n"
        "❯ \n"
    )

    def _run(self, pane_text: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            calls = state / "tmux-calls"
            pane_file = state / "pane"
            pane_file.write_text(pane_text, encoding="utf-8")
            shell = (
                f"source <(sed -n '{PREFIX}' \"$PIPELINE_SCRIPT\")\n"
                'tmux() { if [ "$1" = "capture-pane" ]; then cat "$PANE"; '
                'else printf "%s\\n" "$*" >> "$CALLS"; fi; }\n'
                "NUDGE_SUBMIT_DELAY=0\n"
                "dismiss_feedback_prompt_if_present pipeline-E15-R12\n"
            )
            environment = dict(os.environ)
            environment.update(
                PIPELINE_SCRIPT=str(SCRIPT),
                PIPELINE_STATE_DIR=str(state),
                CALLS=str(calls),
                PANE=str(pane_file),
            )
            completed = subprocess.run(
                ["bash", "-c", shell], cwd=ROOT, env=environment, text=True, capture_output=True
            )
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            return calls.read_text(encoding="utf-8").splitlines() if calls.exists() else []

    def test_the_measured_survey_is_dismissed_with_a_zero(self) -> None:
        calls = self._run(self.MEASURED_PANE)
        self.assertEqual(len(calls), 2, f"nem KÉT hívás (szöveg + Enter): {calls}")
        self.assertTrue(calls[0].rstrip().endswith("0"), calls[0])
        self.assertTrue(calls[1].endswith("Enter"), calls[1])

    def test_without_the_survey_it_is_silent(self) -> None:
        self.assertEqual(self._run("● API Error: 529 Overloaded.\n❯ \n"), [])

    def test_the_dismissal_runs_before_the_continuation_prompt(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        dismissal = source.index('dismiss_feedback_prompt_if_present "$tmux_session"')
        nudge = source.index('send_nudge_to_pane "$tmux_session" "$STALL_NUDGE_TEXT"')
        self.assertLess(dismissal, nudge)
