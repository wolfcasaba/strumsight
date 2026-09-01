"""A kért slotszám és az önjavító ülés motorja — a repóban utazó user-döntés.

TÖRTÉNET. Az eredeti döntés (2026-08-20, PR #351 Sol-pin kiterjesztése): „mind
a két sloton a Sol orchestrátor és a Terra implementer dolgozzon" — ez akkor
volt vállalható, amikor MINDKÉT slot a Codex-oldali Pro-keretből ment, tehát a
Claude-előfizetést egyik sem terhelte.

HATÁLYOS DÖNTÉS (2026-08-21, „lejárt a GPT kvóta"): a Codex-oldal kiesett, az
orchestrátor/reviewer MINDEN sávon a Claude Sonnet 5 (`--effort high`), az
implementer a `minimax`. Két párhuzamos sáv így ugyanabból az előfizetésből
enne, és épp az a hibaosztály jönne vissza, ami az ADR 0222 rotációt kikényszer-
ítette (a negyedik kör nekimegy a falnak → H-NOSIGNAL halt → önjavító kör, ami
szintén a keretből megy). Ezért a kért slotszám **1** — user-döntés, ugyanazon
a fájl > env > script-default szerződésen.

A fájl két mérhető következményt őriz:

1. **A slotszám a repóban utazik.** A rotációnál MÉRVE (E99-R14 lecke) volt,
   hogy a cron exportált env-je némán felülírja a git-en érkező user-döntést.
   A `PIPELINE_SLOTS` pontosan ugyanez az osztály: a lánc egysávosra eshet
   vissza anélkül, hogy ez bárhol látszana. Ezért a commitolt
   `docs/execution/pipeline-slots` ERŐSEBB az env-nél (file > env >
   script-default), érvénytelen tartalomra pedig fail-closed megáll.
   A RAM-fedezet őre (`effective_slots`, ADR 0171 §1) VÁLTOZATLAN — a fájl a
   KÉRT slotszámot mondja meg, nem a tényleges párhuzamot.

2. **Az önjavító kör is slotot foglal**, tehát a Sol-pin alatt az sem mehetett
   a Claude-keretből: a heal-ülést a Sol vezényelte, a rögzített heal-identitás
   pedig a nyilvántartás `sol` sora, hogy az utolsó kísérlet motorváltása
   (ADR 0307 §2) MÉRHETŐEN más modellre váltson. Pin nélkül — és 2026-08-21 óta
   ez az élő út — minden marad a régi, kvóta-tudatos Claude→Terra bitre; azt a
   `test_selfheal_escalation.py` méri, explicit env-pinnel.

A Sol-ülés GÉPEZETE szándékosan mérve marad a Codex-kimaradás alatt is (a
nyilvántartás `sol` sora, a `fallback` paraméterrel felélesztett cellák): egy
esetleges Codex-újraéledéskor egyetlen fájl átírásával visszakapcsolható.
A Sol↔Terra függetlenség kulcsa változatlanul a MODELL-azonosság: a `sol` sor
implementernek választva ütközik a sol-orchestrátorral (`H-INDEP`,
fail-closed), a `terra` sor nem.

A slotszám megváltoztatásakor a `docs/execution/pipeline-slots` fájlt és a
`test_the_committed_slots_file_value_is_one` cellát EGYÜTT kell átírni —
ugyanaz a szerződés, mint a rotáció-fájlnál.
"""

import datetime as dt
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-pipeline.sh"
SLOTS_FILE = ROOT / "docs" / "execution" / "pipeline-slots"
REGISTRY = ROOT / "docs" / "execution" / "engine-registry.tsv"


def run_driver(*arguments: str, **environment_overrides: str) -> subprocess.CompletedProcess:
    environment = dict(os.environ)
    environment.update(environment_overrides)
    return subprocess.run(
        ["bash", str(SCRIPT), *arguments],
        cwd=ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )


