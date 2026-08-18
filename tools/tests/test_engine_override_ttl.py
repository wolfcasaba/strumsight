"""Engine-override TTL és 72 órás kor-figyelmeztetés (E99-R14 D2 / ADR 0307 §1).

A driver motor-override blokkja a KÖR-KIVÁLASZTÁSKOR ellenőrzi a lejáratot
és a fájl korát. A mérce-mátrix három cellát rögzít:

  | eset                  | feltétel                          | elvárt viselkedés                  |
  | --------------------- | --------------------------------- | ---------------------------------- |
  | küszöb ALATT          | < 72 óra, nincs explicit expiry   | az override ÉL                     |
  | küszöb RAJTA          | pont 72 óra                       | figyelmeztetés + napi 1 ntfy       |
  | küszöb FÖLÖTT         | > 72 óra, expires_at A MÚLTBAN    | a fájl TÖRLŐDIK, queue lép vissza  |

Falszifikációs cella (m3 javítás — `tools/engine-profile.sh` `evaluate`
parancsával, M2 izolált másolattal): ha a lejárat-ellenőrzést kivesszük
a forrásból, a lejárati eset PIROS kell legyen. A második falszifikáció:
ha a 72 órás kor-figyelmeztetést kivesszük, a rajta-cellának IGEN
figyelmeztetnie kell (a teszt a figyelmeztetés TÉNYÉT méri, nem a kód
elérési útját).

M3 javítás: a kiértékelés a `tools/engine-profile.sh evaluate` parancsra
van bízva — a driver motor-override blokkja ÉS a tesztek UGYANAZT a
függvényt hívják, nincs duplikált logika. A korábbi
`--engine-override-evaluate` top-level hook törölve.

M2 javítás: a falszifikációs tesztek a forrást IZOLÁLT MÁSOLATON
módosítják (a `tools/engine-profile.sh` átmeneti másolata + a registry
átmeneti másolata a registry-feloldáshoz) — a termelési forrás
érintetlen marad, párhuzamos futás / processz-halál mellett sem.
"""

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# M3 javítás: a kiértékelést a `tools/engine-profile.sh` `evaluate` parancsa
# végzi. A driver és a tesztek is ezt hívják — nincs duplikált logika.
PROFILE = ROOT / "tools" / "engine-profile.sh"
REGISTRY = ROOT / "docs" / "execution" / "engine-registry.tsv"


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


def run_evaluate(state_dir: Path, profile_script: Path, warn_hours: str | None = None) -> tuple[int, str]:
    """A `tools/engine-profile.sh evaluate` parancsot hívja.

    M3 javítás: a driver motor-override blokkja is ezt hívja, így a
    teszt és a termelési út egyetlen logikát mér. A `profile_script`
    paraméter a falszifikációs tesztek izolált MÁSOLATÁRA mutat (M2).
    """
    environment = dict(os.environ)
    environment["PIPELINE_STATE_DIR"] = str(state_dir)
    if warn_hours is not None:
        environment["PIPELINE_OVERRIDE_WARN_HOURS"] = warn_hours
    result = subprocess.run(
        ["bash", str(profile_script), "evaluate"],
        capture_output=True, text=True, env=environment, cwd=ROOT,
    )
    return result.returncode, (result.stdout or "").strip()


