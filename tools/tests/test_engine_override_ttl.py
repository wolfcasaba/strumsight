"""Engine-override TTL és 72 órás kor-figyelmeztetés (E99-R14 D2 / ADR 0307 §1).

A driver motor-override blokkja a KÖR-KIVÁLASZTÁSKOR ellenőrzi a lejáratot
és a fájl korát. A mérce-mátrix három cellát rögzít:

  | eset                  | feltétel                          | elvárt viselkedés                  |
  | --------------------- | --------------------------------- | ---------------------------------- |
  | küszöb ALATT          | < 72 óra, nincs explicit expiry   | az override ÉL                     |
  | küszöb RAJTA          | pont 72 óra                       | figyelmeztetés + napi 1 ntfy       |
  | küszöb FÖLÖTT         | > 72 óra, expires_at A MÚLTBAN    | a fájl TÖRLŐDIK, queue lép vissza  |

Falszifikációs cella: ha a D2 lejárat-ellenőrzését kiveszem (az
`expires_at` összehasonlítás törlése), a lejárati eset PIROS kell legyen.
A második falszifikáció: ha a 72 órás kor-figyelmeztetést kiveszem, a
rajta-cellának IGEN figyelmeztetnie kell (a teszt a figyelmeztetés
TÉNYÉT méri, nem a kód elérési útját).

A teszthorog a `tools/round-pipeline.sh --engine-override-evaluate` hook,
amely ELŐTT a body initje lefut, és a TESZTHOROGNAK szánt viselkedést
csendben, log/ntfy nélkül adja vissza. A kimenet:
  stdout: <motor> | EXPIRED | <empty>
  exit:   0=live · 1=expired · 2=stale (warn) · 3=no-file
"""

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "tools" / "round-pipeline.sh"


def _make_legacy_override(override_path: Path, engine: str) -> None:
    """A régi, egysoros alak — csak motornév, lejárat nélkül."""
    override_path.write_text(f"{engine}\n", encoding="utf-8")


def _make_ttl_override(override_path: Path, engine: str, expires_at: str, reason: str = "-") -> None:
    """Az új, 3 soros alak — engine=/expires_at=/reason=."""
    override_path.write_text(
        f"engine={engine}\nexpires_at={expires_at}\nreason={reason}\n",
        encoding="utf-8",
    )


def _override_age_hours(override_path: Path, hours: float) -> None:
    """A `use` parancs a mtime-ot frissíti, de a tesztben szükség van egy
    konkrét korra — `touch -d` közvetlenül a tesztből hívható, ezt a
    wrapper az `os.utime`-szal adja vissza."""
    seconds = int(hours * 3600)
    target = _now_epoch() - seconds
    os.utime(override_path, (target, target))


def _now_epoch() -> int:
    return int(subprocess.check_output(["date", "+%s"], text=True).strip())


def run_evaluate(state_dir: Path, queue_engine: str = "minimax", warned_hours: str | None = None) -> tuple[int, str]:
    """A driver teszthorogját hívja, visszaadja (exit_code, stdout)."""
    environment = dict(os.environ)
    environment["PIPELINE_STATE_DIR"] = str(state_dir)
    if warned_hours is not None:
        environment["PIPELINE_OVERRIDE_WARN_HOURS"] = warned_hours
    result = subprocess.run(
        ["bash", str(DRIVER), "--engine-override-evaluate", queue_engine],
        capture_output=True, text=True, env=environment, cwd=ROOT,
    )
    return result.returncode, (result.stdout or "").strip()


