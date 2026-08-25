"""A Claude HETI keret kimerülése nem HALT, hanem időzített hold.

MÉRT eset (2026-08-24/25, E13-R16 + E09-R27). A Claude Code CLI a heti keret
kimerülésekor ezt írja a panelre:

    You've hit your weekly limit · resets 8am (UTC)    /upgrade to increase…

A driver `CLAUDE_LIMIT_PATTERN` mintája `(usage|session) limit` alakra
illeszkedett, a `weekly` szóra NEM. Következmény-lánc, mérve a
`.pipeline/chain.log`-ban és a session-naplókban:

  * az utolsó 60 pipeline-session közül **18** pontosan ezen a mondaton halt
    meg — mind H-NOSIGNAL-ként osztályozva;
  * az E13-R16 körön 22:50–02:40 között 4 session (2 orchestrátor + 2
    önjavító) indult és halt meg azonnal ugyanezen a falon, elköltve az
    önjavítási keretet;
  * 02:40-kor a lánc HALT-ra ment („az önjavító session jelzés nélkül ért
    véget"), és **11 óra 25 percig állt** kézi `tools/pipeline-status.sh
    --resume`-ra várva — a heti keret közben 08:00-kor már megnyílt;
  * a kör így 1121 percet vett el a 90 perces medián helyett.

A szerződés, amit ez a teszt rögzít — ugyanaz a három lépcső, amit a Terra
napi-budget (E03-R08 H6) és a Codex CLI usage-limit (E05-R15 H6) holdja már
használ:

1. a minta illeszkedjen a MÉRT heti-limit mondatra;
2. kvóta-nyomos session-napló → `claude-quota-hold` fájl a banner
   reset-idejével (nem vak felülbecslés);
3. az aktív hold csendben kihagyja a firinget — se session, se önjavítási
   kísérlet.
"""

import os
import re
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-pipeline.sh"

# A MÉRT banner, betűre a `.pipeline/session-E13-R16-20260824T225007.log`-ból.
REAL_WEEKLY_LIMIT_BANNER = (
    "  ⎿  You've hit your weekly limit · resets 8am (UTC)    "
    "/upgrade to increase your usage limit."
)


def _limit_pattern() -> str:
    for line in SCRIPT.read_text().splitlines():
        if line.startswith("CLAUDE_LIMIT_PATTERN="):
            return line.split("=", 1)[1].strip().strip("'")
    raise AssertionError("nincs CLAUDE_LIMIT_PATTERN a driverben")


class ClaudeWeeklyQuotaHoldTest(unittest.TestCase):
    def test_the_measured_weekly_banner_matches_the_quota_pattern(self) -> None:
        self.assertRegex(
            REAL_WEEKLY_LIMIT_BANNER,
            re.compile(_limit_pattern(), re.IGNORECASE),
            "a heti-limit banner nem illeszkedik a kvóta-mintára — a driver "
            "H-NOSIGNAL-nak minősíti a kvótahalált, elkölti az önjavítási "
            "keretet, majd megállítja a láncot kézi --resume-ig",
        )

    def _run(self, args: list[str], state: Path) -> subprocess.CompletedProcess:
        env = dict(os.environ)
        env["PIPELINE_STATE_DIR"] = str(state)
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_a_weekly_limit_log_writes_the_hold_with_the_banner_reset_time(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            session_log = state / "session-E13-R16.log"
            session_log.write_text(
                "✓ dolgozom a körön\n" + REAL_WEEKLY_LIMIT_BANNER + "\n"
            )

            result = self._run(
                ["--claude-quota-hold-if-detected", "E13-R16", str(session_log)],
                state,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            hold = state / "claude-quota-hold"
            self.assertTrue(
                hold.exists(),
                "a kvóta-nyomos session-napló nem írt holdot — a következő "
                "firing ugyanebbe a falba futna, önjavítási kísérletet költve",
            )
            content = hold.read_text()
            self.assertIn("round=E13-R16", content)
            hold_until = int(
                re.search(r"^hold_until=(\d+)$", content, re.M).group(1)
            )
            # A banner 8:00 UTC-t mond; a driver a KÖVETKEZŐ ilyen időpontra
            # kerekít, tehát a hold a jövőben van és 08:00:00 UTC-re esik.
            self.assertGreater(hold_until, int(time.time()))
            self.assertEqual(time.gmtime(hold_until).tm_hour, 8)
            self.assertEqual(time.gmtime(hold_until).tm_min, 0)

    def test_a_clean_log_writes_no_hold(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            session_log = state / "session-E13-R17.log"
            session_log.write_text("minden rendben, a kör fut\n")

            result = self._run(
                ["--claude-quota-hold-if-detected", "E13-R17", str(session_log)],
                state,
            )

            self.assertEqual(result.returncode, 1)
            self.assertFalse((state / "claude-quota-hold").exists())

    def test_an_active_hold_skips_the_firing_and_an_expired_one_does_not(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            hold = state / "claude-quota-hold"

            hold.write_text(f"round=E13-R16\nhold_until={int(time.time()) + 3600}\n")
            active = self._run(["--claude-quota-hold-active", "E13-R16"], state)
            self.assertEqual(
                active.returncode,
                0,
                "az aktív hold nem hagyta ki a firinget — a lánc újra sessiont "
                "indítana a zárt kereten",
            )
            self.assertTrue(hold.exists(), "az aktív holdot nem szabad törölni")

            # Másik körre szóló hold nem blokkol, és takarít.
            other = self._run(["--claude-quota-hold-active", "E13-R17"], state)
            self.assertEqual(other.returncode, 1)
            self.assertFalse(hold.exists())

            # Lejárt hold: a lánc mehet tovább.
            hold.write_text(f"round=E13-R16\nhold_until={int(time.time()) - 60}\n")
            expired = self._run(["--claude-quota-hold-active", "E13-R16"], state)
            self.assertEqual(
                expired.returncode,
                1,
                "a lejárt hold megállította a láncot — a keret-reset után a "
                "körnek automatikusan újra sorra kell kerülnie",
            )
            self.assertFalse(hold.exists())


if __name__ == "__main__":
    unittest.main()
