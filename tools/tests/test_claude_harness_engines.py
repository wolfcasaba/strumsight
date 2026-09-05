"""A claude-harness implementer két üzemmódja (ADR 0140 kiterjesztés, 2026-08-06).

MIÉRT: a `tools/mm-round.sh` eddig BEDRÓTOZVA a MiniMax `/anthropic`
endpointjára futott, és kulcs nélkül kilépett. A Terra keret 1%-ra fogyásakor a
user natív Claude-modellt (Sonnet 5) kért implementernek az ELŐFIZETÉSEN —
ehhez a burkolónak két üzemmódot kell tudnia:

* **külső endpoint** (MiniMax M3): kulcs + `ANTHROPIC_BASE_URL` override;
* **natív Claude-modell**: NINCS override, a config dir saját auth-ja hitelesít.

A tesztek hamis `claude` binárissal mérik, mit ad át a burkoló — hálózat és
modellhívás nélkül.

Negyedik mért hibaminta (E06-R23 self-heal, ADR 0112, 2026-08-12): a Claude
helyesen megírta a `status=stopped` jelzést (H3 scope-sértés), a `claude -p`
folyamat mégis percekig tovább futott — hat további commitot hozva létre a
jelzés UTÁN, mielőtt ~15 perccel később magától kilépett. Lásd
`test_a_process_that_keeps_running_after_signaling_is_killed_promptly`.

Ötödik mért hibaminta (E99-R17 H6 self-heal, ADR 0112, 2026-08-20): a
`run_wrapper` `dict(os.environ)`-ból indul, ezért ha ez a pytest-futás maga is
egy `ROUND_ENGINE=minimax` implementer-session Bash-hívásaként fut (a
kötelező §7 gate), a szülő session saját `ANTHROPIC_BASE_URL`/
`ANTHROPIC_AUTH_TOKEN`/`CLAUDE_CODE_AUTO_COMPACT_WINDOW`/`MINIMAX_API_KEY`
exportjai változatlanul bekerülnek a szimulált alfolyamatba, és két
`sonnet-impl` (natív, "nincs override") eset hamisan PIROSRA vált. Mérve:
`ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic ANTHROPIC_AUTH_TOKEN=x
CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000 MINIMAX_API_KEY=x python3 -m pytest
tools/tests/test_claude_harness_engines.py -q` → 2 failed (ugyanaz a két eset,
amit a `mm-round.sh` saját gate-futása H6-ként jelzett). Lásd
`test_ambient_endpoint_env_does_not_leak_into_a_subscription_mode_run`.

Hatodik mért hibaminta (E99-R20 H6 self-heal, ADR 0112, 2026-08-20): ugyanez
az osztály, más forrás. Az ötödik minta a `mm-round.sh` SAJÁT (`external_endpoint`
ághoz tartozó) `launch_env`-jét takarította ki; a `tools/codex-round.sh`
motor-profil blokkja viszont EGY SZINTTEL FELJEBB, a hívó session sajátjaként
exportálja a `tools/engine-profile.sh env <motor>` teljes kimenetét
(`ENGINE_MODEL`, `ENGINE_STALL_MINUTES`, `ENGINE_ROUND_TIMEOUT`,
`ENGINE_CONTEXT_WINDOW`, `ENGINE_MAX_OUTPUT`, `ENGINE_REASONING`, valamint
`CODEX_HOME`/`CLAUDE_CONFIG_DIR`) — ez a §7 gate-en ÁT ugyanúgy bekerül a
`dict(os.environ)`-ba. Mérve: az E99-R20 `terra` implementer futása alatt
`bash tools/engine-profile.sh env terra` → `ENGINE_MODEL=gpt-5.6-terra`
(+ a fenti hattal), és a leszivárgott `ENGINE_MODEL` a `mm-round.sh:82`
`model=${MM_MODEL:-${ENGINE_MODEL:-MiniMax-M3[1m]}}` során a "nincs
ROUND_ENGINE" (`""`) esetben — ahol a wrapper SAJÁT `if [ -n "$round_engine" ]`
ága helyesen NEM fut le, tehát NEM ír felül semmit — közvetlenül a hamis,
ambiens `gpt-5.6-terra` értéket adta a `--model` kapcsolónak a történeti
MiniMax-alapértelmezés (`MiniMax-M3[1m]`) helyett. `python3 -m pytest
tools/tests -q` a valódi Terra-worktree-ben (`/home/ubuntu/ss-terra-e99-r20`,
head `21224fa9`) kétszer egymás után `1 failed, 656 passed`-et mért
(`WrapperModeTest.test_the_legacy_call_without_round_engine_stays_minimax`);
egy KÜLÖN, friss shellben futtatott `ROUND_ENGINE=terra python3 -m pytest
tools/tests -q` viszont zöld, mert ott hiányzik a `codex-round.sh` teljes
export-blokkja — a puszta `ROUND_ENGINE=terra` NEM elég a reprodukcióhoz,
a `tools/engine-profile.sh env terra` teljes hat sora kell. Lásd
`test_ambient_engine_profile_env_does_not_leak_into_the_legacy_run`.
"""

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "tools" / "mm-round.sh"
REGISTRY = ROOT / "docs" / "execution" / "engine-registry.tsv"