class EngineOverrideTTLTest(unittest.TestCase):
    """A D2 mérce-mátrix 3 cellája — a küszöb alatt/rajta/fölött."""

    def setUp(self) -> None:
        self._state = tempfile.TemporaryDirectory()
        self.addCleanup(self._state.cleanup)
        self.state = Path(self._state.name)
        self.override = self.state / "engine-override"

    def test_under_threshold_is_live(self) -> None:
        """§4 1. cella: 71 órás, lejárat nélküli override → live, nincs figy."""
        _make_legacy_override(self.override, "qwen-plus")
        _override_age_hours(self.override, 71)

        exit_code, stdout = run_evaluate(self.state)

        self.assertEqual(exit_code, 0, msg=f"küszöb alatt LIVE kell, exit {exit_code}, stdout {stdout!r}")
        self.assertEqual(stdout, "qwen-plus")
        self.assertTrue(self.override.exists(), "a fájl nem törölhető a küszöb alatt")

    def test_exactly_threshold_is_stale_warning(self) -> None:
        """§4 2. cella: pontosan 72 óra → STALE (warning), napi 1 ntfy, az override ÉL."""
        _make_legacy_override(self.override, "qwen-plus")
        _override_age_hours(self.override, 72)

        exit_code, stdout = run_evaluate(self.state)

        self.assertEqual(exit_code, 2, msg=f"pont 72 óra: STALE kell, exit {exit_code}, stdout {stdout!r}")
        self.assertEqual(stdout, "qwen-plus")
        self.assertTrue(self.override.exists(), "a STALE warning nem törölheti a fájlt")

    def test_over_threshold_is_stale_warning(self) -> None:
        """§4 3. cella (1. fele): 73 óra régi, nincs expiry → STALE, ÉL."""
        _make_legacy_override(self.override, "qwen-plus")
        _override_age_hours(self.override, 73)

        exit_code, _ = run_evaluate(self.state)

        self.assertEqual(exit_code, 2, msg=f"73 óra: STALE kell, exit {exit_code}")
        self.assertTrue(self.override.exists())

    def test_expires_at_in_past_triggers_deletion(self) -> None:
        """§4 3. cella (2. fele): explicit expires_at a múltban → EXPIRED, a fájl TÖRLŐDIK."""
        _make_ttl_override(self.override, "qwen-plus", expires_at=str(_now_epoch() - 60), reason="kvóta")

        exit_code, stdout = run_evaluate(self.state)

        self.assertEqual(exit_code, 1, msg=f"lejárt: EXPIRED (1) kell, exit {exit_code}, stdout {stdout!r}")
        self.assertEqual(stdout, "EXPIRED")
        self.assertFalse(self.override.exists(), "a lejárt fájlt TÖRÖLNI kell")

    def test_expires_at_in_future_is_live_even_if_file_old(self) -> None:
        """200 órás mtime, de az expires_at a JÖVŐBEN → LIVE, nincs STALE warning.

        A `use` parancs a mtime-ot a TTL-lel együtt frissíti, ez a teszt
        azt mutatja, hogy a jövőbeni lejárat FELÜLÍRJA a kor-figyelmeztetést
        (a használó szándékosan hosszabbít, ne zavarjuk)."""
        _make_ttl_override(self.override, "qwen-plus", expires_at=str(_now_epoch() + 36000), reason="kvóta")
        _override_age_hours(self.override, 200)

        exit_code, stdout = run_evaluate(self.state)

        self.assertEqual(exit_code, 0, msg=f"jövőbeni expiry → LIVE, exit {exit_code}, stdout {stdout!r}")
        self.assertEqual(stdout, "qwen-plus")
        self.assertTrue(self.override.exists())

    def test_no_file_is_empty(self) -> None:
        """Nincs override-fájl → a queue engine oszlopa dönt (a hook itt <empty>-t ad)."""
        # Nem hozunk létre fájlt.
        exit_code, stdout = run_evaluate(self.state)

        self.assertEqual(exit_code, 3)
        self.assertEqual(stdout, "<empty>")

    def test_legacy_one_line_format_is_accepted(self) -> None:
        """Visszafelé kompatibilitás: a régi, egysoros alak (TTL nélkül) érvényes."""
        self.override.write_text("sonnet-impl\n", encoding="utf-8")
        _override_age_hours(self.override, 1)

        exit_code, stdout = run_evaluate(self.state)

        self.assertEqual(exit_code, 0)
        self.assertEqual(stdout, "sonnet-impl")

    def test_threshold_is_configurable(self) -> None:
        """PIPELINE_OVERRIDE_WARN_HOURS=24 — 25 órára STALE, 23 órára LIVE."""
        _make_legacy_override(self.override, "qwen-plus")
        _override_age_hours(self.override, 25)

        exit_code, _ = run_evaluate(self.state, warned_hours="24")
        self.assertEqual(exit_code, 2, msg="PIPELINE_OVERRIDE_WARN_HOURS=24 → 25h STALE")

        _override_age_hours(self.override, 23)
        exit_code, stdout = run_evaluate(self.state, warned_hours="24")
        self.assertEqual(exit_code, 0, msg=f"PIPELINE_OVERRIDE_WARN_HOURS=24 → 23h LIVE, exit {exit_code}, stdout {stdout!r}")
        self.assertEqual(stdout, "qwen-plus")