class _IsolatedProfileMixin:
    """M2 javítás: a falszifikációs tesztek a `tools/engine-profile.sh`-t és
    a registry-t egy átmeneti könyvtárba MÁSOLJÁK, és a forrást CSAK ott
    módosítják. A termelési forrás ÉRINTETLEN marad, párhuzamos futás
    vagy processz-halál mellett sem.

    A `self.profile_copy` az izolált másolat útvonala.
    A `setUp` létrehozza, a `tearDown` (vagy `addCleanup`) törli.
    """

    def _stage_isolated_profile(self) -> Path:
        """Az izolált profil-másolat előkészítése. A másolat a `tools/`
        almappába kerül, hogy a fájl BASH_SOURCE-származtatott `repo_root`
        feloldása a registry-hez jusson (a registry a `<repo_root>/docs/
        execution/engine-registry.tsv`).

        Visszatérési érték: a másolat útvonala (a `evaluate` parancs
        indításához).
        """
        temp = Path(tempfile.mkdtemp(prefix="e99-r14-iso-"))
        self.addCleanup(shutil.rmtree, temp, ignore_errors=True)

        # engine-profile.sh a tools/ almappába
        profile_dir = temp / "tools"
        profile_dir.mkdir(parents=True)
        profile_copy = profile_dir / "engine-profile.sh"
        shutil.copy(PROFILE, profile_copy)

        # Registry a docs/execution/ almappába
        registry_dir = temp / "docs" / "execution"
        registry_dir.mkdir(parents=True)
        shutil.copy(REGISTRY, registry_dir / "engine-registry.tsv")

        return profile_copy


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

        exit_code, stdout = run_evaluate(self.state, PROFILE)

        self.assertEqual(exit_code, 0, msg=f"küszöb alatt LIVE kell, exit {exit_code}, stdout {stdout!r}")
        self.assertEqual(stdout, "qwen-plus")
        self.assertTrue(self.override.exists(), "a fájl nem törölhető a küszöb alatt")

    def test_exactly_threshold_is_stale_warning(self) -> None:
        """§4 2. cella: pontosan 72 óra → STALE (warning), napi 1 ntfy, az override ÉL."""
        _make_legacy_override(self.override, "qwen-plus")
        _override_age_hours(self.override, 72)

        exit_code, stdout = run_evaluate(self.state, PROFILE)

        self.assertEqual(exit_code, 2, msg=f"pont 72 óra: STALE kell, exit {exit_code}, stdout {stdout!r}")
        self.assertEqual(stdout, "qwen-plus")
        self.assertTrue(self.override.exists(), "a STALE warning nem törölheti a fájlt")

    def test_over_threshold_is_stale_warning(self) -> None:
        """§4 3. cella (1. fele): 73 óra régi, nincs expiry → STALE, ÉL."""
        _make_legacy_override(self.override, "qwen-plus")
        _override_age_hours(self.override, 73)

        exit_code, _ = run_evaluate(self.state, PROFILE)

        self.assertEqual(exit_code, 2, msg=f"73 óra: STALE kell, exit {exit_code}")
        self.assertTrue(self.override.exists())

    def test_expires_at_in_past_triggers_deletion(self) -> None:
        """§4 3. cella (2. fele): explicit expires_at a múltban → EXPIRED, a fájl TÖRLŐDIK."""
        _make_ttl_override(self.override, "qwen-plus", expires_at=str(_now_epoch() - 60), reason="kvóta")

        exit_code, stdout = run_evaluate(self.state, PROFILE)

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

        exit_code, stdout = run_evaluate(self.state, PROFILE)

        self.assertEqual(exit_code, 0, msg=f"jövőbeni expiry → LIVE, exit {exit_code}, stdout {stdout!r}")
        self.assertEqual(stdout, "qwen-plus")
        self.assertTrue(self.override.exists())

    def test_no_file_is_empty(self) -> None:
        """Nincs override-fájl → a queue engine oszlopa dönt (a hook itt <empty>-t ad)."""
        # Nem hozunk létre fájlt.
        exit_code, stdout = run_evaluate(self.state, PROFILE)

        self.assertEqual(exit_code, 3)
        self.assertEqual(stdout, "<empty>")

    def test_legacy_one_line_format_is_accepted(self) -> None:
        """Visszafelé kompatibilitás: a régi, egysoros alak (TTL nélkül) érvényes."""
        self.override.write_text("sonnet-impl\n", encoding="utf-8")
        _override_age_hours(self.override, 1)

        exit_code, stdout = run_evaluate(self.state, PROFILE)

        self.assertEqual(exit_code, 0)
        self.assertEqual(stdout, "sonnet-impl")

    def test_threshold_is_configurable(self) -> None:
        """PIPELINE_OVERRIDE_WARN_HOURS=24 — 25 órára STALE, 23 órára LIVE."""
        _make_legacy_override(self.override, "qwen-plus")
        _override_age_hours(self.override, 25)

        exit_code, _ = run_evaluate(self.state, PROFILE, warn_hours="24")
        self.assertEqual(exit_code, 2, msg="PIPELINE_OVERRIDE_WARN_HOURS=24 → 25h STALE")

        _override_age_hours(self.override, 23)
        exit_code, stdout = run_evaluate(self.state, PROFILE, warn_hours="24")
        self.assertEqual(exit_code, 0, msg=f"PIPELINE_OVERRIDE_WARN_HOURS=24 → 23h LIVE, exit {exit_code}, stdout {stdout!r}")
        self.assertEqual(stdout, "qwen-plus")


