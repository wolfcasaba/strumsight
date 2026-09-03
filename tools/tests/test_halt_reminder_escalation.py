"""A halt-emlékeztető ESZKALÁL, nem hallgat el (ADR 0495 D3).

MÉRT eset (2026-08-30/31, `E15-R07 / H2`). Az önjavítás kimerült, a lánc
emberi döntésre várt — és a `.pipeline/chain.log` szerint **két teljes napon
át, 576 firingen keresztül nulla kör indult**. A telefonra menő emlékeztető
viszont a régi szerződés szerint a halt után `PIPELINE_HALT_REMINDER_MAX_H`
(24) órával VÉGLEG elhallgatott:

    [ "$now" -lt "$(( halted_epoch + max_seconds ))" ] || return 1

Vagyis pontosan akkor némult el, amikor a baj a legnagyobb lett. A mai
szerződés, amit ez a teszt rögzít:

1. a küszöb ALATT változatlanul `halt_reminder_min` percenként, `high`;
2. a küszöb FÖLÖTT nem szűnik meg, hanem ritkul (`backoff_h`) és `urgent`;
3. a ritkított ablakon BELÜL továbbra sem küld (nem spam).
"""

import datetime as dt
import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-pipeline.sh"

PREFIX = "1,/^# --- Reviewer-függetlenség/p"


class HaltReminderEscalationTest(unittest.TestCase):
    def probe(
        self,
        tmp: Path,
        *,
        halted_hours_ago: float,
        last_reminder_minutes_ago: float | None,
        now: int = 1_800_000_000,
        max_h: str = "24",
        backoff_h: str = "6",
    ) -> tuple[bool, str]:
        """→ (esedékes-e MOST, milyen prioritással)."""
        state = tmp
        halted_epoch = now - int(halted_hours_ago * 3600)
        halted_at = dt.datetime.fromtimestamp(halted_epoch, tz=dt.timezone.utc).isoformat()
        (state / "HALTED").write_text(
            "round=E15-R07\nhalt=H2\nsummary=fixture\n" f"halted_at={halted_at}\n",
            encoding="utf-8",
        )
        if last_reminder_minutes_ago is not None:
            stamp = now - int(last_reminder_minutes_ago * 60)
            (state / "halt-reminder-last").write_text(f"E15-R07|H2|{stamp}\n", encoding="utf-8")

        shell = (
            f"source <(sed -n '{PREFIX}' \"$PIPELINE_SCRIPT\")\n"
            'if halt_reminder_due E15-R07 H2; then printf "DUE|"; else printf "QUIET|"; fi\n'
            "halt_reminder_priority\n"
        )
        environment = dict(os.environ)
        environment.update(
            PIPELINE_SCRIPT=str(SCRIPT),
            PIPELINE_STATE_DIR=str(state),
            PIPELINE_TEST_NOW=str(now),
            PIPELINE_HALT_REMINDER_MIN="60",
            PIPELINE_HALT_REMINDER_MAX_H=max_h,
            PIPELINE_HALT_REMINDER_BACKOFF_H=backoff_h,
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
        verdict, priority = completed.stdout.strip().split("|")
        return verdict == "DUE", priority.strip()

    def test_below_the_threshold_the_old_hourly_high_contract_is_unchanged(self) -> None:
        with TemporaryState() as tmp:
            due, priority = self.probe(tmp, halted_hours_ago=3, last_reminder_minutes_ago=61)
            self.assertTrue(due)
            self.assertEqual(priority, "high")

    def test_below_the_threshold_it_does_not_spam(self) -> None:
        with TemporaryState() as tmp:
            due, _ = self.probe(tmp, halted_hours_ago=3, last_reminder_minutes_ago=30)
            self.assertFalse(due)

    def test_above_the_threshold_it_escalates_instead_of_going_silent(self) -> None:
        """A MÉRT defekt cellája: 30 órája áll, 7 órája nem szólt."""
        with TemporaryState() as tmp:
            due, priority = self.probe(tmp, halted_hours_ago=30, last_reminder_minutes_ago=7 * 60)
            self.assertTrue(due, "a 24 órás küszöb fölött az emlékeztető elhallgatott")
            self.assertEqual(priority, "urgent")

    def test_the_two_day_outage_would_have_kept_alerting(self) -> None:
        """A 2026-08-30/31-i, 48 órás kiesés: a 48. órában is szól."""
        with TemporaryState() as tmp:
            due, priority = self.probe(tmp, halted_hours_ago=48, last_reminder_minutes_ago=6 * 60)
            self.assertTrue(due)
            self.assertEqual(priority, "urgent")

    def test_above_the_threshold_the_backoff_window_is_respected(self) -> None:
        with TemporaryState() as tmp:
            due, _ = self.probe(tmp, halted_hours_ago=30, last_reminder_minutes_ago=90)
            self.assertFalse(due, "a ritkított ablakon belül nem szabad küldeni")


class TemporaryState:
    """Külön állapot-könyvtár körönként (a driver a fájlokból olvas)."""

    def __enter__(self) -> Path:
        import tempfile

        self._directory = tempfile.TemporaryDirectory()
        return Path(self._directory.name)

    def __exit__(self, *_exception: object) -> None:
        self._directory.cleanup()


if __name__ == "__main__":
    unittest.main()