class EngineOverrideFalsificationTest(unittest.TestCase):
    """Falszifikációs cella (brief §4, kötelező).

    A D2 lejárat-ellenőrzését kikapcsoljuk a forrásban (az `expires_at`
    összehasonlítás ELTÁVOLÍTÁSA), és megnézzük, hogy a lejárati teszt
    PIROS lesz-e. Ha a teszt a kiszedés után is zöld, akkor a teszt
    HIBÁS, nem a kód — ezt a falszifikációs cella garantálja, hogy ne
    fordulhasson elő (docs/LESSONS.md L09).
    """

    def setUp(self) -> None:
        self._state = tempfile.TemporaryDirectory()
        self.addCleanup(self._state.cleanup)
        self.state = Path(self._state.name)
        self.override = self.state / "engine-override"
        self._original_source = DRIVER.read_text(encoding="utf-8")

    def tearDown(self) -> None:
        # A forrást MINDIG visszaállítjuk — egy kósza hiba nem hagyhat
        # módosított kódot a lemezen.
        DRIVER.write_text(self._original_source, encoding="utf-8")

    def test_lejarat_ellenorzes_kivetelevel_a_lejarati_teszt_piros(self) -> None:
        """A lejárat-ellenőrzés kikapcsolása → a lejárati teszt PIROS."""
        # A minta a BODY-ból származik (8 spaces), de a hook eltérő
        # behúzással rendelkezik — `re.sub` MINDKETTŐT lecseréli globálisan.
        modified, count = re.subn(
            r'\[ "\$\(date \+%s\)" -ge "\$expires_at" \]; then',
            '[ 1 -eq 0 ]; then  # E99-R14 falszifikáció: lejárat-ellenőrzés KIKAPCSOLVA',
            self._original_source,
        )
        self.assertGreater(count, 0, "a módosítás nem illeszkedett — a teszt nem ellenőrizhető")
        DRIVER.write_text(modified, encoding="utf-8")

        # A lejárati eset most a KIKAPCSOLT kód miatt LIVE (exit 0) kell
        # legyen — a fájl NEM törlődik. A tesztünk azt mondja, hogy
        # EXPIRED kell legyen, tehát a kód → a teszt RÖVIDREZÁRVA.
        _make_ttl_override(self.override, "qwen-plus", expires_at=str(_now_epoch() - 60), reason="rövidre")
        exit_code, stdout = run_evaluate(self.state)

        self.assertNotEqual(
            exit_code, 1,
            msg="Ha a lejárat-ellenőrzés KI a forrásban, a teszt TÉNYLEG kideríti: "
                f"a lejárati eset exit {exit_code} ({stdout!r}), nem 1. "
                "A teszt NEM őrzi az invariánst — JAVÍTANI kell a kódot, nem a tesztet.",
        )
        self.assertTrue(
            self.override.exists(),
            "Ha a lejárat-ellenőrzés KI, a fájl NEM törlődik — a teszt PIROS, ahogy kell.",
        )

    def test_kor_figyelmeztetes_kivetelevel_a_kuszob_rajta_teszt_piros(self) -> None:
        """A kor-figyelmeztetés kikapcsolása → a 72 óra pontos-teszt PIROS.

        A D2 72 órás figyelmeztetését kivesszük az `awk` sor átírásával
        — `re.sub` a test `print (a >= t) ? 1 : 0` mintát keresi, és
        a `print 0`-val helyettesíti (MINDKÉT előfordulás)."""
        modified, count = re.subn(
            r"above=\$\(awk -v a=\"\$age_hours\" -v t=\"\$override_warn_threshold\" 'BEGIN \{ print \(a >= t\) \? 1 : 0 \}'\)",
            "above=0  # E99-R14 falszifikáció: kor-figyelmeztetés KIKAPCSOLVA",
            self._original_source,
        )
        self.assertGreater(count, 0, f"a módosítás nem illeszkedett (count={count})")
        DRIVER.write_text(modified, encoding="utf-8")

        # A 72 órás eset most LIVE (exit 0) kell legyen — a teszt azt
        # mondja, hogy STALE (exit 2) kell. A kód → a teszt RÖVIDREZÁRVA.
        _make_legacy_override(self.override, "qwen-plus")
        _override_age_hours(self.override, 72)

        exit_code, stdout = run_evaluate(self.state)

        self.assertNotEqual(
            exit_code, 2,
            msg="Ha a kor-figyelmeztetés KI a forrásban, a 72h teszt TÉNYLEG kideríti: "
                f"az exit {exit_code} ({stdout!r}), nem 2. A teszt NEM őrzi az invariánst.",
        )


if __name__ == "__main__":
    unittest.main()