class EngineOverrideFalsificationTest(unittest.TestCase, _IsolatedProfileMixin):
    """Falszifikációs cella (brief §4, kötelező).

    M2 javítás: a forrást IZOLÁLT MÁSOLATON módosítjuk. A termelési
    `tools/engine-profile.sh` ÉRINTETLEN marad — sem a teszt futása
    alatt, sem párhuzamos futás / processz-halál esetén. A `setUp`
    előkészíti a másolatot, a `tearDown` (vagy `addCleanup`) törli.
    """

    def setUp(self) -> None:
        self._state = tempfile.TemporaryDirectory()
        self.addCleanup(self._state.cleanup)
        self.state = Path(self._state.name)
        self.override = self.state / "engine-override"
        # M2 javítás: a forrást IZOLÁLT MÁSOLATON tesszük — a termelési
        # `tools/engine-profile.sh` nem módosul, a teszt a másolaton dolgozik.
        self.profile_copy = self._stage_isolated_profile()
        self._original_source = self.profile_copy.read_text(encoding="utf-8")

    def tearDown(self) -> None:
        # M2 javítás: a forrást MINDIG visszaállítjuk (a másolatot) — egy
        # kósza hiba nem hagyhat módosított kódot a lemezen. A teljes
        # temp-könyvtárat amúgy is törli az `_stage_isolated_profile`
        # `addCleanup` regisztrációja; ez a régi szöveget csak azért
        # őrzi, hogy a `tearDown` BIZTONSÁGOS legyen.
        self.profile_copy.write_text(self._original_source, encoding="utf-8")

    def test_lejarat_ellenorzes_kivetelevel_a_lejarati_teszt_piros(self) -> None:
        """A lejárat-ellenőrzés kikapcsolása → a lejárati teszt PIROS.

        M3 javítás: a `re.sub` a megosztott függvényben (`engine_override_evaluate`)
        lévő sort módosítja, amit a driver is hív. M2 javítás: a módosítás
        a másolaton fut, a termelési forrás nem változik.
        """
        # Az `engine_override_evaluate` függvényben a lejárat-ellenőrzés
        # patternje: `[ "$(date +%s)" -ge "$expires_at" ]`. Ezt cseréljük
        # `[ 1 -eq 0 ]`-ra (mindig hamis → sose jár le).
        modified, count = re.subn(
            r'\[ "\$\(date \+%s\)" -ge "\$expires_at" \]; then',
            '[ 1 -eq 0 ]; then  # E99-R14 falszifikáció: lejárat-ellenőrzés KIKAPCSOLVA',
            self._original_source,
        )
        self.assertGreater(count, 0, "a módosítás nem illeszkedett — a teszt nem ellenőrizhető")
        self.profile_copy.write_text(modified, encoding="utf-8")

        # A lejárati eset most a KIKAPCSOLT kód miatt LIVE (exit 0) kell
        # legyen — a fájl NEM törlődik. A tesztünk azt mondja, hogy
        # EXPIRED kell legyen, tehát a kód → a teszt RÖVIDREZÁRVA.
        _make_ttl_override(self.override, "qwen-plus", expires_at=str(_now_epoch() - 60), reason="rövidre")
        exit_code, stdout = run_evaluate(self.state, self.profile_copy)

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

        M3 javítás: a `re.sub` a megosztott függvény `awk ... (a >= t) ? 1 : 0`
        szűrőjét írja át `print 0`-ra (mindig hamis → sose STALE). M2 javítás:
        a módosítás a másolaton fut, a termelési forrás nem változik.
        """
        modified, count = re.subn(
            r"above=\$\(awk -v a=\"\$age_hours\" -v t=\"\$warn_threshold\" 'BEGIN \{ print \(a >= t\) \? 1 : 0 \}'\)",
            "above=0  # E99-R14 falszifikáció: kor-figyelmeztetés KIKAPCSOLVA",
            self._original_source,
        )
        self.assertGreater(count, 0, f"a módosítás nem illeszkedett (count={count})")
        self.profile_copy.write_text(modified, encoding="utf-8")

        # A 72 órás eset most LIVE (exit 0) kell legyen — a teszt azt
        # mondja, hogy STALE (exit 2) kell. A kód → a teszt RÖVIDREZÁRVA.
        _make_legacy_override(self.override, "qwen-plus")
        _override_age_hours(self.override, 72)

        exit_code, stdout = run_evaluate(self.state, self.profile_copy)

        self.assertNotEqual(
            exit_code, 2,
            msg="Ha a kor-figyelmeztetés KI a forrásban, a 72h teszt TÉNYLEG kideríti: "
                f"az exit {exit_code} ({stdout!r}), nem 2. A teszt NEM őrzi az invariánst.",
        )


if __name__ == "__main__":
    unittest.main()
