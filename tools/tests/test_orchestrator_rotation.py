"""Orchestrátor-rotáció és session-keret fogyásmérő (ADR 0222).

MÉRT ok (2026-08-11, E06-R05). A lánc MINDEN körben a Claude-ot ültette az
orchestrátor+reviewer székbe, körönként ~85 perc `--effort max` munkával,
`azonnali lánc-folytatás`-sal szünet nélkül. Egy 5 órás ablakba ~3,5 kör fér,
tehát a keret kimerülése nem baleset volt, hanem a kiosztás következménye.

A védőháló ráadásul VAK volt: a `CLAUDE_LIMIT_PATTERN` egyetlen mintája sem
illeszkedett a CLI tényleges bannerére

    „You've used 97% of your session limit · resets 3:40pm (UTC) · /upgrade to k…"

amiből a `session-E06-R05-20260811T134634.log`-ban 11 darab van, 90→97%-ig
számolva. Ezért nem lépett a Terra-átadás; a sessiont a 20 perces elakadás-őr
lőtte le a CI-dispatch+merge közben, a kör H-NOSIGNAL-t kapott, és két önjavító
kör kellett a feloldásához (docs/LESSONS.md L213).

Ez a fájl a driver gépi döntéseit méri a kiexportált horgokon keresztül —
hálózat, tmux és élő modellhívás nélkül.
"""

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "tools" / "round-pipeline.sh"

# A banner MÁSOLATA az éles naplóból, ANSI-vezérlőkkel együtt: a mérésnek
# pontosan azt a bemenetet kell kapnia, amin a régi minta elhasalt.
REAL_BANNER = (
    "\x1b[K\x1b[2C\x1b[1B\x1b[38;5;220mYou've used 97% of your session limit "
    "· resets 3:40pm (UTC) · /upgrade to k…\x1b[39m\n"
)


def driver(*args: str, state: Path, **env: str) -> subprocess.CompletedProcess:
    environment = dict(os.environ, PIPELINE_STATE_DIR=str(state), **env)
    return subprocess.run(
        ["bash", str(DRIVER), *args],
        capture_output=True,
        text=True,
        env=environment,
        timeout=60,
    )


class SessionGaugeTest(unittest.TestCase):
    """A fogyásmérő az ÉLES banner-alakon."""

    def test_the_percent_is_read_from_an_ansi_laden_pane_log(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            log = state / "session.log"
            log.write_text(REAL_BANNER, encoding="utf-8")
            result = driver("--claude-session-pct", str(log), state=state)
            self.assertEqual(result.stdout.strip(), "97", result.stderr)

    def test_the_last_measurement_wins(self) -> None:
        """A banner számol felfelé; a döntés az UTOLSÓ állásra épül."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            log = state / "session.log"
            log.write_text(
                REAL_BANNER.replace("97%", "90%") + REAL_BANNER.replace("97%", "96%"),
                encoding="utf-8",
            )
            self.assertEqual(
                driver("--claude-session-pct", str(log), state=state).stdout.strip(),
                "96",
            )

    def test_a_log_without_a_banner_reports_nothing(self) -> None:
        """Hiányzó mérés nem lehet zárlat — az bénítaná a láncot."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            log = state / "session.log"
            log.write_text("teljesen hétköznapi session-napló\n", encoding="utf-8")
            result = driver("--claude-session-pct", str(log), state=state)
            self.assertEqual(result.stdout.strip(), "")
            self.assertNotEqual(result.returncode, 0)

    def test_the_reset_time_is_parsed_into_the_future(self) -> None:
        """A zárlat a banner reset-idejéhez igazodik, nem vak 5 órás becslés."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            log = state / "session.log"
            log.write_text(REAL_BANNER, encoding="utf-8")
            result = driver("--claude-session-reset-epoch", str(log), state=state)
            epoch = int(result.stdout.strip())
            self.assertGreater(epoch, int(time.time()))
            self.assertLess(epoch, int(time.time()) + 25 * 3600)


class RotationTest(unittest.TestCase):
    """A körök felét a Terra vezényli (user-döntés 2026-08-11)."""

    def test_the_orchestrator_alternates_between_the_two_engines(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            last = state / "orchestrator-last"
            self.assertEqual(driver("--next-orchestrator", state=state).stdout.strip(), "claude")
            last.write_text("claude\n", encoding="utf-8")
            self.assertEqual(driver("--next-orchestrator", state=state).stdout.strip(), "terra")
            last.write_text("terra\n", encoding="utf-8")
            self.assertEqual(driver("--next-orchestrator", state=state).stdout.strip(), "claude")

    def test_the_rotation_can_be_pinned_to_one_engine(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            for pinned in ("claude", "terra"):
                with self.subTest(engine=pinned):
                    result = driver(
                        "--next-orchestrator", state=state, PIPELINE_ORCH_ROTATION=pinned
                    )
                    self.assertEqual(result.stdout.strip(), pinned)

    def test_without_a_fallback_engine_everything_stays_on_claude(self) -> None:
        """`PIPELINE_FALLBACK_ENGINE=none` mellett nincs kinek rotálni."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            result = driver(
                "--next-orchestrator",
                state=state,
                PIPELINE_ORCH_ROTATION="terra",
                PIPELINE_FALLBACK_ENGINE="none",
            )
            self.assertEqual(result.stdout.strip(), "claude")


