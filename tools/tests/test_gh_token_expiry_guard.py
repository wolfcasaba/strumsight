"""A GitHub-PAT lejárata ELŐRE JELZETT, nem `H-AUTH` halt (ADR 0495 D4).

MÉRT eset (2026-08-28): a lejárt token 57 firingen (~4,75 óra) át állította
meg a láncot `H-AUTH`-tal, és a feloldás emberi volt (új PAT beírása a
`~/.git-credentials` + `gh auth` párosba). A hibaosztály DÁTUMOZOTT — a `gh`
a saját válaszfejlécében megmondja a lejáratot:

    Github-Authentication-Token-Expiration: 2026-09-27 08:13:31 UTC

A szerződés, amit ez a teszt rögzít:

1. a küszöb fölött (bőven a lejárat előtt) NINCS értesítés — nem zaj;
2. a küszöbön belül `high` értesítés megy;
3. két napon belül `urgent`;
4. a lejárat lekérdezése GYORSÍTÓTÁRAZOTT — a probe-ablakon belül nem kérdez
   újra (5 percenként futó driver, nem API-pazarlás);
5. ha a lejárat nem mérhető (üres válasz), a driver CSENDBEN megy tovább — az
   előrejelzés kényelem, nem kapu.
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-pipeline.sh"

# A driver token-őrének forrása: a `# --- 1c.` blokktól a `# --- 2.` blokkig.
PREFIX = "1,/^# --- Reviewer-függetlenség/p"
GUARD = "/^# --- 1c\\. A GitHub-PAT lejárata/,/^check_gh_token_expiry$/p"


class GhTokenExpiryGuardTest(unittest.TestCase):
    def run_guard(
        self,
        state: Path,
        *,
        expiry: str,
        now: int = 1_800_000_000,
        warn_days: str = "7",
        probe_calls_file: Path | None = None,
        repeat: int = 1,
    ) -> tuple[list[str], int]:
        """→ (elküldött értesítések, hányszor kérdezte le a lejáratot)."""
        notifications = state / "notifications"
        probes = probe_calls_file or (state / "probes")
        probe_command = f'printf "{expiry}\\n"; printf "x\\n" >> "{probes}"'
        shell = (
            f"source <(sed -n '{PREFIX}' \"$PIPELINE_SCRIPT\")\n"
            'notify() { printf "%s|%s|%s\\n" "$1" "$2" "${3:-default}" >> "$NOTIFICATIONS"; }\n'
            f"source <(sed -n '{GUARD}' \"$PIPELINE_SCRIPT\" | head -n -1)\n"
            + "check_gh_token_expiry\n" * repeat
        )
        environment = dict(os.environ)
        environment.update(
            PIPELINE_SCRIPT=str(SCRIPT),
            PIPELINE_STATE_DIR=str(state),
            PIPELINE_TEST_NOW=str(now),
            PIPELINE_GH_TOKEN_WARN_DAYS=warn_days,
            PIPELINE_GH_EXPIRY_CMD=probe_command,
            NOTIFICATIONS=str(notifications),
        )
        completed = subprocess.run(
            ["bash", "-c", shell],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        sent = notifications.read_text(encoding="utf-8").splitlines() if notifications.exists() else []
        probe_count = len(probes.read_text(encoding="utf-8").splitlines()) if probes.exists() else 0
        return sent, probe_count

    @staticmethod
    def _in_days(now: int, days: float) -> str:
        import datetime as dt

        moment = dt.datetime.fromtimestamp(now + days * 86400, tz=dt.timezone.utc)
        return moment.strftime("%Y-%m-%d %H:%M:%S UTC")

    def test_a_far_expiry_is_silent(self) -> None:
        now = 1_800_000_000
        with tempfile.TemporaryDirectory() as directory:
            sent, _ = self.run_guard(Path(directory), expiry=self._in_days(now, 25), now=now)
            self.assertEqual(sent, [])

    def test_inside_the_warning_window_it_alerts(self) -> None:
        now = 1_800_000_000
        with tempfile.TemporaryDirectory() as directory:
            sent, _ = self.run_guard(Path(directory), expiry=self._in_days(now, 5), now=now)
            self.assertEqual(len(sent), 1)
            self.assertIn("GitHub-token", sent[0])
            self.assertTrue(sent[0].endswith("|high"), sent[0])

    def test_two_days_before_expiry_it_is_urgent(self) -> None:
        now = 1_800_000_000
        with tempfile.TemporaryDirectory() as directory:
            sent, _ = self.run_guard(Path(directory), expiry=self._in_days(now, 1.5), now=now)
            self.assertEqual(len(sent), 1)
            self.assertTrue(sent[0].endswith("|urgent"), sent[0])

    def test_the_expiry_probe_is_cached_between_firings(self) -> None:
        now = 1_800_000_000
        with tempfile.TemporaryDirectory() as directory:
            _, probe_count = self.run_guard(
                Path(directory), expiry=self._in_days(now, 5), now=now, repeat=3
            )
            self.assertEqual(probe_count, 1, "a driver 5 percenként fut — nem kérdezhet minden firingen")

    def test_an_unmeasurable_expiry_is_not_a_gate(self) -> None:
        now = 1_800_000_000
        with tempfile.TemporaryDirectory() as directory:
            sent, _ = self.run_guard(Path(directory), expiry="", now=now)
            self.assertEqual(sent, [])


if __name__ == "__main__":
    unittest.main()