FAKE_CLAUDE = """#!/usr/bin/env bash
{
  printf 'BASE_URL=%s\\n' "${ANTHROPIC_BASE_URL:-<nincs>}"
  printf 'AUTH_TOKEN=%s\\n' "${ANTHROPIC_AUTH_TOKEN:+<van>}"
  printf 'CONFIG_DIR=%s\\n' "${CLAUDE_CONFIG_DIR:-<nincs>}"
  printf 'COMPACT=%s\\n' "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-<nincs>}"
  printf 'ARGS=%s\\n' "$*"
  printf 'PROMPT=%s\\n' "$(printf '%s' "$2" | head -c 4000)"
} >> "$FAKE_CLAUDE_OUT"
[ "${FAKE_NO_WORK:-0}" = "1" ] || printf 'munka\\n' >> "$FAKE_WORKFILE"
printf 'status=done\\nsummary=kesz\\n' > "$FAKE_SIGNAL"
if [ "${FAKE_CLAUDE_MODE:-exit}" = "hang-after-signal" ]; then
  # MÉRT eset (E06-R23 self-heal, 2026-08-12): a jelzés megírása után a
  # folyamat NEM állt le magától — ezt szimulálja ez a hosszú sleep.
  sleep 120
fi
exit 0
"""


def registry_row(name: str) -> list[str]:
    for line in REGISTRY.read_text(encoding="utf-8").splitlines():
        if line.startswith(f"{name}\t"):
            return line.split("\t")
    raise AssertionError(f"nincs ilyen motor a nyilvántartásban: {name}")


class RegistryTest(unittest.TestCase):
    def test_the_subscription_engine_declares_no_api_key(self) -> None:
        """A natív Claude-motor auth-ja a config dirben él, nem kulcsfájlban."""
        row = registry_row("sonnet-impl")
        self.assertEqual(row[1], "claude")
        self.assertEqual(row[3], "claude-sonnet-5")
        self.assertEqual((row[4], row[5]), ("-", "-"))
        # user-döntés 2026-08-23: „az implementátor pedig sonnet 5 high" — a
        # `sonnet-impl` az UI-sáv implementere, a fölötte ülő orchestrátor
        # Opus 5 (orch_pair_model/orch_pair_effort a driverben; az effort
        # 2026-08-25 óta `high` — lásd a heti-keret mérést,
        # docs/execution/ch13-throughput-diagnosis.md).
        self.assertEqual(row[12], "high", "a --effort szint a reasoning oszlopból jön")

    def test_the_minimax_engine_still_declares_its_key(self) -> None:
        row = registry_row("minimax")
        self.assertEqual(row[4], "MINIMAX_API_KEY")