class SlotDecisionTest(unittest.TestCase):
    """A kért slotszám feloldása: file > env > script-default."""

    def test_the_committed_slots_file_value_is_one(self) -> None:
        # A LEGKORÁBBI user-döntés (2026-08-21) egy sávot kért, mert a Codex-oldal
        # kiesésével MINDEN sáv orchestrátora a Claude, és két párhuzamos
        # session ugyanabból az előfizetésből enne.
        #
        # FELÜLÍRVA 2026-08-23 (user-döntés): két sáv fut. Az 1. sáv a mai pár
        # (Sonnet 5 high orchestrátor + MiniMax implementer, „oda nem kell nagy
        # tudás, csak kódolás folyik"), a 2. sáv a Chapter 13 UI-lánc Opus 5 max
        # orchestrátorral és `sonnet-impl` (Sonnet 5 high) implementerrel, mert
        # az UI-minőség a cél. A fenti kvóta-kockázat NEM szűnt meg — a döntés
        # tudatosan vállalja; a fék a session-küszöb
        # (PIPELINE_CLAUDE_SESSION_PCT_MAX — user-döntés 2026-08-23 óta 100,
        # azaz „vidd el a keret végéig"), és PIPELINE_FALLBACK_ENGINE=none
        # mellett a küszöb elérése MINDKÉT sávot megállítja (nincs Codex-oldal:
        # a ChatGPT Pro előfizetés 2026-08-23-án elfogyott, ~egy hónapig).
        #
        # ÚJRA FELÜLÍRVA 2026-09-01 (user-döntés): "az E15-öt várjuk meg, amíg
        # befejezi ezt a kört, de utána állítsd le; fusson csak egy slot a
        # 12-es epiccel." A 2. sáv a Chapter 15 UI-lánc volt — azt a
        # `pipeline-queue.tsv` nyolc `hold` sora állítja meg —, tehát a kért
        # slotszám ismét EGY. A cella EREJE változatlan: továbbra is EGZAKT pin
        # a commitolt fájlra, csak az ÚJ döntésre; a döntési lánc (2026-08-21 ->
        # 08-23 -> 09-01) szándékosan itt marad olvashatóan.
        #
        # VISSZAKAPCSOLÁS: ha a user újra két sávot kér, ez a cella és a
        # `test_the_real_driver_reads_the_committed_file_without_any_env`
        # együtt vált "2"-re a `docs/execution/pipeline-slots`-szal — a
        # queue `hold` sorainak `pending`-re állításával egy időben.
        self.assertEqual(SLOTS_FILE.read_text(encoding="utf-8").strip(), "1")

    def test_the_committed_file_overrides_the_operator_env(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            slots_file = Path(name) / "pipeline-slots"
            slots_file.write_text("3\n", encoding="utf-8")
            result = run_driver(
                "--requested-slots",
                PIPELINE_SLOTS_FILE=str(slots_file),
                PIPELINE_SLOTS="1",
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "3")
        self.assertIn("SLOT-FÁJL", result.stderr)

    def test_the_real_driver_reads_the_committed_file_without_any_env(self) -> None:
        environment = dict(os.environ)
        environment.pop("PIPELINE_SLOTS", None)
        environment.pop("PIPELINE_SLOTS_FILE", None)
        result = subprocess.run(
            ["bash", str(SCRIPT), "--requested-slots"],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        # 2026-09-01 óta ismét EGY sáv (lásd
        # test_the_committed_slots_file_value_is_one) — a driver env nélkül a
        # commitolt fájlt olvassa, tehát ugyanazt az értéket kell adnia.
        self.assertEqual(result.stdout.strip(), "1")

    def test_without_a_file_the_env_semantics_stay_measurable(self) -> None:
        for wanted in ("1", "2", "4"):
            with self.subTest(wanted=wanted):
                result = run_driver(
                    "--requested-slots",
                    PIPELINE_SLOTS_FILE="/dev/null",
                    PIPELINE_SLOTS=wanted,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), wanted)

    def test_an_invalid_slots_file_fails_closed(self) -> None:
        for content in ("banana", "0", "-2", "2.5"):
            with self.subTest(content=content):
                with tempfile.TemporaryDirectory() as name:
                    slots_file = Path(name) / "pipeline-slots"
                    slots_file.write_text(f"{content}\n", encoding="utf-8")
                    result = run_driver(
                        "--requested-slots", PIPELINE_SLOTS_FILE=str(slots_file)
                    )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("érvénytelen slot-érték", result.stderr)

    def test_the_ram_guard_still_caps_the_requested_slots(self) -> None:
        # A fájl a KÉRT sávokat mondja meg; az OOM-őr (docs/LESSONS.md L05)
        # ettől függetlenül visszavehet — épp ez az „őszinte napló" elve.
        result = run_driver(
            "--effective-slots",
            "2",
            PIPELINE_MIN_FREE_GB_PER_SLOT="100000",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "1")
        self.assertIn("SLOT-KORLÁT", result.stderr)


class SolSeatRegistryTest(unittest.TestCase):
    """A `sol` ülés a nyilvántartásban — és a függetlenség mérési kulcsa."""

    def registry_row(self, name: str) -> list[str]:
        for line in REGISTRY.read_text(encoding="utf-8").splitlines():
            if line.startswith("#") or not line.strip() or line.startswith("name\t"):
                continue
            row = line.split("\t")
            if row[0] == name:
                return row
        self.fail(f"nincs '{name}' sor a nyilvántartásban")

    def test_the_registry_carries_the_sol_seat_with_the_driver_default_model(self) -> None:
        row = self.registry_row("sol")
        self.assertEqual(row[1], "codex")
        self.assertEqual(row[3], "gpt-5.6-sol")
        # Ugyanaz a CODEX_HOME/auth, mint a Terráé — a közös Pro-előfizetés a
        # döntés tudatosan vállalt ára (épp a keret égetése a cél).
        self.assertEqual(row[2], self.registry_row("terra")[2])

    def test_the_driver_default_sol_model_matches_the_registry_row(self) -> None:
        shell = (
            "source <(sed -n '1,/^# --- Reviewer-függetlenség/p' \"$PIPELINE_SCRIPT\")\n"
            'printf "%s\\n" "$sol_model"\n'
        )
        result = subprocess.run(
            ["bash", "-c", shell],
            cwd=ROOT,
            env={**os.environ, "PIPELINE_SCRIPT": str(SCRIPT)},
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.registry_row("sol")[3])

    def test_a_sol_implementer_conflicts_with_the_sol_orchestrator_but_terra_does_not(self) -> None:
        # A `sol` sor felvétele nem nyit rést: implementernek választva a
        # modell-azonosság miatt fail-closed H-INDEP, a Terra viszont marad
        # független (két különböző modell).
        shell = (
            # A függetlenség-mérő függvény a reviewer-blokk UTÁN él, ezért a
            # hosszabb prefixet forrásoljuk — a teszthorgok `case` blokkja
            # (a marker UTÁN) így sem fut le.
            "source <(sed -n '1,/^# --- Teszthorgok/p' \"$PIPELINE_SCRIPT\")\n"
            'repo_root="$PIPELINE_ROOT"\n'
            'engine_registry="$PIPELINE_ROOT/docs/execution/engine-registry.tsv"\n'
            'for implementer in sol terra codex minimax; do\n'
            '  if orchestrator_conflicts_with_implementer sol "$implementer"; then\n'
            '    printf "%s=conflict\\n" "$implementer"\n'
            "  else\n"
            '    printf "%s=independent\\n" "$implementer"\n'
            "  fi\n"
            "done\n"
        )
        result = subprocess.run(
            ["bash", "-c", shell],
            cwd=ROOT,
            env={**os.environ, "PIPELINE_SCRIPT": str(SCRIPT), "PIPELINE_ROOT": str(ROOT)},
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.split(),
            ["sol=conflict", "terra=independent", "codex=independent", "minimax=independent"],
        )


class SelfhealSeatTest(unittest.TestCase):
    """Az önjavító kör is slot — a Sol-pin alatt Sol vezényli, Terra javít."""

    def run_attempt(
        self,
        state: Path,
        *,
        attempts: int,
        rotation: str | None,
        # 2026-08-21 óta a driver script-defaultja `none` (a GPT-kvóta
        # elfogyott), a Sol-ülés GÉPEZETE viszont változatlan — az azt mérő
        # cellák ezért explicit `terra` értékkel élesztik fel a Codex-oldalt,
        # a fail-safe cella pedig ugyanezen a paraméteren adja a `none`-t.
        fallback: str = "terra",
    ) -> tuple[subprocess.CompletedProcess, Path, Path]:
        now = int(time.time())
        halted_at = dt.datetime.fromtimestamp(now - 60, tz=dt.timezone.utc).isoformat()
        (state / "HALTED").write_text(
            "round=E99-R42\n"
            "halt=H-NOSIGNAL\n"
            "summary=fixture halt\n"
            f"halted_at={halted_at}\n",
            encoding="utf-8",
        )
        (state / "selfheal.count").write_text(
            f"E99-R42|H-NOSIGNAL|{attempts}\n", encoding="utf-8"
        )

        registry = state / "engine-registry.tsv"
        sol_config = state / "sol"
        terra_config = state / "terra"
        sonnet_config = state / "sonnet"
        for config in (sol_config, terra_config, sonnet_config):
            config.mkdir()
        registry.write_text(
            "name\tharness\tconfig_dir\tmodel\tauth_env\tauth_file\n"
            f"sol\tcodex\t{sol_config}\tgpt-5.6-sol\t-\t-\n"
            f"terra\tcodex\t{terra_config}\tgpt-5.6-terra\t-\t-\n"
            f"sonnet-impl\tclaude\t{sonnet_config}\tclaude-sonnet-5\t-\t-\n",
            encoding="utf-8",
        )

        seat = state / "seat"
        launched_engine = state / "launched-engine"
        shell = """\
source <(sed -n '1,/^# --- Reviewer-függetlenség/p' "$PIPELINE_SCRIPT")
repo_root="$PIPELINE_ROOT"
heal_template="$repo_root/docs/execution/pipeline-selfheal-prompt.md"
notify() { :; }
inflight_add() { :; }
inflight_remove() { :; }
git() { :; }
run_selfheal_session() {
  printf '%s\\n' "$1" > "$LAUNCHED_ENGINE"
  printf '%s\\n' "$orchestrator_preference" > "$SEAT"
  printf 'outcome=retry\\nsummary=fixture retry\\n' > "$heal_status_file"
}
run_orchestrator_session() {
  printf 'orchestrator-session\\n' > "$LAUNCHED_ENGINE"
  printf '%s\\n' "$orchestrator_preference" > "$SEAT"
  printf 'outcome=retry\\nsummary=fixture retry\\n' > "$heal_status_file"
}
attempt_selfheal
"""
        environment = dict(os.environ)
        environment.update(
            PIPELINE_SCRIPT=str(SCRIPT),
            PIPELINE_ROOT=str(ROOT),
            PIPELINE_STATE_DIR=str(state),
            PIPELINE_ENGINE_REGISTRY=str(registry),
            PIPELINE_SELFHEAL_MAX="3",
            PIPELINE_TEST_NOW=str(now),
            PIPELINE_FALLBACK_ENGINE=fallback,
            SEAT=str(seat),
            LAUNCHED_ENGINE=str(launched_engine),
        )
        if rotation is None:
            environment["PIPELINE_ORCH_ROTATION_FILE"] = "/dev/null"
            environment["PIPELINE_ORCH_ROTATION"] = "alternate"
        else:
            rotation_file = state / "orchestrator-rotation"
            rotation_file.write_text(f"{rotation}\n", encoding="utf-8")
            environment["PIPELINE_ORCH_ROTATION_FILE"] = str(rotation_file)

        completed = subprocess.run(
            ["bash", "-c", shell],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
        return completed, seat, launched_engine

    def test_under_the_sol_pin_the_heal_is_orchestrated_by_sol(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            completed, seat, launched = self.run_attempt(state, attempts=0, rotation="sol")

            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(seat.read_text(encoding="utf-8").strip(), "sol")
            self.assertEqual(
                launched.read_text(encoding="utf-8").strip(), "orchestrator-session"
            )

    def test_without_the_pin_the_heal_stays_on_the_claude_path(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            completed, seat, launched = self.run_attempt(state, attempts=0, rotation=None)

            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(seat.read_text(encoding="utf-8").strip(), "claude")
            self.assertEqual(
                launched.read_text(encoding="utf-8").strip(), "orchestrator-session"
            )

    def test_the_last_attempt_under_the_pin_varies_to_a_different_model(self) -> None:
        # ADR 0307 §2 lever: a harmadik kísérlet MÁS modellel megy. A Sol-ülés
        # nyilvántartásbeli sora nélkül ez némán elmaradna (a
        # `heal_engine_for_attempt` ismeretlen névre a saját motort adja).
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            completed, _seat, launched = self.run_attempt(state, attempts=2, rotation="sol")

            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(launched.read_text(encoding="utf-8").strip(), "terra")
            self.assertIn("ÖNJAVÍTÓ MOTORVÁLTÁS: E99-R42 sol → terra", completed.stderr)

    def test_a_disabled_codex_fallback_keeps_the_heal_on_the_claude_path(self) -> None:
        # `PIPELINE_FALLBACK_ENGINE=none` a fail-safe: Codex-oldal nélkül a Sol
        # sem indítható, tehát a heal nem maradhat motor nélkül.
        with tempfile.TemporaryDirectory() as name:
            state = Path(name)
            completed, seat, _launched = self.run_attempt(
                state, attempts=0, rotation="sol", fallback="none"
            )

            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(seat.read_text(encoding="utf-8").strip(), "claude")


if __name__ == "__main__":
    unittest.main()
