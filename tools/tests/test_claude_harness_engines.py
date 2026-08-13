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
"""

import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

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
        self.assertEqual(row[12], "medium", "a --effort szint a reasoning oszlopból jön")

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
            }
        )
        environment.pop("ROUND_BRIEF", None)
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