class WrapperModeTest(unittest.TestCase):
    def run_wrapper(self, engine: str, *, extra_env=None, timeout=None):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        base = Path(directory.name)
        workdir = base / "work"
        workdir.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=workdir, check=True)
        subprocess.run(["git", "config", "user.email", "t@e.hu"], cwd=workdir, check=True)
        subprocess.run(["git", "config", "user.name", "T"], cwd=workdir, check=True)
        (workdir / "f.txt").write_text("x\n", encoding="utf-8")
        subprocess.run(["git", "add", "-A"], cwd=workdir, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=workdir, check=True)

        prompt = base / "prompt.md"
        prompt.write_text("Implementer feladat — E09-R01\n", encoding="utf-8")
        out = base / "claude-args.txt"
        out.touch()
        fake = base / "fake-claude"
        fake.write_text(FAKE_CLAUDE, encoding="utf-8")
        fake.chmod(0o755)

        environment = dict(os.environ)
        environment.update(
            {
                "ROUND_ENGINE": engine,
                "CLAUDE_BIN": str(fake),
                "FAKE_CLAUDE_OUT": str(out),
                "FAKE_SIGNAL": str(workdir / ".codex-round-status"),
                "FAKE_WORKFILE": str(workdir / "munka.txt"),
                "MM_POLL_SECONDS": "1",
                # A SIGTERM→SIGKILL türelmi idő élesben 5 mp; ez a suite hamis,
                # azonnal kilépő binárissal mér, ezért ott tiszta fali óra
                # (E14-R13/H5 önjavító kör, 2026-09-05).
                "MM_KILL_GRACE_SECONDS": "1",
            }
        )
        environment.pop("ROUND_BRIEF", None)
        # A burkoló saját endpoint-döntésének útjából kitakarítjuk azt, amit
        # egy ÉLŐ implementer-session örökített ide (lásd a modul-docstring
        # ötödik ÉS hatodik mért hibamintáját) — enélkül a "nincs override"
        # asserciók a leszivárgott ambiens értéket mérnék, nem a `mm-round.sh`
        # tényleges viselkedését. Két forrás: a `mm-round.sh` SAJÁT
        # `external_endpoint` launch_env-je (ötödik minta — az első négy) ÉS a
        # `tools/codex-round.sh`/`tools/engine-profile.sh env <motor>`
        # EGY SZINTTEL FELJEBBI exportja, ami BÁRMELYIK motorral (nemcsak
        # minimax-szal) élő session Bash-hívásaként öröklődik (hatodik minta —
        # a maradék hét). `extra_env` alább még felülírhatja, ha egy teszt
        # szándékosan mást akar.
        for leaking_var in (
            "ANTHROPIC_BASE_URL",
            "ANTHROPIC_AUTH_TOKEN",
            "CLAUDE_CODE_AUTO_COMPACT_WINDOW",
            "MINIMAX_API_KEY",
            "CODEX_HOME",
            "CLAUDE_CONFIG_DIR",
            "ENGINE_MODEL",
            "ENGINE_STALL_MINUTES",
            "ENGINE_ROUND_TIMEOUT",
            "ENGINE_CONTEXT_WINDOW",
            "ENGINE_MAX_OUTPUT",
            "ENGINE_REASONING",
        ):
            environment.pop(leaking_var, None)
        if extra_env:
            environment.update(extra_env)

        subprocess.run(
            ["bash", str(WRAPPER), str(workdir), str(prompt), str(base / "round.log")],
            capture_output=True,
            text=True,
            env=environment,
            cwd=str(ROOT),
            timeout=timeout,
        )
        self.signal_text = (workdir / ".codex-round-status").read_text(encoding="utf-8")
        return out.read_text(encoding="utf-8")

    def test_a_native_claude_model_runs_without_an_endpoint_override(self) -> None:
        """Előfizetéses üzemmód: nincs base-url és nincs token — a config dir hitelesít."""
        captured = self.run_wrapper("sonnet-impl", extra_env={"MINIMAX_API_KEY": ""})
        self.assertIn("BASE_URL=<nincs>", captured)
        self.assertNotIn("AUTH_TOKEN=<van>", captured)
        self.assertIn("--model claude-sonnet-5", captured)

    def test_ambient_endpoint_env_does_not_leak_into_a_subscription_mode_run(self) -> None:
        """MÉRT hibaminta (E99-R17 H6 self-heal, 2026-08-20) — lásd a modul-
        docstring ötödik pontját. Ha ez a teszt maga is egy ROUND_ENGINE=
        minimax implementer-session Bash-hívásaként fut, az `os.environ`
        MÁR tartalmazza a szülő session saját MiniMax-endpoint exportjait;
        itt szándékosan ugyanazokat az ÉRTÉKEKET szimuláljuk (a `mm-round.sh`
        valódi MiniMax base-url konstansát), hogy a reprodukció a futtató
        környezettől függetlenül, determinisztikusan lefusson."""
        leaked_ambient_env = {
            "ANTHROPIC_BASE_URL": "https://api.minimax.io/anthropic",
            "ANTHROPIC_AUTH_TOKEN": "leaked-ambient-token",
            "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000",
            "MINIMAX_API_KEY": "leaked-ambient-key",
        }
        with patch.dict(os.environ, leaked_ambient_env):
            captured = self.run_wrapper("sonnet-impl", extra_env={"MINIMAX_API_KEY": ""})
        self.assertIn("BASE_URL=<nincs>", captured)
        self.assertNotIn("AUTH_TOKEN=<van>", captured)
        self.assertIn("COMPACT=<nincs>", captured)

    def test_ambient_engine_profile_env_does_not_leak_into_the_legacy_run(self) -> None:
        """MÉRT hibaminta (E99-R20 H6 self-heal, 2026-08-20) — lásd a modul-
        docstring hatodik pontját. Ha ez a teszt maga is egy ÉLŐ
        `ROUND_ENGINE=terra` implementer-session Bash-hívásaként fut, a
        `tools/codex-round.sh` motor-profil blokkja már exportálta a
        `tools/engine-profile.sh env terra` teljes kimenetét a szülő
        session-be; itt szándékosan ugyanazokat az ÉRTÉKEKET szimuláljuk
        (valódi mérés a boxon, 2026-08-20), hogy a reprodukció a futtató
        környezettől függetlenül, determinisztikusan lefusson."""
        leaked_ambient_env = {
            "CODEX_HOME": "/home/ubuntu/.codex-terra",
            "ENGINE_MODEL": "gpt-5.6-terra",
            "ENGINE_STALL_MINUTES": "12",
            "ENGINE_ROUND_TIMEOUT": "3600",
            "ENGINE_CONTEXT_WINDOW": "400000",
            "ENGINE_MAX_OUTPUT": "64000",
            "ENGINE_REASONING": "-",
        }
        with patch.dict(os.environ, leaked_ambient_env):
            captured = self.run_wrapper("", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("BASE_URL=https://api.minimax.io/anthropic", captured)
        self.assertIn("--model MiniMax-M3", captured)

    def test_the_effort_level_comes_from_the_registry(self) -> None:
        captured = self.run_wrapper("sonnet-impl", extra_env={"MINIMAX_API_KEY": ""})
        self.assertIn("--effort medium", captured)

    def test_the_implementer_preamble_is_prepended(self) -> None:
        """A mért hibaminták tiltása a claude-harness motorra is érvényes."""
        captured = self.run_wrapper("sonnet-impl", extra_env={"MINIMAX_API_KEY": ""})
        self.assertIn("PROMPT=# Implementer-preambulum", captured)

    def test_the_preamble_forbids_backgrounding_the_mandatory_gate(self) -> None:
        """MÉRT hibaminta (E99-R08 H6 self-heal, 2026-08-13): két egymást követő
        `sonnet-impl` javító kör (session 3f71b1fb-ee86-4206-b9a6-6f802768f679,
        majd a „resume" 665d8491-3352-416f-9ac8-f420c4936468) a kötelező
        `python3 -m pytest tools/tests -q` gate-et a Bash-eszköz saját
        `run_in_background: true` kapcsolójával küldte háttérbe, majd „Running
        the full pytest suite ... in the background ... I'll report back once
        it completes" bejelentéssel zárta a fordulót — jelzés és commit
        nélkül. A `claude -p` egy fordulós harness: a folyamat a forduló
        végén kilépett, ezzel a háttér-feladatot IS megölte, mielőtt bármi
        eredmény visszajutott volna — mindkét kísérlet exit 0-val
        `status=unknown`-ba halt, ami egy H6 haltot (ADR 0087 §2) okozott.
        Ugyanez az elv más hívó eszköz kontextusában már bizonyítva:
        `docs/LESSONS.md` L183."""
        captured = self.run_wrapper("sonnet-impl", extra_env={"MINIMAX_API_KEY": ""})
        self.assertIn("run_in_background", captured)

    def test_minimax_keeps_its_own_endpoint_and_token(self) -> None:
        """A visszakapcsolás garanciája (user-kérés 2026-08-06): az M3 sajátosságai
        (külső `/anthropic` endpoint + token) a Sonnet-üzemmód bevezetése után is
        érvényesek."""
        captured = self.run_wrapper("minimax", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("BASE_URL=https://api.minimax.io/anthropic", captured)
        self.assertIn("AUTH_TOKEN=<van>", captured)
        self.assertIn("--model MiniMax-M3", captured)
        self.assertNotIn("--effort", captured, "az M3-nak nincs effort-szintje a nyilvántartásban")

    def test_the_legacy_call_without_round_engine_stays_minimax(self) -> None:
        """ROUND_ENGINE nélkül a történeti alapértelmezés változatlan."""
        captured = self.run_wrapper("", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("BASE_URL=https://api.minimax.io/anthropic", captured)
        self.assertIn("--model MiniMax-M3", captured)

    def test_minimax_config_dir_stays_isolated(self) -> None:
        """Az M3 SAJÁT config dirje (~/.claude-minimax) nem keveredik a fő auth-tal."""
        row = registry_row("minimax")
        self.assertEqual(row[2], "~/.claude-minimax")
        captured = self.run_wrapper("minimax", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("CONFIG_DIR=" + str(Path.home() / ".claude-minimax"), captured)

    def test_sonnet_gets_its_own_tool_set_and_no_fake_compact_window(self) -> None:
        """Motor-specifikus tulajdonságok (user-kérés 2026-08-06)."""
        captured = self.run_wrapper("sonnet-impl", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("TodoWrite", captured, "a több-fájlos kör listavezetést kíván")
        self.assertIn("COMPACT=<nincs>", captured, "natív modellnél a hamis 1M ablak ártana")

    def test_minimax_keeps_the_compact_window_override(self) -> None:
        """Az M3 sajátja: a hamis 1M-es ablak KELL (az endpoint nem adja meg a
        valódit). A `TodoWrite` viszont 2026-08-06 óta MINDKÉT sávon ott van —
        a befejezetlen fa a lánc legdrágább hibaosztálya."""
        captured = self.run_wrapper("minimax", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("COMPACT=1000000", captured)

    def test_the_engine_specific_preamble_is_appended_for_sonnet(self) -> None:
        captured = self.run_wrapper("sonnet-impl", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("Motor-specifikus kiegészítés", captured)

    def test_minimax_gets_the_todo_tool_for_completion_discipline(self) -> None:
        """A félkész fa a lánc legdrágább hibaosztálya — a listavezetés ellenszer."""
        captured = self.run_wrapper("minimax", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("TodoWrite", captured)

    def test_the_minimax_specific_preamble_is_appended(self) -> None:
        captured = self.run_wrapper("minimax", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("Motor-specifikus kiegészítés — MiniMax M3", captured)

    def test_a_done_signal_without_work_is_downgraded_here_too(self) -> None:
        self.run_wrapper("minimax", extra_env={"MINIMAX_API_KEY": "k", "FAKE_NO_WORK": "1"})
        self.assertIn("status=unknown", self.signal_text)

    def test_a_done_signal_with_work_survives(self) -> None:
        self.run_wrapper("minimax", extra_env={"MINIMAX_API_KEY": "teszt-kulcs"})
        self.assertIn("status=done", self.signal_text)

    def test_a_noop_done_signal_is_kept_when_the_dispatcher_explicitly_allows_it(self) -> None:
        """MÉRT eset (E06-R27 H6 self-heal, 2026-08-13, mm-round.sh —
        codex-round.sh azonos logikája `test_qwen_implementer_hardening.py`
        `ClaimGuardTest`-jében fedve). Egy javító `sonnet-impl` forduló
        commitolt (`524397de`), de jelzés nélkül lépett ki; a dispatch-elt
        signal-recovery forduló jogosan `done`-t jelzett ÚJ commit/diff
        nélkül, mert a dolga a MÁR meglévő munka megerősítése volt — a régi
        `verify_claim` ezt tévesen `unknown`-ra fokozta le, mert a
        `scope_base` (az invokáció-kezdő HEAD) már az előző forduló
        commitját tartalmazta. `ROUND_VERIFY_NOOP_OK=1` teszi ezt a
        dispatcher szándéka szerint legitimmé."""
        self.run_wrapper(
            "minimax",
            extra_env={"MINIMAX_API_KEY": "teszt-kulcs", "FAKE_NO_WORK": "1", "ROUND_VERIFY_NOOP_OK": "1"},
        )
        self.assertIn("status=done", self.signal_text)
        self.assertIn("verify_noop_ok=1", self.signal_text)

    def test_a_process_that_keeps_running_after_signaling_is_killed_promptly(self) -> None:
        """MÉRT hibaminta (E06-R23 self-heal, ADR 0112, 2026-08-12): a Claude
        helyesen írta meg a jelzésfájlt, de a folyamata ennek ellenére
        percekig tovább futott (hat további commit a jelzés UTÁN, ~15 perccel
        később lépett csak ki magától). A burkolónak a jelzés megjelenése
        UTÁN azonnal ki kell lőnie a folyamatot — nem szabad megvárnia az
        elakadás-őrt vagy az abszolút időkorlátot."""
        started = time.monotonic()
        self.run_wrapper(
            "minimax",
            extra_env={
                "MINIMAX_API_KEY": "teszt-kulcs",
                "FAKE_CLAUDE_MODE": "hang-after-signal",
                "MM_POLL_SECONDS": "1",
                "MM_ROUND_TIMEOUT": "600",
                "MM_STALL_MINUTES": "10",
            },
            timeout=30,
        )
        elapsed = time.monotonic() - started
        self.assertIn("status=done", self.signal_text)
        self.assertNotIn("status=timeout", self.signal_text, "a jelzés a tény, nem az időtúllépés")
        self.assertNotIn("status=stalled", self.signal_text)
        self.assertLess(
            elapsed, 15,
            "a burkolónak pár másodpercen belül ki kell lőnie a folyamatot a jelzés után, "
            f"nem a 600s-es időkorlátig várnia (mért: {elapsed:.1f}s)",
        )

    def test_a_codex_harness_engine_is_rejected_by_this_wrapper(self) -> None:
        result = subprocess.run(
            ["bash", str(WRAPPER), "/tmp", "/tmp", "/tmp/x.log"],
            capture_output=True,
            text=True,
            env={**os.environ, "ROUND_ENGINE": "terra"},
            cwd=str(ROOT),
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