class PreemptionTest(unittest.TestCase):
    """Egy ~85 perces kört nem indítunk a keret maradék néhány százalékán."""

    @staticmethod
    def write_usage(state: Path, pct: int, reset_in: int) -> None:
        (state / "claude-usage").write_text(
            "pct={}\nreset={}\nmeasured={}\nlog=fixture\n".format(
                pct, int(time.time()) + reset_in, int(time.time())
            ),
            encoding="utf-8",
        )

    def test_a_nearly_spent_budget_hands_the_round_to_terra(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            self.write_usage(state, pct=97, reset_in=3600)
            result = driver(
                "--next-orchestrator", state=state, PIPELINE_ORCH_ROTATION="claude"
            )
            self.assertEqual(result.stdout.strip(), "terra", "a zárlat felülírja a rotációt")

    def test_a_healthy_budget_keeps_claude_in_the_chair(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            self.write_usage(state, pct=40, reset_in=3600)
            result = driver(
                "--next-orchestrator", state=state, PIPELINE_ORCH_ROTATION="claude"
            )
            self.assertEqual(result.stdout.strip(), "claude")

    def test_an_expired_block_releases_claude_again(self) -> None:
        """A reset elmúltával a Claude azonnal újra sorra kerül."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            self.write_usage(state, pct=99, reset_in=-60)
            result = driver(
                "--next-orchestrator", state=state, PIPELINE_ORCH_ROTATION="claude"
            )
            self.assertEqual(result.stdout.strip(), "claude")


class IndependenceTest(unittest.TestCase):
    """ADR 0138: a Terra nem review-zheti a saját diffjét — rotáció alatt sem."""

    def test_a_terra_led_round_swaps_the_implementer_to_claude(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            result = driver("--independent-engine", "terra", "terra", state=state)
            self.assertEqual(result.stdout.strip(), "sonnet-impl")

    def test_a_claude_led_round_leaves_the_implementer_alone(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            result = driver("--independent-engine", "terra", "claude", state=state)
            self.assertEqual(result.stdout.strip(), "terra")

    def test_the_legacy_codex_engine_name_is_covered_too(self) -> None:
        """MÉRT rés: a régi feltétel csak a `codex` nevet nézte, az ADR 0140
        óta élő `engine-override=terra` mellett tehát ki sem lépett — pedig
        `codex` és `terra` UGYANAZ a gpt-5.6-terra modell."""
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            for engine in ("codex", "terra"):
                with self.subTest(engine=engine):
                    result = driver("--independent-engine", engine, "terra", state=state)
                    self.assertEqual(result.stdout.strip(), "sonnet-impl")

    def test_a_blocked_claude_budget_rules_out_the_claude_implementer(self) -> None:
        """Kimerült kereten a szerepcsere nem megoldás: a csere-motor sem
        ehet ugyanabból a keretből, ezért külső kulcsos motorra megyünk.

        MÉRT hiba (2026-08-11, E06-R07 H5): a driver a `minimax` választ a
        `MINIMAX_API_KEY` env VAGY a `~/.mmx/config.json` jelenlétéből dönti
        el (round-pipeline.sh `resolve_independent_engine`) — ez a helyes,
        éles viselkedés, ÉLES gépi állapotot mér. A teszt viszont, a
        testvéreitől eltérően (`PIPELINE_ORCH_ROTATION`,
        `PIPELINE_FALLBACK_ENGINE` explicit env-ként megy a `driver()`-be),
        NEM injektálta ezt az állapotot, hanem az AMBIENS host-ra hagyatkozott.
        A dev boxon van `~/.mmx/config.json`, ezért ott zölden futott; a
        Router CI friss `ubuntu-latest` futóján viszont sem a fájl, sem az
        env nincs jelen, így a driver — HELYESEN — `HALT_INDEP`-et adott, a
        teszt pedig determinisztikusan pirosra váltott MINDEN PR-en, ami
        érintett egy router-ci trigger-utat (`docs/rounds/**` is az — tehát
        gyakorlatilag minden SDD-kör). Lásd docs/LESSONS.md L219.
        """
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            (state / "claude-blocked-until").write_text(
                str(int(time.time()) + 3600), encoding="utf-8"
            )
            result = driver(
                "--independent-engine",
                "terra",
                "terra",
                state=state,
                # Bizonyítottan fake fixture (L219), nem valódi hitelesítő — a
                # "fixture" szó nincs a secrets-scan placeholder-listáján, ezért
                # H7-ben (2026-08-11) jelölés nélkül lelet lett; docs/LESSONS.md L220.
                MINIMAX_API_KEY="heal-e06-r07-h5-fixture-key",  # strumsight:allow-secret L220 fake fixture
            )
            self.assertEqual(result.stdout.strip(), "minimax")


class PreambleClaudeCliProhibitionTest(unittest.TestCase):
    """MÉRT halt (2026-08-12, E06-R11 H6): a Terra-vezényelt orchestrátor-
    session a `pipeline-codex-orchestrator-preamble.md` feltétel nélküli „ne
    hívd a claude CLI-t” szabályát a fenti `IndependenceTest` által is
    igazolt, ROTÁCIÓ-eredetű `sonnet-impl` implementer-dispatch-ra is
    ráhúzta, és inkább önmagát haltolta (H6), ahelyett hogy a §1.1 szerint a
    `tools/mm-round.sh`-sal elindította volna a MÁR kvóta-ellenőrzött
    implementert. A preambulum (ADR 0115, 2026-08-02) egyetlen kiváltó okot
    ismert — a Claude-kvóta kimerülését —, és nem lett frissítve, amikor az
    ADR 0222 (2026-08-11) egy MÁSODIK, kvótától független kiváltó okot
    (rotáció) vezetett be, amely alatt a Claude-kvóta tipikusan egészséges —
    épp ekkor adja a driver implementernek a claude-harness `sonnet-impl`-et.
    """

    def setUp(self) -> None:
        self.preamble = (
            ROOT / "docs" / "execution" / "pipeline-codex-orchestrator-preamble.md"
        ).read_text(encoding="utf-8")

    def test_the_claude_cli_ban_is_no_longer_the_unconditional_2026_08_02_wording(self) -> None:
        """Ez a pontos mondat okozta a H6-ot — ha visszatér, a hiba visszatér."""
        self.assertNotIn(
            "A `claude` CLI-t NE hívd** — épp az a kvóta merült ki, ami miatt itt vagy.",
            self.preamble,
        )

    def test_the_registered_claude_harness_implementer_dispatch_is_explicitly_carved_out(
        self,
    ) -> None:
        """A javításnak névvel ki kell mondania, hogy a §1.1 implementer-
        dispatch (a nyilvántartás `sonnet-impl` sora, `tools/mm-round.sh`
        wrapperrel) NEM a tiltott 'saját magad Claude-ra visszaváltása', mert
        a `resolve_independent_engine` (ADR 0222) már megmérte a
        Claude-kvótát, mielőtt ezt a nevet a promptba írta."""
        self.assertIn("sonnet-impl", self.preamble)
        self.assertIn("tools/mm-round.sh", self.preamble)
        self.assertIn("0222", self.preamble)


if __name__ == "__main__":
    unittest.main()
